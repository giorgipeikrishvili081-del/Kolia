import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kolia/services/auth_service.dart';
import 'package:kolia/services/database_helper.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection reference
  static CollectionReference get _formsCollection => _firestore.collection('btk_forms');

  static Future<String> saveForm(Map<String, dynamic> data, {int? localDbId}) async {
    final team = await AuthService.getLoggedInTeam();
    final teamId = team?.id ?? 'unknown_id';
    final teamName = team?.name ?? 'Unknown Team';
    final teamColor = team?.color.value;

    // Add metadata
    final String? existingTeamId = data['team_id'];
    if (existingTeamId == null || existingTeamId == 'unknown_id' || (team != null && !team.isAdmin && existingTeamId == teamId)) {
      // Update team info if it's new, unknown, or the team is updating their own form
      data['team_id'] = teamId;
      data['team_name'] = teamName;
      if (teamColor != null) {
        data['team_color'] = teamColor;
      }
    } else if (team?.isAdmin == true && existingTeamId != teamId) {
      // If admin/supervisor edits another team's form, don't overwrite team_id or team_name
      // Just mark it as edited by supervisor
      data['edited_by_admin'] = true;
    }

    data['updated_at'] = FieldValue.serverTimestamp();
    if (data['created_at'] == null) {
      data['created_at'] = FieldValue.serverTimestamp();
    }
    // Any save (new or update) resets the Drive upload status to allow re-uploading edited content
    data['is_uploaded'] = false;

    String cloudId;
    // Save to Firestore
    if (data['id'] != null) {
      cloudId = data['id'];
      await _formsCollection.doc(cloudId).set(data, SetOptions(merge: true));
    } else {
      final docRef = await _formsCollection.add(data);
      cloudId = docRef.id;
      await docRef.update({'id': cloudId});
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

  static Future<int> syncAllUnsynced() async {
    final localForms = await DatabaseHelper.instance.getAllForms();
    final unsynced = localForms.where((f) => f['is_synced'] == false).toList();

    if (unsynced.isEmpty) return 0;

    int count = 0;
    for (var form in unsynced) {
      try {
        final dbId = form['db_id'] as int;
        
        // Extract the actual form data.
        // In BtkFormPage, the form values are stored under the 'data' key in the local record.
        Map<String, dynamic> dataToSync;
        if (form['data'] != null && form['data'] is Map) {
          dataToSync = Map<String, dynamic>.from(form['data']);
        } else {
          dataToSync = Map<String, dynamic>.from(form);
          dataToSync.remove('db_id');
          dataToSync.remove('is_synced');
          dataToSync.remove('is_uploaded');
          dataToSync.remove('data');
        }
        
        await saveForm(dataToSync, localDbId: dbId);
        count++;
      } catch (e) {
        print('Failed to sync form ${form['db_id']}: $e');
      }
    }
    return count;
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
        .get();

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
    final snapshot = await _formsCollection.get();

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
    final snapshot = await _formsCollection.get();
    return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
  }
}
