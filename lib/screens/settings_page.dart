import 'package:flutter/material.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/services/auth_service.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/google_drive_service.dart';
import 'package:kolia/services/form_data_store.dart';
import 'package:kolia/services/theme_manager.dart';
import 'package:kolia/services/app_state.dart';
import 'package:kolia/main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TeamInfo? _currentTeam;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadTeamInfo();
  }

  Future<void> _loadTeamInfo() async {
    final team = await AuthService.getLoggedInTeam();
    if (mounted) {
      setState(() {
        _currentTeam = team;
      });
    }
  }

  void _syncData() async {
    setState(() => _isSyncing = true);
    try {
      final count = await FirebaseService.syncAllUnsynced();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0 ? '$count ბლანკი წარმატებით დასინქრონირდა' : 'ყველა მონაცემი სინქრონიზებულია'),
            backgroundColor: Colors.green,
          ),
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

  void _showSyncOptions() {
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
                _syncData();
              },
            ),
            if (_currentTeam?.isAdmin == true)
              ListTile(
                leading: const Icon(Icons.add_to_drive_outlined, color: Colors.blue),
                title: const Text('Sync all to Drive'),
                subtitle: const Text('ყველა ბლანკის ატვირთვა Google Drive-ზე'),
                onTap: () {
                  Navigator.pop(context);
                  _syncAllToDrive();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncAllToDrive() async {
    setState(() => _isSyncing = true);
    try {
      final local = await FormDataStore.savedForms;
      final cloudForms = await FirebaseService.getAllForms();
      
      final Map<String, Map<String, dynamic>> combinedMap = {};
      for (var f in cloudForms) {
        final id = f['id'];
        if (id != null) combinedMap[id] = {...f, 'source': 'cloud'};
      }
      for (var f in local) {
        final dbId = f['db_id'];
        if (dbId == null) continue;
        final key = 'local_$dbId';
        combinedMap[key] = {
          ...(f['data'] is Map ? f['data'] : (f as Map<String, dynamic>)),
          'db_id': dbId,
          'source': 'local',
        };
      }

      final allForms = combinedMap.values.toList();
      if (allForms.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('მონაცემები არ მოიძებნა')));
        return;
      }

      final toUpload = allForms.where((f) => f['is_uploaded'] != true).toList();
      List<Map<String, dynamic>> formsToProcess = toUpload;

      if (toUpload.isEmpty) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('სინქრონიზაცია'),
            content: const Text('ყველა ბლანკი უკვე ატვირთულია Google Drive-ზე. გსურთ მათი თავიდან ატვირთვა?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('არა')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('დიახ, თავიდან ატვირთვა')),
            ],
          ),
        );
        if (confirm == true) {
          formsToProcess = allForms;
        } else {
          return;
        }
      }

      int successCount = 0;
      for (var form in formsToProcess) {
        try {
          await GoogleDriveService.uploadFormAsGoogleDoc(form);
          successCount++;
        } catch (e) {
          debugPrint('Drive upload error: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$successCount ბლანკი წარმატებით აიტვირთა Drive-ზე'), 
            backgroundColor: Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('შეცდომა: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showStats() async {
    setState(() => _isSyncing = true);
    try {
      final todayStats = await FirebaseService.getTodaysStats();
      final generalStats = await FirebaseService.getGeneralStats();
      if (!mounted) return;

      final int totalToday = todayStats.values.fold(0, (sum, val) => sum + val);
      final int totalGeneral = generalStats.values.fold(0, (sum, val) => sum + val);

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
                height: 300,
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
    return FutureBuilder<List<TeamInfo>>(
      future: AuthService.getTeamsWithCustomizations(),
      builder: (context, snapshot) {
        final teams = snapshot.data ?? [];
        final Map<String, TeamInfo> teamLookup = {for (var t in teams) t.id: t};

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
                  final team = teamLookup[e.key] ?? 
                    AuthService.teams.firstWhere(
                      (t) => t.id == e.key,
                      orElse: () => AuthService.teams.firstWhere(
                        (t) => t.name == e.key,
                        orElse: () => TeamInfo(id: '', name: e.key, password: '', color: Colors.grey),
                      ),
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
    );
  }

  void _showEditNameDialog() async {
    final controller = TextEditingController(text: _currentTeam?.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('გუნდის სახელის შეცვლა'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ახალი სახელი',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('შენახვა'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _currentTeam?.name) {
      await AuthService.updateTeamInfo(name: newName);
      teamNameNotifier.value = newName;
      await _loadTeamInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('სახელი წარმატებით შეიცვალა'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _showEditColorDialog() async {
    final List<Color> colors = [
      Colors.blue,
      Colors.blueGrey,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.brown,
      Colors.black,
    ];

    final Color? selectedColor = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('აირჩიეთ ფერი'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: colors.length,
            itemBuilder: (context, index) {
              final color = colors[index];
              return InkWell(
                onTap: () => Navigator.pop(context, color),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _currentTeam?.color == color ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('დახურვა')),
        ],
      ),
    );

    if (selectedColor != null && selectedColor != _currentTeam?.color) {
      await AuthService.updateTeamInfo(color: selectedColor);
      teamColorNotifier.value = selectedColor;
      await _loadTeamInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ფერი წარმატებით შეიცვალა'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _clearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('წავშალოთ ყველა მონაცემი?'),
        content: const Text('ეს წაშლის ყველა გაგზავნილ ფორმას და დრაფტს. მოქმედების გაუქმება შეუძლებელია.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('ყველაფრის წაშლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.clearAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ყველა მონაცემი წაშლილია'))
        );
      }
    }
  }

  void _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('გამოსვლა'),
        content: const Text('დარწმუნებული ხართ რომ გსურთ სისტემიდან გამოსვლა?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('გამოსვლა', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      loginNotifier.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('პარამეტრები', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildSectionHeader('პროფილი'),
          ValueListenableBuilder<String>(
            valueListenable: teamNameNotifier,
            builder: (context, teamName, _) {
              return ValueListenableBuilder<Color>(
                valueListenable: teamColorNotifier,
                builder: (context, teamColor, _) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: teamColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.groups_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  teamName.isNotEmpty ? teamName : 'იტვირთება...', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'ავტორიზებული გუნდი', 
                                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _handleLogout,
                            icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                            label: const Text('შეცვლა', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Theme.of(context).colorScheme.primary,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('მონაცემების მართვა'),
          _buildSettingTile(
            icon: Icons.storage_rounded,
            title: 'ლოკალური ქეშის გასუფთავება',
            subtitle: 'დროებითი მონაცემების წაშლა',
            onTap: _clearData,
          ),
          _buildSettingTile(
            icon: Icons.sync_rounded,
            title: 'მონაცემების სინქრონიზაცია',
            subtitle: 'Firebase ან Google Drive',
            trailing: _isSyncing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _isSyncing ? null : _showSyncOptions,
          ),
          _buildSettingTile(
            icon: Icons.analytics_outlined,
            title: 'სტატისტიკა',
            subtitle: 'დღევანდელი და ჯამური მონაცემები',
            onTap: _isSyncing ? null : _showStats,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('პრეფერენსები'),
          _buildSettingTile(
            icon: Icons.edit_note_rounded,
            title: 'გუნდის სახელის შეცვლა',
            subtitle: 'შეცვალეთ თქვენი გუნდის სახელი',
            onTap: _showEditNameDialog,
          ),
          _buildSettingTile(
            icon: Icons.palette_outlined,
            title: 'გუნდის ფერის შეცვლა',
            subtitle: 'შეცვალეთ აპლიკაციის თემის ფერი',
            onTap: _showEditColorDialog,
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              final bool isDark = Theme.of(context).brightness == Brightness.dark;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: SwitchListTile(
                  secondary: Icon(
                    isDark ? Icons.dark_mode : Icons.dark_mode_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('ბნელი რეჟიმი', style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: const Text('აპლიკაციის იერსახის მორგება'),
                  value: isDark,
                  onChanged: (v) async {
                    await ThemeManager.setTheme(v ? ThemeMode.dark : ThemeMode.light);
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('შესახებ'),
          _buildSettingTile(
            icon: Icons.info_outline_rounded,
            title: 'აპლიკაციის ვერსია',
            subtitle: 'v1.4',
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: _handleLogout,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('გამოსვლა', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey.shade300,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)) : null,
        trailing: trailing ?? const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
