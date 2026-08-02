import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:kolia/screens/map_viewer_page.dart';
import 'package:kolia/services/map_storage_service.dart';

class MapManagementPage extends StatefulWidget {
  const MapManagementPage({super.key});

  @override
  State<MapManagementPage> createState() => _MapManagementPageState();
}

class _MapManagementPageState extends State<MapManagementPage> {
  late Future<List<drive.File>> _mapsFuture;
  final Map<String, double> _downloadProgress = {};
  Set<String> _localMapNames = {};

  @override
  void initState() {
    super.initState();
    _refreshMaps();
  }

  void _refreshMaps({bool silent = true}) {
    setState(() {
      _mapsFuture = _loadMapsAndLocalState(silent: silent);
    });
  }

  Future<List<drive.File>> _loadMapsAndLocalState({bool silent = true}) async {
    final results = await Future.wait([
      MapStorageService.listMaps(silent: silent),
      MapStorageService.getLocalMapNames(),
    ]);
    
    final remoteMaps = results[0] as List<drive.File>;
    final localNames = results[1] as Set<String>;

    if (mounted) {
      setState(() {
        _localMapNames = localNames;
      });
    }
    
    // Create placeholders for local files that aren't in the remote list
    // so they still show up when offline.
    final List<drive.File> allMaps = List.from(remoteMaps);
    final remoteNames = remoteMaps.map((m) => m.name).toSet();
    
    for (var name in localNames) {
      if (!remoteNames.contains(name)) {
        final localFile = drive.File()
          ..name = name
          ..id = 'local_$name'; // Fake ID for local-only files
        allMaps.add(localFile);
      }
    }

    return allMaps;
  }

  Future<void> _downloadMap(drive.File driveFile) async {
    final String fileName = driveFile.name ?? 'unknown';
    try {
      await MapStorageService.downloadToPermanent(
        driveFile,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress[fileName] = progress;
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _downloadProgress.remove(fileName);
          _localMapNames.add(fileName);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$fileName წარმატებით ჩამოიტვირთა'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(fileName);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('შეცდომა გადმოწერისას: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteMap(String fileName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('წავშალოთ ფაილი?'),
        content: Text('ნამდვილად გსურთ $fileName-ის წაშლა ლოკალური მეხსიერებიდან?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('გაუქმება')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('წაშლა', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MapStorageService.deleteLocalMap(fileName);
      if (mounted) {
        setState(() {
          _localMapNames.remove(fileName);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('რუკები'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshMaps(silent: false),
          ),
        ],
      ),
      body: FutureBuilder<List<drive.File>>(
        future: _mapsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text('შეცდომა: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _refreshMaps(silent: false),
                      child: const Text('თავიდან სცადეთ'),
                    ),
                  ],
                ),
              ),
            );
          }
          final maps = snapshot.data ?? [];
          if (maps.isEmpty) {
            return FutureBuilder<String>(
              future: MapStorageService.getMapFolderIdForDebug(),
              builder: (context, folderSnapshot) {
                final folderId = folderSnapshot.data ?? 'ჩატვირთვა...';
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.map_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('რუკები არ მოიძებნა', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('საქაღალდის ID: $folderId', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 16),
                        const Text(
                          'დარწმუნდით, რომ:\n1. საქაღალდე საჯაროა (Anyone with link)\n2. საქაღალდეში ნამდვილად არის ფაილები\n3. API Key სწორია',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _refreshMaps(silent: false),
                          icon: const Icon(Icons.refresh),
                          label: const Text('განახლება'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            );
          }

          return ListView.builder(
            itemCount: maps.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final driveFile = maps[index];
              final fileName = driveFile.name ?? 'Unknown';
              final progress = _downloadProgress[fileName];
              final isLocal = _localMapNames.contains(fileName);
              
              final sizeStr = driveFile.size != null 
                  ? '${(int.parse(driveFile.size!) / (1024 * 1024)).toStringAsFixed(1)} MB' 
                  : '...';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () async {
                        if (isLocal) {
                          final file = await MapStorageService.getPermanentFile(fileName);
                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapViewerPage(file: file, title: fileName),
                              ),
                            );
                          }
                        } else {
                          // Try to get (will download if not present)
                          try {
                            final file = await MapStorageService.getMap(driveFile);
                            if (mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MapViewerPage(file: file, title: fileName),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('ვერ მოხერხდა ფაილის გახსნა: $e')),
                              );
                            }
                          }
                        }
                      },
                      leading: Icon(
                        fileName.toLowerCase().endsWith('.pdf') 
                          ? Icons.picture_as_pdf 
                          : Icons.map_outlined,
                        color: Colors.blue,
                      ),
                      title: Text(fileName),
                      subtitle: Text(
                        '${isLocal ? 'გადმოწერილია' : 'ხელმისაწვდომია'} • $sizeStr',
                        style: TextStyle(
                          color: isLocal ? Colors.green : Colors.grey,
                          fontSize: 12
                        )
                      ),
                      trailing: progress != null
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLocal)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _deleteMap(fileName),
                                ),
                              if (driveFile.id != null && !driveFile.id!.startsWith('local_'))
                                IconButton(
                                  icon: Icon(isLocal ? Icons.refresh : Icons.download),
                                  onPressed: () => _downloadMap(driveFile),
                                ),
                            ],
                          ),
                    ),
                    if (progress != null)
                      LinearProgressIndicator(value: progress, minHeight: 2),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
