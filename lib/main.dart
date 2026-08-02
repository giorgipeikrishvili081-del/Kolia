import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:kolia/screens/home_screen.dart';
import 'package:kolia/screens/export_page.dart';
import 'package:kolia/screens/settings_page.dart';
import 'package:kolia/screens/login_screen.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/services/auth_service.dart';

import 'package:kolia/services/theme_manager.dart';
import 'package:kolia/services/app_state.dart';
import 'package:kolia/services/sync_service.dart';
import 'package:kolia/services/shorebird_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    // Initialize Workmanager for background sync
    await SyncService.init();
    await SyncService.startPeriodicSync();
    
    // Check for Shorebird updates
    ShorebirdService.instance.checkForUpdates();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    // Continue anyway, but some features will be disabled
  }
  await DatabaseHelper.instance.database;
  await ThemeManager.init();
  
  final loggedIn = await AuthService.isLoggedIn();
  if (loggedIn) {
    final team = await AuthService.getLoggedInTeam();
    if (team != null) {
      teamColorNotifier.value = team.color;
      teamNameNotifier.value = team.name;
    }
    // Attempt an immediate sync on startup if internet is available
    SyncService.performSync();
  }
  loginNotifier.value = loggedIn;
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: loginNotifier,
      builder: (context, isLoggedIn, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: teamColorNotifier,
          builder: (context, teamColor, _) {
            return ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, _) {
                return MaterialApp(
                  title: 'Kolia',
                  debugShowCheckedModeBanner: false,
                  builder: (context, child) {
                    return Column(
                      children: [
                        Material(
                          child: ListenableBuilder(
                            listenable: ShorebirdService.instance,
                            builder: (context, _) {
                              if (ShorebirdService.instance.isDownloading) {
                                return Container(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, bottom: 8, left: 16, right: 16),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.downloading, size: 16, color: Colors.orange),
                                            const SizedBox(width: 12),
                                            const Expanded(
                                              child: Text(
                                                'მიმდინარეობს აპლიკაციის განახლება...',
                                                style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation(Colors.orange)),
                                    ],
                                  ),
                                );
                              }
                              if (ShorebirdService.instance.isUpdateReady) {
                                return Container(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, bottom: 4, left: 16, right: 16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'განახლება მზადაა. გთხოვთ გადატვირთოთ აპი.',
                                          style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => ShorebirdService.instance.checkForUpdates(), 
                                        child: const Text('OK', style: TextStyle(fontSize: 12)),
                                      )
                                    ],
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        Expanded(child: child!),
                      ],
                    );
                  },
                  theme: ThemeData(
                    brightness: Brightness.light,
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: teamColor,
                      brightness: Brightness.light,
                    ),
                    useMaterial3: true,
                    scaffoldBackgroundColor: Colors.grey.shade50,
                  ),
                  darkTheme: ThemeData(
                    brightness: Brightness.dark,
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: teamColor,
                      brightness: Brightness.dark,
                    ),
                    useMaterial3: true,
                  ),
                  themeMode: currentMode,
                  home: isLoggedIn
                      ? const MainScreen()
                      : LoginScreen(
                          key: UniqueKey(),
                          onLoginSuccess: () async {
                            final team = await AuthService.getLoggedInTeam();
                            if (team != null) {
                              teamColorNotifier.value = team.color;
                              teamNameNotifier.value = team.name;
                            }
                            loginNotifier.value = true;
                          }),
                );
              },
            );
          },
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeScreen(
        onNavigateToExports: () async => _onItemTapped(1),
        onNavigateToSettings: () => _onItemTapped(2),
      ),
      const ExportPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'მთავარი',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_shared_outlined),
            selectedIcon: Icon(Icons.folder_shared_rounded),
            label: 'ექსპორტი',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'პარამეტრები',
          ),
        ],
      ),
    );
  }
}
