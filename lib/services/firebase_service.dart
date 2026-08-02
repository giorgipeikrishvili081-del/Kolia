import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kolia/services/auth_service.dart';
import 'package:kolia/services/database_helper.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  static CollectionReference get _formsCollection => _firestore.collection('btk_forms');
  static CollectionReference get _teamsCollection => _firestore.collection('teams');

  static Future<void> updateTeamCustomization(String teamId, String name, int colorValue) async {
    await _teamsCollection.doc(teamId).set({
      'name': name,
      'color': colorValue,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<Map<String, Map<String, dynamic>>> getTeamCustomizations() async {
    try {
      final snapshot = await _teamsCollection.get(const GetOptions(source: Source.serverAndCache));
      Map<String, Map<String, dynamic>> customizations = {};
      for (var doc in snapshot.docs) {
        customizations[doc.id] = doc.data() as Map<String, dynamic>;
      }
      return customizations;
    } catch (e) {
      debugPrint('Error fetching team customizations: $e');
      return {};
    }
  }

  static Future<String> saveForm(Map<String, dynamic> data, {int? localDbId}) async {
    // Check connectivity first to prevent duplicate "ghost" forms in Firestore cache
    // We only want to save to Firestore when online, as we manage offline state in SQLite.
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw Exception("კავშირი არ არის. ბლანკი შენახულია მხოლოდ ლოკალურად.");
    }

    final team = await AuthService.getLoggedInTeam();
    final teamId = team?.id ?? 'unknown_id';
    final teamName = team?.name ?? 'Unknown Team';
    final teamColor = team?.color.toARGB32();

    // Add metadata
    final String? existingTeamId = data['team_id'];
    if (existingTeamId == null || existingTeamId == 'unknown_id' || (team != null && !team.isAdmin && existingTeamId == teamId)) {
      data['team_id'] = teamId;
      data['team_name'] = teamName;
      if (teamColor != null) {
        data['team_color'] = teamColor;
      }
    } else if (team?.isAdmin == true && existingTeamId != teamId) {
      data['edited_by_admin'] = true;
    }

    data['updated_at'] = FieldValue.serverTimestamp();
    if (data['created_at'] == null) {
      data['created_at'] = FieldValue.serverTimestamp();
    }
    data['is_uploaded'] = false;

    String cloudId;
    // Save to Firestore
    if (data['id'] != null) {
      cloudId = data['id'];
      await _formsCollection.doc(cloudId).set(data, SetOptions(merge: true));
    } else {
      // Defensive: Check if a form with the same BTK Index and Team ID already exists
      // to prevent duplicates if a previous sync attempt was interrupted.
      final btkIndex = data['btk_index'] ?? data['ბტკ ინდექსი'];
      if (btkIndex != null && btkIndex.toString().isNotEmpty) {
        final existing = await _formsCollection
            .where('team_id', isEqualTo: data['team_id'])
            .where('btk_index', isEqualTo: btkIndex)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          cloudId = existing.docs.first.id;
          await _formsCollection.doc(cloudId).set(data, SetOptions(merge: true));
        } else {
          final docRef = await _formsCollection.add(data);
          cloudId = docRef.id;
          await docRef.update({'id': cloudId});
        }
      } else {
        final docRef = await _formsCollection.add(data);
        cloudId = docRef.id;
        await docRef.update({'id': cloudId});
      }
    }

    // Mark as synced locally if db_id was provided
    if (localDbId != null) {
      await DatabaseHelper.instance.markAsSynced(localDbId, cloudId: cloudId);
    }

    return cloudId;
  }

  static Future<void> markAsUploadedToDrive(String cloudId) async {
    await _formsCollection.doc(cloudId).update({'is_uploaded': true});
  }

  /// Fetches all forms submitted by a specific team
  static Future<List<Map<String, dynamic>>> getFormsByTeam(String teamId) async {
    final snapshot = await _formsCollection
        .where('team_id', isEqualTo: teamId)
        .get(const GetOptions(source: Source.serverAndCache));

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['id'] == null) {
        data['id'] = doc.id;
      }
      return data;
    }).toList();
  }

  static Map<String, dynamic>? _cachedConfig;

  /// Fetches remote configuration (like the Google Drive Map Folder ID)
  static Future<Map<String, dynamic>> getAppConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    try {
      final doc = await _firestore.collection('config').doc('settings').get(
        const GetOptions(source: Source.serverAndCache),
      );
      _cachedConfig = doc.data() ?? {};
      return _cachedConfig!;
    } catch (e) {
      return {};
    }
  }

  static Future<String?> getUploadFolderId() async {
    final config = await getAppConfig();
    return config['upload_folder_id']?.toString();
  }

  static bool _isSyncing = false;

  static Future<int> syncAllUnsynced() async {
    if (_isSyncing) {
      debugPrint('FirebaseService: Sync already in progress, skipping.');
      return 0;
    }

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      debugPrint('FirebaseService: No internet, skipping sync.');
      return 0;
    }
    
    _isSyncing = true;
    try {
      final unsynced = await DatabaseHelper.instance.getUnsyncedForms();

      if (unsynced.isEmpty) return 0;

      int count = 0;
      for (var form in unsynced) {
        try {
          final dbId = form['db_id'] as int;
          final dataToSync = DatabaseHelper.extractFormData(form);
          
          await saveForm(dataToSync, localDbId: dbId);
          count++;
        } catch (e) {
          debugPrint('Failed to sync form ${form['db_id']}: $e');
        }
      }
      return count;
    } finally {
      _isSyncing = false;
    }
  }

  static Stream<List<Map<String, dynamic>>> getFormsStream() {
    return _formsCollection
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        // Ensure the ID is present in the data map
        if (data['id'] == null) {
          data['id'] = doc.id;
        }
        // Include metadata to help the UI detect "ghost" forms (local Firestore cache)
        data['has_pending_writes'] = doc.metadata.hasPendingWrites;
        return data;
      }).toList();
    });
  }

  static Future<void> deleteForm(String id) async {
    await _formsCollection.doc(id).delete();
  }

  static Future<void> deleteAllForms() async {
    final snapshots = await _formsCollection.get();
    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }
  }

  static Future<Map<String, int>> getTodaysStats() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    
    final snapshot = await _formsCollection
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .get(const GetOptions(source: Source.serverAndCache));

    Map<String, int> stats = {};
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Favor stable team_id for stats aggregation, fallback to name for legacy
      final teamKey = data['team_id'] ?? data['team_name'] ?? 'Unknown Team';
      stats[teamKey] = (stats[teamKey] ?? 0) + 1;
    }
    return stats;
  }

  static Future<Map<String, int>> getGeneralStats() async {
    final snapshot = await _formsCollection.get(const GetOptions(source: Source.serverAndCache));

    Map<String, int> stats = {};
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Favor stable team_id for stats aggregation, fallback to name for legacy
      final teamKey = data['team_id'] ?? data['team_name'] ?? 'Unknown Team';
      stats[teamKey] = (stats[teamKey] ?? 0) + 1;
    }
    return stats;
  }

  static Future<List<Map<String, dynamic>>> getAllForms() async {
    final snapshot = await _formsCollection.get(const GetOptions(source: Source.serverAndCache));
    return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
  }
}
