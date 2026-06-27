import 'package:flutter/material.dart';
import 'package:kolia/screens/btk_form_page.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/services/auth_service.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/screens/drafts_page.dart';
import 'package:kolia/screens/plant_id_page.dart';
import 'package:kolia/services/app_state.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function() onNavigateToExports;
  final VoidCallback onNavigateToSettings;

  const HomeScreen({
    super.key,
    required this.onNavigateToExports,
    required this.onNavigateToSettings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentDrafts = [];
  int _unsyncedCount = 0;
  Map<String, TeamInfo> _teamCache = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final teams = await AuthService.getTeamsWithCustomizations();
    final drafts = await DatabaseHelper.instance.getAllDrafts();
    final forms = await DatabaseHelper.instance.getAllForms();
    if (mounted) {
      setState(() {
        _teamCache = {for (var t in teams) t.id: t};
        _recentDrafts = drafts.take(3).toList();
        _unsyncedCount = forms.where((f) => f['is_synced'] == false).length;
      });
    }
  }

  Future<void> _loadRecentDrafts() async {
    final teams = await AuthService.getTeamsWithCustomizations();
    final drafts = await DatabaseHelper.instance.getAllDrafts();
    final forms = await DatabaseHelper.instance.getAllForms();
    if (mounted) {
      setState(() {
        _teamCache = {for (var t in teams) t.id: t};
        _recentDrafts = drafts.take(3).toList();
        _unsyncedCount = forms.where((f) => f['is_synced'] == false).length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadRecentDrafts,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 24, right: 64, bottom: 16),
                centerTitle: false,
                title: ValueListenableBuilder<String>(
                  valueListenable: teamNameNotifier,
                  builder: (context, teamName, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'სამუშაო სივრცე',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        if (teamName.isNotEmpty)
                          ValueListenableBuilder<Color>(
                            valueListenable: teamColorNotifier,
                            builder: (context, teamColor, _) {
                              return Text(
                                teamName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: teamColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                IconButton(
                  onPressed: widget.onNavigateToSettings,
                  icon: Icon(Icons.tune_rounded, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(width: 8),
              ],
            ),

            // Continue Research (Drafts)
            if (_recentDrafts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ბოლო დრაფტები', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (context) => const DraftsPage())
                            ).then((_) => _loadRecentDrafts()),
                            child: const Text('ყველას ნახვა'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._recentDrafts.map((d) => _buildDraftTile(d)),
                    ],
                  ),
                ),
              ),

            // Cloud Forms (Realtime)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('ბლანკები',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        TextButton(
                          onPressed: () => widget.onNavigateToExports(),
                          child: const Text('ყველას ნახვა'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: FirebaseService.getFormsStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                        if (!snapshot.hasData) return const Center(child: LinearProgressIndicator());
                        
                        final forms = snapshot.data!.take(3).toList();
                        if (forms.isEmpty) return const Text('ღრუბელში მონაცემები ჯერ არ არის', style: TextStyle(fontSize: 12, color: Colors.grey));

                        return Column(
                          children: forms.map((f) => _buildCloudFormTile(f)).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Primary Actions
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ძირითადი ხელსაწყოები', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    _buildPrimaryAction(
                      title: 'ბტკ-ის ბლანკი',
                      desc: 'კომპლექსური საველე კვლევა',
                      icon: Icons.assignment_rounded,
                      color: Colors.blueGrey.shade700,
                      onTap: () => Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const BtkFormPage())
                      ).then((_) => _loadRecentDrafts()),
                    ),
                  ],
                ),
              ),
            ),

            // Utilities Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: const Text('დამხმარე ხელსაწყოები', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                delegate: SliverChildListDelegate([
                  _buildToolTile(
                    title: 'მცენარის ID',
                    icon: Icons.filter_center_focus_rounded,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PlantIdPage()),
                    ),
                  ),
                  _buildToolTile(
                    title: 'ისტორია',
                    icon: Icons.history_rounded,
                    badgeCount: _unsyncedCount,
                    onTap: () => widget.onNavigateToExports().then((_) => _loadRecentDrafts()),
                  ),
                  _buildToolTile(
                    title: 'სტატისტიკა',
                    icon: Icons.bar_chart_rounded,
                    onTap: _showStatisticsDialog,
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudFormTile(Map<String, dynamic> form) {
    final String formTeamId = form['team_id'] ?? '';
    final String initialTeamName = form['team_name'] ?? 'Unknown';
    
    final customizedTeam = _teamCache[formTeamId];
    
    final String displayTeamName = customizedTeam?.name ?? initialTeamName;
    final Color displayColor = customizedTeam?.color ?? Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Icon(Icons.cloud_done_outlined, size: 20, color: displayColor),
        title: Text(form['btk_index'] ?? 'უსახელო', 
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Row(
          children: [
            Expanded(
              child: Text('გუნდი: $displayTeamName • ${form['date']}', 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            ),
            if (form['edited_by_admin'] == true)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.5),
                ),
                child: const Text('ED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber)),
              ),
          ],
        ),
        trailing: const Icon(Icons.remove_red_eye_outlined, size: 14, color: Colors.grey),
        onTap: () async {
          final currentTeam = await AuthService.getLoggedInTeam();
          final bool isAdmin = currentTeam?.isAdmin ?? false;
          
          final bool isOwnForm = currentTeam != null && 
              (currentTeam.id == formTeamId || (formTeamId.isEmpty && currentTeam.name == displayTeamName));
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BtkFormPage(
                  cloudData: form,
                  readOnly: !(isOwnForm || isAdmin), // Admin can edit any form
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _showStatisticsDialog() async {
    final todayStats = await FirebaseService.getTodaysStats();
    final generalStats = await FirebaseService.getGeneralStats();
    if (!mounted) return;

    final int totalToday = todayStats.values.fold(0, (sum, val) => sum + val);
    final int totalGeneral = generalStats.values.fold(0, (sum, val) => sum + val);

    showDialog(
      context: context,
      builder: (context) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: EdgeInsets.zero,
          title: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: Colors.blue),
                    ),
                    const SizedBox(width: 16),
                    const Text('სტატისტიკა', style: TextStyle(fontWeight: FontWeight.w900)),
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
            height: 400,
            child: TabBarView(
              children: [
                _buildStatsView(todayStats, totalToday, 'დღევანდელი აქტივობა'),
                _buildStatsView(generalStats, totalGeneral, 'ჯამური აქტივობა'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('დახურვა', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsView(Map<String, int> stats, int total, String subtitle) {
    if (stats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: Text('მონაცემები ჯერ არავის შეუვსია.', 
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return FutureBuilder<List<TeamInfo>>(
      future: AuthService.getTeamsWithCustomizations(),
      builder: (context, teamSnapshot) {
        final teams = teamSnapshot.data ?? [];
        final Map<String, TeamInfo> teamLookup = {for (var t in teams) t.id: t};

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),
            _TeamStatsVisualizer(stats: stats, teamLookup: teamLookup),
            const SizedBox(height: 16),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: stats.entries.map((entry) {
                    final team = teamLookup[entry.key] ?? 
                      AuthService.teams.firstWhere(
                        (t) => t.id == entry.key,
                        orElse: () => AuthService.teams.firstWhere(
                          (t) => t.name == entry.key,
                          orElse: () => TeamInfo(id: '', name: entry.key, password: '', color: Colors.grey),
                        ),
                      );
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: team.color.withValues(alpha: 0.1),
                        child: Text(entry.value.toString(), 
                          style: TextStyle(fontWeight: FontWeight.bold, color: team.color)),
                      ),
                      title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('შევსებული ბლანკი'),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      }
    );
  }
}

class _TeamStatsVisualizer extends StatelessWidget {
  final Map<String, int> stats;
  final Map<String, TeamInfo> teamLookup;
  const _TeamStatsVisualizer({required this.stats, required this.teamLookup});

  @override
  Widget build(BuildContext context) {
    final total = stats.values.fold(0, (sum, count) => sum + count);
    
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(140, 140),
            painter: _DonutChartPainter(stats: stats, total: total, teamLookup: teamLookup),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const Text('ჯამში', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final Map<String, int> stats;
  final int total;
  final Map<String, TeamInfo> teamLookup;

  _DonutChartPainter({required this.stats, required this.total, required this.teamLookup});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -3.14159 / 2;

    if (total == 0) {
      final paint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(center, radius - strokeWidth / 2, paint);
      return;
    }

    for (var entry in stats.entries) {
      final team = teamLookup[entry.key] ?? 
        AuthService.teams.firstWhere(
          (t) => t.id == entry.key,
          orElse: () => AuthService.teams.firstWhere(
            (t) => t.name == entry.key,
            orElse: () => TeamInfo(id: '', name: entry.key, password: '', color: Colors.grey),
          ),
        );
      
      final sweepAngle = (entry.value / total) * 2 * 3.14159;
      
      final paint = Paint()
        ..color = team.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Draw arc with a small gap
      canvas.drawArc(rect, startAngle + 0.05, sweepAngle - 0.1, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

extension on _HomeScreenState {
  Widget _buildDraftTile(Map<String, dynamic> draft) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        title: Text(draft['title'] ?? 'უსახელო', 
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${draft['form_type']} • ${draft['date']}', 
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
        onTap: () {
           final id = draft['id'];
           Navigator.push(
             context, 
             MaterialPageRoute(builder: (context) => BtkFormPage(draftId: id))
           ).then((_) => _loadRecentDrafts());
        },
      ),
    );
  }

  Widget _buildPrimaryAction({
    required String title, 
    required String desc, 
    required IconData icon, 
    required Color color,
    required VoidCallback onTap
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(desc, 
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.add_circle_outline_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolTile({required String title, required IconData icon, int badgeCount = 0, bool isLocked = false, VoidCallback? onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLocked ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: isLocked ? Colors.grey : Theme.of(context).colorScheme.primary, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    title, 
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600, 
                      fontSize: 12,
                      color: isLocked ? Colors.grey : Theme.of(context).colorScheme.onSurface
                    ),
                  ),
                  if (isLocked) 
                    Text('მალე', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
                ],
              ),
              if (badgeCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
