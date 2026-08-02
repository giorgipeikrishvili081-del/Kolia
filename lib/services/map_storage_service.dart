import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kolia/services/google_drive_service.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class MapStorageService {
  // Replace this with the actual ID from your Google Drive folder URL
  static const String _defaultMapFolderId = '1d2e8jvtqSP-m71XUJim6QZtgHqWVJDWof';

  static String? _permanentDirPath;
  static String? _tempDirPath;

  static Future<String> _getPermanentDirPath() async {
    if (_permanentDirPath != null) return _permanentDirPath!;
    final directory = await getApplicationDocumentsDirectory();
    _permanentDirPath = p.join(directory.path, 'permanent_maps');
    final dir = Directory(_permanentDirPath!);
    if (!await dir.exists()) await dir.create(recursive: true);
    return _permanentDirPath!;
  }

  static Future<String> _getTempDirPath() async {
    if (_tempDirPath != null) return _tempDirPath!;
    final directory = await getTemporaryDirectory();
    _tempDirPath = p.join(directory.path, 'map_cache');
    final dir = Directory(_tempDirPath!);
    if (!await dir.exists()) await dir.create(recursive: true);
    return _tempDirPath!;
  }

  /// Lists files that are already downloaded locally
  static Future<Set<String>> getLocalMapNames() async {
    final path = await _getPermanentDirPath();
    final dir = Directory(path);
    if (!await dir.exists()) return {};
    
    final List<FileSystemEntity> entities = await dir.list().toList();
    return entities
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toSet();
  }

  static final CacheManager _cacheManager = CacheManager(
    Config(
      'map_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 100,
    ),
  );

  /// Resolves the map folder ID from Firestore or uses the default
  static Future<String> _getMapFolderId() async {
    final config = await FirebaseService.getAppConfig();
    final folderId = config['map_folder_id'];
    if (folderId == null || folderId.toString().trim().isEmpty || folderId == 'YOUR_FOLDER_ID_HERE') {
      return _defaultMapFolderId;
    }
    return folderId.toString();
  }

  /// Helper for UI debugging
  static Future<String> getMapFolderIdForDebug() async {
    return await _getMapFolderId();
  }

  /// Lists all files in the maps folder in Google Drive.
  static Future<List<drive.File>> listMaps({bool silent = true}) async {
    try {
      final folderId = await _getMapFolderId();
      debugPrint('MapStorageService: Fetching maps from folder: $folderId');
      
      final files = await GoogleDriveService.listFiles(folderId, silent: silent);
      debugPrint('MapStorageService: Found ${files.length} files');
      return files;
    } catch (e) {
      debugPrint('MapStorageService: Error listing maps: $e');
      rethrow;
    }
  }

  /// Gets a map file, either from permanent storage, cache, or by downloading it
  static Future<File> getMap(drive.File driveFile) async {
    final String fileName = driveFile.name ?? 'unknown_map';
    final String? fileId = driveFile.id;
    
    if (fileId == null) throw Exception('Drive file ID is null');

    // 1. Check permanent storage first
    final permanentFile = await getPermanentFile(fileName);
    if (await permanentFile.exists()) {
      return permanentFile;
    }

    // 2. Check cache
    final tempPath = await _getTempDirPath();
    final cacheFile = File(p.join(tempPath, fileName));
    
    if (await cacheFile.exists()) {
      return cacheFile;
    }

    // 3. Download to temp if not found (Download as "cached")
    await GoogleDriveService.downloadFile(fileId, cacheFile);
    return cacheFile;
  }

  static Future<bool> isDownloadedLocally(String fileName) async {
    final path = await _getPermanentDirPath();
    final file = File(p.join(path, fileName));
    return await file.exists();
  }

  static Future<void> deleteLocalMap(String fileName) async {
    final path = await _getPermanentDirPath();
    final file = File(p.join(path, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<File> getPermanentFile(String fileName) async {
    final path = await _getPermanentDirPath();
    return File(p.join(path, fileName));
  }

  /// Downloads a file to permanent storage with progress reporting
  static Future<void> downloadToPermanent(drive.File driveFile, {Function(double)? onProgress}) async {
    final String fileName = driveFile.name ?? 'unknown_map';
    final String? fileId = driveFile.id;
    if (fileId == null) throw Exception('Drive file ID is null');

    final file = await getPermanentFile(fileName);
    await GoogleDriveService.downloadFile(fileId, file, onProgress: onProgress);
  }
}
