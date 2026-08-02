import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kolia/services/auth_service.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/google_drive_service.dart';
import 'package:kolia/services/file_export_service.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/screens/btk_form_page.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  TeamInfo? _currentTeam;
  List<Map<String, dynamic>> _localForms = [];
  Map<String, TeamInfo> _teamsMap = {};
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Get local data first and show it immediately
    final team = await AuthService.getLoggedInTeam();
    final local = await DatabaseHelper.instance.getAllForms();
    
    if (mounted) {
      setState(() {
        _currentTeam = team;
        _localForms = local;
      });
    }

    // 2. Fetch team customizations (might take time if offline)
    // AuthService.getTeamsWithCustomizations already uses Firestore cache
    final allTeamsList = await AuthService.getTeamsWithCustomizations();
    
    final Map<String, TeamInfo> tMap = {};
    for (var t in allTeamsList) {
      tMap[t.id] = t;
    }

    if (mounted) {
      setState(() {
        _teamsMap = tMap;
      });
    }
  }

  Future<void> _syncSingleForm(Map<String, dynamic> form) async {
    setState(() => _isSyncing = true);
    try {
      final dbId = form['db_id'];
      final fullLocalData = await DatabaseHelper.instance.getForm(dbId);
      if (fullLocalData == null) throw Exception("ლოკალური მონაცემები ვერ მოიძებნა");

      final dataToSync = DatabaseHelper.extractFormData(fullLocalData);
      
      await FirebaseService.saveForm(dataToSync, localDbId: dbId);
      await _loadInitialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ფორმა წარმატებით დასინქრონირდა'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('სინქრონიზაციის შეცდომა: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _uploadTodaysToDrive(List<Map<String, dynamic>> allForms) async {
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final todayStrDot = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}";
    
    debugPrint('ExportPage: Searching for forms with date: $todayStr or $todayStrDot');
    
    final todaysForms = allForms.where((f) {
      final rawDate = f['date'] ?? f['თარიღი'];
      if (rawDate == null) {
        debugPrint('ExportPage: Form ${f['btk_index'] ?? f['ბტკ ინდექსი'] ?? 'unknown'} has no date field');
        return false;
      }

      DateTime? formDate;
      if (rawDate is Timestamp) {
        formDate = rawDate.toDate();
      } else if (rawDate is DateTime) {
        formDate = rawDate;
      } else {
        final formDateStr = rawDate.toString().trim();
        debugPrint('ExportPage: Checking form ${f['btk_index'] ?? 'unknown'} with date string "$formDateStr"');
        
        if (formDateStr.startsWith(todayStr) || formDateStr.startsWith(todayStrDot)) return true;
        
        // Fallback 1: try parsing to DateTime
        try {
          formDate = DateTime.parse(formDateStr);
        } catch (_) {
          // Fallback 2: Handle DD.MM.YYYY or DD/MM/YYYY formats
          try {
            final parts = formDateStr.split(RegExp(r'[./-]'));
            if (parts.length >= 3) {
              int? d, m, y;
              if (parts[0].length == 4) { // YYYY.MM.DD
                y = int.tryParse(parts[0]);
                m = int.tryParse(parts[1]);
                d = int.tryParse(parts[2]);
              } else { // DD.MM.YYYY
                d = int.tryParse(parts[0]);
                m = int.tryParse(parts[1]);
                y = int.tryParse(parts[2]);
              }
              
              if (d != null && m != null && y != null) {
                formDate = DateTime(y, m, d);
              }
            }
          } catch (_) {}
        }
      }

      if (formDate != null) {
        return formDate.year == now.year && 
               formDate.month == now.month && 
               formDate.day == now.day;
      }

      return false;
    }).toList();

    if (todaysForms.isEmpty) {
      debugPrint('ExportPage: No forms found for today ($todayStr). Total forms checked: ${allForms.length}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('დღევანდელი ბლანკები ვერ მოიძებნა ($todayStr)')),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('დღევანდელი ბლანკები'),
        content: Text('ნამდვილად გსურთ დღევანდელი ${todaysForms.length} ბლანკის ატვირთვა Google Drive-ზე?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ატვირთვა')),
        ],
      ),
    );

    if (confirm == true) {
      await _uploadToDriveInternal(todaysForms);
    }
  }

  Future<void> _uploadAllToDrive(List<Map<String, dynamic>> allForms) async {
    // Include all forms that are not uploaded yet, regardless of source (local or cloud)
    final toUpload = allForms.where((f) => f['is_uploaded'] != true).toList();
    
    if (toUpload.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Drive-ზე ატვირთვა'),
          content: const Text('ყველა ბლანკი უკვე ატვირთულია Google Drive-ზე. გსურთ მათი თავიდან ატვირთვა?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('არა')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('დიახ')),
          ],
        ),
      );
      if (!mounted) return;
      if (confirm != true) return;
      toUpload.addAll(allForms);
    }

    await _uploadToDriveInternal(toUpload);
  }

  Future<void> _uploadToDriveInternal(List<Map<String, dynamic>> toUpload) async {
    int successCount = 0;
    int failCount = 0;

    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>('ემზადება...');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, _) => AlertDialog(
          title: const Text('Drive-ზე ატვირთვა'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, status, _) => Text(
                  status,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final String? uploadFolderId = await FirebaseService.getUploadFolderId();

    // Perform uploads in parallel for speed
    final List<Future<void>> uploadTasks = toUpload.map((form) async {
      final btkIndex = form['btk_index'] ?? form['ბტკ ინდექსი'] ?? 'Unknown';
      try {
        await GoogleDriveService.uploadFormAsGoogleDoc(form, parentFolderId: uploadFolderId);
        successCount++;
      } catch (e) {
        debugPrint('Drive upload error for $btkIndex: $e');
        failCount++;
      }
      progressNotifier.value = (successCount + failCount) / toUpload.length;
      statusNotifier.value = 'დასრულდა: $btkIndex\n(${successCount + failCount} / ${toUpload.length})';
    }).toList();

    await Future.wait(uploadTasks);
    
    if (mounted) {
      Navigator.pop(context); // Close progress dialog
      await _loadInitialData(); // Refresh UI to reflect upload status
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount ბლანკი წარმატებით აიტვირთა. ${failCount > 0 ? "$failCount ჩაიშალა." : ""}'), 
            backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showStats() async {
    setState(() => _isSyncing = true);
    try {
      final todayStats = await FirebaseService.getTodaysStats();
      final generalStats = await FirebaseService.getGeneralStats();
      if (!mounted) return;
      
      final int totalToday = todayStats.values.fold(0, (acc, val) => acc + val);
      final int totalGeneral = generalStats.values.fold(0, (acc, val) => acc + val);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return DefaultTabController(
              length: 2,
              child: AlertDialog(
                titlePadding: EdgeInsets.zero,
                title: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.analytics_outlined, color: Colors.teal),
                          const SizedBox(width: 12),
                          const Text('სტატისტიკა'),
                        ],
                      ),
                    ),
                    const TabBar(
                      tabs: [
                        Tab(text: 'დღეს'),
                        Tab(text: 'ჯამური'),
                      ],
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 350,
                  child: TabBarView(
                    children: [
                      _buildStatsList(todayStats, totalToday, 'დღევანდელი ბლანკები', isDark),
                      _buildStatsList(generalStats, totalGeneral, 'ჯამური ბლანკები', isDark),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('დახურვა')),
                ],
              ),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('შეცდომა: $e')));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Widget _buildStatsList(Map<String, int> stats, int total, String subtitle, bool isDark) {
    if (stats.isEmpty) {
      return const Center(child: Text('მონაცემები არ არის.'));
    }
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: isDark ? 0.2 : 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ჯამური რაოდენობა', 
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    )
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11, 
                      color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              Text(
                '$total', 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 32, 
                  color: Theme.of(context).colorScheme.primary,
                )
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        Expanded(
          child: ListView(
            shrinkWrap: true,
            children: stats.entries.map((e) {
              final team = _teamsMap[e.key] ?? AuthService.teams.firstWhere(
                (t) => t.id == e.key,
                orElse: () => const TeamInfo(id: '', name: 'Unknown', password: '', color: Colors.grey),
              );
              return ListTile(
                dense: true,
                leading: CircleAvatar(backgroundColor: team.color, radius: 6),
                title: Text(team.name),
                trailing: Text(e.value.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAllForAdmin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ყველას წაშლა (ADMIN)'),
        content: const Text('ნამდვილად გსურთ ყველა ბლანკის წაშლა Cloud-იდან და ლოკალური მეხსიერებიდან? ეს მოქმედება შეუქცევადია!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('ყველას წაშლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSyncing = true);
      try {
        await FirebaseService.deleteAllForms();
        await DatabaseHelper.instance.clearAllData();
        await _loadInitialData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ყველა მონაცემი წაშლილია')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('შეცდომა წაშლისას: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _syncAllLocal() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('სინქრონიზაციისთვის საჭიროა ინტერნეტთან კავშირი'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final count = await FirebaseService.syncAllUnsynced();
      await _loadInitialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count ბლანკი წარმატებით დასინქრონირდა'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('სინქრონიზაციის შეცდომა: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSyncOptions(List<Map<String, dynamic>> forms) {
    final isAdmin = _currentTeam?.isAdmin ?? false;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('აირჩიეთ სინქრონიზაციის ტიპი', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined, color: Colors.orange),
              title: const Text('Sync all to Firebase'),
              subtitle: const Text('გაუგზავნელი ბლანკების ატვირთვა'),
              onTap: () {
                Navigator.pop(context);
                _syncAllLocal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded, color: Colors.green),
              title: const Text('Bulk Export to CSV'),
              subtitle: const Text('ყველა ბლანკის ექსპორტი ერთ ფაილად'),
              onTap: () {
                Navigator.pop(context);
                _bulkExportCsv(forms);
              },
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined, color: Colors.blue),
              title: const Text('Upload Today\'s to Drive'),
              subtitle: const Text('მხოლოდ დღევანდელი ბლანკების ატვირთვა'),
              onTap: () {
                Navigator.pop(context);
                _uploadTodaysToDrive(forms);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_to_drive_outlined, color: Colors.blueGrey),
              title: const Text('Upload All to Drive'),
              subtitle: const Text('ყველა ბლანკის ატვირთვა Google Drive-ზე'),
              onTap: () {
                Navigator.pop(context);
                _uploadAllToDrive(forms);
              },
            ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.calendar_today_rounded, color: Colors.purple),
                title: const Text('Update All to Today'),
                subtitle: const Text('ყველა ბლანკის თარიღის განახლება დღევანდელით'),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('თარიღების განახლება'),
                      content: const Text('ნამდვილად გსურთ ყველა შენახული ბლანკის თარიღის შეცვლა დღევანდელით?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('არა')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('დიახ')),
                      ],
                    ),
                  );
                    if (confirm == true) {
                      setState(() => _isSyncing = true);
                      await DatabaseHelper.instance.updateAllDatesToCurrent();
                      await _loadInitialData();
                      if (mounted) {
                        setState(() => _isSyncing = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ყველა ბლანკის თარიღი განახლდა')),
                        );
                      }
                    }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    // Attempt to sync pending forms first when user pulls to refresh
    await FirebaseService.syncAllUnsynced();
    // Then reload local state
    await _loadInitialData();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirebaseService.getFormsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _localForms.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('ბლანკები')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        
        final cloudForms = snapshot.data ?? [];
        final Map<String, Map<String, dynamic>> combinedMap = {};

        // 1. Process cloud forms first
        for (var f in cloudForms) {
          final id = f['id'];
          if (id != null) {
            combinedMap[id] = {
              ...f,
              'source': 'cloud',
              'is_synced': true,
            };
          }
        }

        // 2. Process local forms and merge/replace duplicates
        for (var f in _localForms) {
          final dbId = f['db_id'];
          final String? cloudIdInLocal = f['id'] ?? (f['data'] is Map ? f['data']['id'] : null);
          final String? btkIndex = f['btk_index'] ?? f['ბტკ ინდექსი'] ?? (f['data'] is Map ? (f['data']['btk_index'] ?? f['data']['ბტკ ინდექსი']) : null);
          final String? teamId = f['team_id'] ?? (f['data'] is Map ? f['data']['team_id'] : null);
          
          final Map<String, dynamic> localFormProcessed = {
            ...f,
            if (f['data'] is Map) ...f['data'],
            'db_id': dbId,
            'source': 'local',
            'is_synced': f['is_synced'] == true,
          };

          // Try to find a matching cloud form by ID or by Index/Team fallback
          String? matchId;
          if (cloudIdInLocal != null && combinedMap.containsKey(cloudIdInLocal)) {
            matchId = cloudIdInLocal;
          } else if (btkIndex != null && btkIndex.isNotEmpty) {
            matchId = combinedMap.keys.firstWhere(
              (k) => (combinedMap[k]!['btk_index'] == btkIndex || combinedMap[k]!['ბტკ ინდექსი'] == btkIndex) && 
                     combinedMap[k]!['team_id'] == teamId,
              orElse: () => '',
            );
            if (matchId == '') matchId = null;
          }

          if (matchId != null) {
            // Already in cloud, update the cloud entry with local DB ID
            combinedMap[matchId]!['db_id'] = dbId;
            // Merge local data into cloud data to ensure we have all fields (like db_id)
            combinedMap[matchId] = {
              ...localFormProcessed,
              ...combinedMap[matchId]!,
              'db_id': dbId, // Priority to local DB ID
            };
            continue;
          }

          // If it was synced but is gone from cloud (deleted by supervisor), skip it
          // However, we should be careful here. If it's missing from combinedMap 
          // but was marked as synced, it might be due to Firestore lag/pending writes.
          // We'll show it anyway if it was marked as synced but not found in cloud map.
          // if (cloudIdInLocal != null && f['is_synced'] == true) {
          //   continue;
          // }

          // Not in cloud yet
          combinedMap['local_$dbId'] = localFormProcessed;
        }

        final isAdmin = _currentTeam?.isAdmin ?? false;
        var forms = combinedMap.values.toList();

        forms.sort((a, b) {
          final dateA = a['date'] ?? '';
          final dateB = b['date'] ?? '';
          return dateB.compareTo(dateA);
        });

        return Scaffold(
          appBar: AppBar(
            leading: isAdmin ? IconButton(
              icon: const Icon(Icons.cloud_outlined, color: Colors.blue),
              onPressed: () => _showSyncOptions(forms),
              tooltip: 'სინქრონიზაცია',
            ) : null,
            title: const Text('ბლანკები'),
            actions: [
              if (_isSyncing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                if (!isAdmin && forms.any((f) => f['source'] == 'local'))
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: Colors.orange),
                    onPressed: _syncAllLocal,
                    tooltip: 'ყველას სინქრონიზაცია',
                  ),
                if (isAdmin) ...[
                  IconButton(
                    icon: const Icon(Icons.cloud_upload_rounded, color: Colors.blueAccent),
                    onPressed: () => _uploadTodaysToDrive(forms),
                    tooltip: 'დღევანდელი ბლანკების ატვირთვა Drive-ზე',
                  ),
                  IconButton(
                    icon: const Icon(Icons.bar_chart_rounded, color: Colors.teal),
                    onPressed: _showStats,
                    tooltip: 'დღევანდელი სტატისტიკა',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                    onPressed: _deleteAllForAdmin,
                    tooltip: 'ყველას წაშლა (Admin)',
                  ),
                ],
              ],
            ],
          ),
          body: forms.isEmpty 
            ? RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('მონაცემები არ არის'),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: forms.length,
                itemBuilder: (context, index) {
                  final rawForm = forms[index];
                  final String teamId = rawForm['team_id'] ?? '';
                  
                  // Resolve current team info from map if available (for consistency across history)
                  final customizedTeam = _teamsMap[teamId];
                  final String teamName = customizedTeam?.name ?? rawForm['team_name'] ?? 'Unknown';
                  final Color? customizedColor = customizedTeam?.color;
                  
                  // Merge resolved info into form data for downstream use
                  final form = {
                    ...rawForm,
                    'team_name': teamName,
                    if (customizedColor != null) 'team_name': teamName, // Redundant but safe
                    if (customizedColor != null) 'team_color': customizedColor.toARGB32(),
                  };

                  final baseTeamForCurrent = _currentTeam != null 
                      ? AuthService.teams.firstWhere((t) => t.id == _currentTeam!.id, orElse: () => _currentTeam!)
                      : null;

                  final bool isOwnForm = _currentTeam != null && (
                    _currentTeam!.id == teamId || 
                    ((teamId.isEmpty || teamId == 'unknown_id') && (teamName == _currentTeam!.name || (baseTeamForCurrent != null && teamName == baseTeamForCurrent.name)))
                  );

                  final bool canEdit = isOwnForm || isAdmin;
                  final bool isSynced = form['is_synced'] == true;
                  final String source = form['source'] ?? 'local';
                  
                  // Priority: 1. Current customization, 2. Stored snapshot, 3. Fallback
                  Color displayColor = customizedColor ?? Colors.grey;
                  if (customizedColor == null) {
                    if (form['team_color'] != null) {
                      try {
                        displayColor = Color(form['team_color'] is int ? form['team_color'] : int.parse(form['team_color'].toString()));
                      } catch (_) {}
                    } else {
                      final baseTeam = AuthService.teams.firstWhere(
                        (t) => t.id == teamId,
                        orElse: () => AuthService.teams.firstWhere(
                          (t) => t.name == teamName,
                          orElse: () => const TeamInfo(id: '', name: '', password: '', color: Colors.grey),
                        ),
                      );
                      displayColor = baseTeam.color;
                    }
                  }

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Stack(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: displayColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.description_rounded, color: displayColor),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isSynced ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                                size: 14,
                                color: isSynced ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        form['btk_index'] ?? 'ბტკ ინდექსის გარეშე',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$teamName • ${form['date'] ?? 'თარიღი არაა'}'),
                          if (form['edited_by_admin'] == true)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.5),
                              ),
                              child: const Text('EDITED BY SUPERVISOR', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber)),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BtkFormPage(
                                  cloudData: source == 'cloud' ? form : null,
                                  formId: source == 'local' ? form['db_id'] : null,
                                  readOnly: !canEdit,
                                ),
                              ),
                            ).then((_) => _loadInitialData()),
                            icon: Icon(canEdit ? Icons.edit_rounded : Icons.remove_red_eye_rounded,
                              color: canEdit ? Colors.orange : Colors.blueGrey),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (val) {
                              if (val == 'sync') _syncSingleForm(form);
                              if (val == 'pdf') _savePdf(form);
                              if (val == 'csv') _saveCsv(form);
                              if (val == 'drive') _uploadToDrive(form);
                              if (val == 'delete') _deleteForm(form);
                            },
                            itemBuilder: (context) => [
                              if (!isSynced)
                                const PopupMenuItem(
                                  value: 'sync',
                                  child: Row(
                                    children: [
                                      Icon(Icons.sync_rounded, color: Colors.orange, size: 20),
                                      SizedBox(width: 12),
                                      Text('სინქრონიზაცია'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'pdf',
                                child: Row(
                                  children: [
                                    Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 20),
                                    SizedBox(width: 12),
                                    Text('ჩამოტვირთვა (PDF)'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'csv',
                                child: Row(
                                  children: [
                                    Icon(Icons.table_chart_rounded, color: Colors.green, size: 20),
                                    SizedBox(width: 12),
                                    Text('ჩამოტვირთვა (CSV/Excel)'),
                                  ],
                                ),
                              ),
                              if (isSynced && isAdmin)
                                PopupMenuItem(
                                  value: 'drive',
                                  child: Row(
                                    children: [
                                      Icon(
                                        form['is_uploaded'] == true ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded, 
                                        color: form['is_uploaded'] == true ? Colors.green : Colors.blue, 
                                        size: 20
                                      ),
                                      const SizedBox(width: 12),
                                      Text(form['is_uploaded'] == true ? 'Drive (თავიდან ატვირთვა)' : 'Google Drive'),
                                    ],
                                  ),
                                ),
                              if (isAdmin || isOwnForm)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
                                      const SizedBox(width: 12),
                                      Text('წაშლა${isAdmin && !isOwnForm ? " (Admin)" : ""}'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        );
      },
    );
  }

  void _deleteForm(Map<String, dynamic> form) async {
    final String? cloudId = form['id'];
    final int? dbId = form['db_id'];

    final String title = cloudId != null ? 'ბლანკის წაშლა Cloud-იდან' : 'ბლანკის წაშლა';
    final String content = cloudId != null 
      ? 'ნამდვილად გსურთ ბლანკის "${form['btk_index']}" წაშლა ყველგან? ეს მოქმედება შეუქცევადია.'
      : 'ნამდვილად გსურთ ბლანკის "${form['btk_index']}" წაშლა ლოკალური მეხსიერებიდან?';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('წაშლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSyncing = true);
      try {
        if (cloudId != null) {
          await FirebaseService.deleteForm(cloudId);
        }
        if (dbId != null) {
          await DatabaseHelper.instance.deleteForm(dbId);
        }
        await _loadInitialData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ბლანკი წარმატებით წაიშალა')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('წაშლის შეცდომა: $e'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => _isSyncing = false);
      }
    }
  }

  void _savePdf(Map<String, dynamic> form) async {
    final html = GoogleDriveService.generateHtmlContent(form);
    await FileExportService.savePdf(form, html);
  }

  void _saveCsv(Map<String, dynamic> form) async {
    try {
      final path = await FileExportService.saveCSVToFile(form);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV შენახულია: $path'),
            backgroundColor: Colors.green,
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV შეცდომა: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _bulkExportCsv(List<Map<String, dynamic>> forms) async {
    setState(() => _isSyncing = true);
    try {
      final path = await FileExportService.saveAllToCSV(forms);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ექსპორტი დასრულდა: $path'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ექსპორტის შეცდომა: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _uploadToDrive(Map<String, dynamic> form) async {
    final progressNotifier = ValueNotifier<double>(0);
    final statusNotifier = ValueNotifier<String>('იტვირთება...');

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) => AlertDialog(
            title: const Text('Google Drive'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, _) => Text(status),
                ),
              ],
            ),
          ),
        ),
      );
      
      final String? uploadFolderId = await FirebaseService.getUploadFolderId();
      await GoogleDriveService.uploadFormAsGoogleDoc(form, parentFolderId: uploadFolderId);
      
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('წარმატებით აიტვირთა Google Drive-ზე!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drive შეცდომა: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
