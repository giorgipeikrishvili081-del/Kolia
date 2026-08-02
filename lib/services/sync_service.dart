// This file is UTF-8 encoded.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/database_helper.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize what's needed for the task
      // Note: In background tasks, you might need to re-initialize some services
      // but Firebase usually works if initialized in main.
      
      final count = await SyncService.performSync();
      return Future.value(count >= 0);
    } catch (e) {
      debugPrint('Workmanager task failed: $e');
      return Future.value(false);
    }
  });
}

class SyncService {
  static const String syncTaskName = "com.kolia.syncTask";
  static bool _isSyncing = false;

  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  /// Starts the periodic sync process using Workmanager.
  static Future<void> startPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      "1",
      syncTaskName,
      frequency: const Duration(minutes: 15), // Minimum allowed by Android is 15 mins
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> stopPeriodicSync() async {
    await Workmanager().cancelAll();
  }

  static Future<int> performSync() async {
    if (_isSyncing) return 0;

    // Connectivity Check
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return 0;
    }
    
    // Only proceed if we have records to sync
    final unsyncedCount = await DatabaseHelper.instance.getUnsyncedCount();
    if (unsyncedCount == 0) return 0;

    final stopwatch = Stopwatch()..start();
    _isSyncing = true;
    try {
      debugPrint('SyncService: Starting background sync...');
      final count = await FirebaseService.syncAllUnsynced();
      stopwatch.stop();
      if (count > 0) {
        debugPrint('SyncService: Successfully synced $count records in ${stopwatch.elapsed.inMilliseconds}ms.');
      }
      return count;
    } catch (e) {
      stopwatch.stop();
      debugPrint('SyncService Error after ${stopwatch.elapsed.inMilliseconds}ms: $e');
      return -1;
    } finally {
      _isSyncing = false;
    }
  }
}
