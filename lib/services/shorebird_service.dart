import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class ShorebirdService extends ChangeNotifier {
  static final ShorebirdService instance = ShorebirdService._();
  ShorebirdService._();

  final _updater = ShorebirdUpdater();
  bool _isDownloading = false;
  bool _isUpdateAvailable = false;
  bool _isUpdateReady = false;

  bool get isDownloading => _isDownloading;
  bool get isUpdateAvailable => _isUpdateAvailable;
  bool get isUpdateReady => _isUpdateReady;

  Future<void> checkForUpdates() async {
    // 1. Check if Shorebird is even available on this device/build
    // The new API doesn't have isShorebirdAvailable, it handles it gracefully
    
    try {
      // 2. Check for new updates
      final status = await _updater.checkForUpdate();
      
      if (status == UpdateStatus.restartRequired) {
        _isUpdateReady = true;
        notifyListeners();
        return;
      }

      if (status == UpdateStatus.outdated) {
        _isUpdateAvailable = true;
        _isDownloading = true;
        notifyListeners();

        // 3. Download the update
        await _updater.update();
        _isUpdateReady = true;
      }
    } catch (e) {
      debugPrint('Shorebird update error: $e');
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  Future<int?> getCurrentPatch() async {
    final patch = await _updater.readCurrentPatch();
    return patch?.number;
  }
}
