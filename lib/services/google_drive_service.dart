import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/secrets.dart';

class GoogleDriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: AppSecrets.googleDriveClientId,
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveMetadataReadonlyScope,
      drive.DriveApi.driveReadonlyScope,
    ],
  );

  static drive.DriveApi? _cachedDriveApi;
  static String? _cachedUserEmail;

  /// Returns a DriveApi instance using an API Key for public access.
  static drive.DriveApi _getPublicDriveApi() {
    return drive.DriveApi(ApiKeyClient(AppSecrets.googleApiKey));
  }

  static Future<GoogleSignInAccount?> signIn({bool silent = false}) async {
    // Check current user first to avoid unnecessary async calls
    if (_googleSignIn.currentUser != null) return _googleSignIn.currentUser;
    
    try {
      var account = await _googleSignIn.signInSilently();
      if (!silent && account == null) {
        account = await _googleSignIn.signIn();
      }
      return account;
    } catch (e) {
      if (!silent) {
        return await _googleSignIn.signIn();
      }
      return null;
    }
  }

  static Future<drive.DriveApi> _getDriveApi() async {
    final account = await signIn();
    if (account == null) throw Exception('Google Sign-In failed');
    return _createDriveApi(account);
  }

  static Future<drive.DriveApi?> _getDriveApiSilently() async {
    final account = await signIn(silent: true);
    if (account == null) return null;
    return _createDriveApi(account);
  }

  static drive.DriveApi _createDriveApi(GoogleSignInAccount account) {
    // Reuse DriveApi if the user hasn't changed
    if (_cachedDriveApi != null && _cachedUserEmail == account.email) {
      return _cachedDriveApi!;
    }

    final authenticateClient = GoogleAuthClient(account);
    _cachedDriveApi = drive.DriveApi(authenticateClient);
    _cachedUserEmail = account.email;
    return _cachedDriveApi!;
  }

  /// Lists files in a specific Google Drive folder
  static Future<List<drive.File>> listFiles(String folderId, {bool silent = false}) async {
    final apiKey = AppSecrets.googleApiKey;
    final isApiKeyConfigured = apiKey != 'YOUR_GOOGLE_API_KEY_HERE' && apiKey.isNotEmpty;

    // 1. Try public access with API Key first
    if (isApiKeyConfigured) {
      try {
        final publicApi = _getPublicDriveApi();
        debugPrint('GoogleDriveService: Requesting file list for folder: $folderId');
        
        // Try to get folder metadata first to verify access
        try {
          final folder = await publicApi.files.get(folderId, $fields: 'id, name, capabilities') as drive.File;
          debugPrint('GoogleDriveService: Folder accessible: ${folder.name}');
        } catch (e) {
          debugPrint('GoogleDriveService: Warning - Could not verify folder metadata: $e');
          // Continue anyway, as list might work even if get folder doesn't
        }

        final fileList = await publicApi.files.list(
          q: "'$folderId' in parents and trashed = false",
          $fields: "files(id, name, size, mimeType), nextPageToken",
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );
        
        final files = fileList.files ?? [];
        debugPrint('GoogleDriveService: API Key request successful. Found ${files.length} files.');
        
        // Debug: log first few file names if any
        if (files.isNotEmpty) {
          debugPrint('GoogleDriveService: First file: ${files.first.name}');
        }
        
        return files;
      } catch (e) {
        debugPrint('GoogleDriveService: API Key Error: $e');
        if (!silent) {
          String errorMsg = e.toString();
          if (errorMsg.contains('403')) {
            errorMsg = 'წვდომა შეზღუდულია (403). შეამოწმეთ API Key-ს შეზღუდვები და საქაღალდის პარამეტრები.';
          }
          throw Exception(errorMsg);
        }
      }
    }

    // 2. Fallback to Authenticated access only if user explicitly asks (via silent=false) 
    // and API key is missing or failed.
    if (!isApiKeyConfigured || !silent) {
      debugPrint('GoogleDriveService: Attempting authenticated access fallback...');
      final driveApi = await _getDriveApiSilently();
      if (driveApi == null) {
        if (!silent) throw Exception('Google Drive-ზე წვდომისთვის საჭიროა ავტორიზაცია ან სწორი API Key.');
        return [];
      }

      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: "files(id, name, size, mimeType)",
      );

      return fileList.files ?? [];
    }
    
    return [];
  }

  /// Downloads a file from Google Drive and saves it to a local file
  static Future<void> downloadFile(String fileId, File localFile, {Function(double)? onProgress}) async {
    // 1. Try public access with API Key first
    final apiKey = AppSecrets.googleApiKey;
    final isApiKeyConfigured = apiKey != 'YOUR_GOOGLE_API_KEY_HERE' && apiKey.isNotEmpty;

    if (isApiKeyConfigured) {
      try {
        final publicApi = _getPublicDriveApi();
        final drive.Media media = await publicApi.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;
        
        await _streamDownload(media, localFile, onProgress);
        return;
      } catch (e) {
        debugPrint('Public download failed: $e. Falling back to authenticated download.');
      }
    }

    // 2. Fallback to Authenticated access
    final driveApi = await _getDriveApi();
    final drive.Media media = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    await _streamDownload(media, localFile, onProgress);
  }

  static Future<void> _streamDownload(drive.Media media, File localFile, Function(double)? onProgress) async {
    List<int> dataStore = [];
    int downloaded = 0;
    final int? total = media.length;

    await for (final data in media.stream) {
      dataStore.addAll(data);
      downloaded += data.length;
      if (onProgress != null && total != null) {
        onProgress(downloaded / total);
      }
    }

    await localFile.writeAsBytes(dataStore);
  }

  static Future<void> uploadAsGoogleDoc({
    required String title,
    required String htmlContent,
    String? parentFolderId,
  }) async {
    final driveApi = await _getDriveApi();

    final driveFile = drive.File();
    driveFile.name = title;
    driveFile.mimeType = 'application/vnd.google-apps.document';
    if (parentFolderId != null) {
      driveFile.parents = [parentFolderId];
    }

    final bytes = utf8.encode(htmlContent);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'text/html',
    );

    await driveApi.files.create(
      driveFile,
      uploadMedia: media,
    );
  }

  /// Uploads multiple forms to Google Drive in parallel.
  /// Returns a map with success and fail counts.
  static Future<Map<String, int>> uploadMultipleForms(
    List<Map<String, dynamic>> forms, {
    String? parentFolderId,
    Function(int completed, int total)? onProgress,
  }) async {
    int successCount = 0;
    int failCount = 0;
    int completedCount = 0;

    if (forms.isEmpty) return {'success': 0, 'fail': 0};

    // Limit concurrency to avoid hitting Drive API rate limits too hard
    // but keep it "all together" in parallel batches.
    final List<Future<void>> tasks = forms.map((form) async {
      try {
        await uploadFormAsGoogleDoc(form, parentFolderId: parentFolderId);
        successCount++;
      } catch (e) {
        debugPrint('Bulk upload error: $e');
        failCount++;
      } finally {
        completedCount++;
        if (onProgress != null) {
          onProgress(completedCount, forms.length);
        }
      }
    }).toList();

    await Future.wait(tasks);
    return {'success': successCount, 'fail': failCount};
  }

  static Future<void> uploadFormAsGoogleDoc(Map<String, dynamic> rawData, {String? parentFolderId}) async {
    final Map<String, dynamic> data = json.decode(json.encode(rawData, toEncodable: (item) {
      if (item is Timestamp) return item.toDate().toIso8601String();
      if (item is DateTime) return item.toIso8601String();
      return item.toString();
    }));

    final String htmlContent = generateHtmlContent(data);
    
    final String? btkId = data['btk_index']?.toString();
    final String title = (btkId != null && btkId.isNotEmpty) 
        ? 'ბტკ ბლანკი - $btkId (${data['date'] ?? ''})'
        : 'ბტკ ბლანკი (${data['date'] ?? ''})';

    await uploadAsGoogleDoc(
      title: title, 
      htmlContent: htmlContent,
      parentFolderId: parentFolderId,
    );

    // Defensive updates to Firestore/SQLite - don't let these fail the whole operation
    // if the Drive upload was already successful.
    try {
      if (rawData['id'] != null) {
        await FirebaseService.markAsUploadedToDrive(rawData['id']);
      }
      
      if (rawData['db_id'] != null) {
        await DatabaseHelper.instance.markAsUploaded(rawData['db_id']);
      }
    } catch (e) {
      debugPrint('GoogleDriveService: Metadata update failed after successful upload: $e');
    }
  }

  static String generateHtmlContent(Map<String, dynamic> data) {
    final StringBuffer html = StringBuffer();
    String primaryColor = '#2c3e50';
    if (data['team_color'] != null) {
      try {
        final int colorValue = data['team_color'] is int 
            ? data['team_color'] 
            : int.parse(data['team_color'].toString());
        primaryColor = '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      } catch (e) {}
    }

    html.write('<!DOCTYPE html><html><head><meta charset="utf-8">');
    html.write('<style>');
    html.write('body { font-family: "DejaVu Sans", "Helvetica", Arial, sans-serif; line-height: 1.5; color: #333; margin: 0; padding: 20px; }');
    html.write('sup { font-size: 0.75em; line-height: 0; position: relative; vertical-align: baseline; top: -0.5em; }');
    html.write('.header { text-align: center; border-bottom: 3px solid $primaryColor; padding-bottom: 15px; margin-bottom: 25px; page-break-after: avoid; break-after: avoid; }');
    html.write('h1 { font-size: 22px; color: $primaryColor; margin: 0; }');
    html.write('.team-badge { display: inline-block; padding: 4px 12px; background-color: $primaryColor; color: white; border-radius: 20px; font-size: 12px; margin-top: 8px; font-weight: bold; }');
    html.write('.section-header { background-color: #f8f9fa; border-left: 5px solid $primaryColor; padding: 8px 15px; margin-top: 25px; font-weight: bold; color: $primaryColor; font-size: 16px; text-transform: uppercase; page-break-after: avoid; break-after: avoid; }');
    html.write('.info-table { width: 100%; margin-top: 10px; border-collapse: collapse; page-break-inside: avoid; break-inside: avoid; }');
    html.write('.info-table td { padding: 8px 0; border-bottom: 1px solid #eee; vertical-align: top; }');
    html.write('.label { font-weight: bold; width: 220px; color: #555; font-size: 13px; }');
    html.write('.value { color: #000; font-size: 13px; }');
    html.write('.highlight-box { margin-top: 15px; padding: 10px 15px; background-color: #fff; border: 1px dashed $primaryColor; border-radius: 4px; font-size: 14px; color: $primaryColor; page-break-inside: avoid; break-inside: avoid; }');
    html.write('.highlight-box strong { color: $primaryColor; font-size: 12px; display: inline-block; margin-right: 5px; }');
    html.write('.highlight-box strong::after { content: ":"; }');
    html.write('.data-table { width: 100%; border-collapse: collapse; margin-top: 15px; border: 1px solid #dee2e6; page-break-inside: avoid; break-inside: avoid; }');
    html.write('.data-table thead { display: table-header-group; }');
    html.write('.data-table tr { page-break-inside: avoid; break-inside: avoid; }');
    html.write('.data-table th { background-color: $primaryColor; color: white; padding: 10px; text-align: center; font-size: 11px; text-transform: uppercase; border: 1px solid $primaryColor; }');
    html.write('.data-table td { padding: 8px 10px; border: 1px solid #dee2e6; font-size: 12px; text-align: center; }');
    html.write('.data-table .text-left { text-align: left; }');
    html.write('.sub-header { background-color: #f1f3f5; color: #333; font-weight: bold; font-size: 10px; }');
    html.write('.data-table tr:nth-child(even) { background-color: #f9f9f9; }');
    html.write('.sketch-box { margin-top: 25px; border: 2px solid $primaryColor; border-radius: 4px; overflow: hidden; max-width: 100%; page-break-inside: avoid; break-inside: avoid; }');
    html.write('.sketch-title-bar { background-color: $primaryColor; color: white; padding: 8px 15px; font-weight: bold; text-align: center; font-size: 14px; }');
    html.write('.sketch-meta-bar { background-color: #e9ecef; padding: 5px; border-bottom: 1px solid #dee2e6; text-align: center; font-size: 11px; color: #495057; }');
    html.write('.sketch-img-container { padding: 15px; background-color: #fff; text-align: center; width: 100%; box-sizing: border-box; }');
    html.write('.sketch-img-container img { max-width: 100%; max-height: 450px; height: auto; width: auto; border: 1px solid #eee; display: block; margin: 0 auto; }');
    html.write('.sketch-note { padding: 10px 15px; background-color: #f8f9fa; border-top: 1px solid #dee2e6; font-size: 11px; font-style: italic; color: #6c757d; }');
    html.write('</style>');
    html.write('</head><body>');
    
    html.write('<div class="header">');
    html.write('<h1>ბუნებრივ-ტერიტორიული კომპლექსის (ბტკ) აღწერის ბლანკი</h1>');
    if (data['team_name'] != null) {
      html.write('<div class="team-badge">${data['team_name']}</div>');
    }
    html.write('</div>');
    
    html.write('<div class="section-header">I. ზოგადი ინფორმაცია</div>');
    html.write('<table class="info-table">');
    _addInfoRow(html, 'ბტკ ინდექსი', data['btk_index']);
    _addInfoRow(html, 'თარიღი', data['date']);
    _addInfoRow(html, 'მკვლევარი', data['researcher']);
    _addInfoRow(html, 'მდებარეობა', data['location']);
    _addInfoRow(html, 'კოორდინატები', data['coords']);
    html.write('</table>');
    
    html.write('<div class="section-header">II. ლანდშაფტური და ფიზიკურ-გეოგრაფიული დახასიათება</div>');
    html.write('<table class="info-table">');
    _addInfoRow(html, 'ლანდშაფტის სახელი', data['landscape_name']);
    _addInfoRow(html, 'ლანდშაფტის გვარის ნომერი', data['landscape_genus_number']);
    _addInfoRow(html, 'ფაციესის სახელი', data['facies_name']);
    _addInfoRow(html, 'სტექსი', data['steksi']);
    _addInfoRow(html, 'ფიზიკურ-გეოგრაფიული დახასიათება', data['phys_geog_char']);
    _addInfoRow(html, 'რელიეფის ტიპი', data['relief_type']);
    _addInfoRow(html, 'მორფოლოგიური დახასიათება', data['morphological_char']);
    _addInfoRow(html, 'თანამედროვე გეომორფოლოგიური პროცესები', data['modern_geomorph_proc']);
    _addInfoRow(html, 'მიგრაციული რეჟიმი', data['migration_regime']);
    _addInfoRow(html, 'დატენიანების ხარისხი', data['moistening_degree']);
    _addInfoRow(html, 'მცენარეული ასოციაციის დასახელება', data['plant_association']);
    html.write('</table>');

    if (data['vegetation_rows'] != null && (data['vegetation_rows'] as List).isNotEmpty) {
      html.write('<div class="section-header">III. მცენარეულობის სახეობრივი შემადგენლობა</div>');
      html.write('<table class="data-table">');
      html.write('<thead><tr><th>სახეობა</th><th>იარუსი</th><th>სიმაღლე (მ)</th><th>სიმძლავრე</th><th>ფენოფაზა</th></tr></thead>');
      html.write('<tbody>');
      for (var row in (data['vegetation_rows'] as List)) {
        html.write('<tr>');
        html.write('<td>${row['species'] ?? ''}</td>');
        html.write('<td>${row['layer'] ?? ''}</td>');
        html.write('<td>${row['height'] ?? ''}</td>');
        html.write('<td>${row['abundance'] ?? ''}</td>');
        html.write('<td>${row['phenophase'] ?? ''}</td>');
        html.write('</tr>');
      }
      html.write('</tbody></table>');
    }

    if (data['soil_rows'] != null && (data['soil_rows'] as List).isNotEmpty) {
      html.write('<div class="section-header">IV. ნიადაგის პროფილის მორფოლოგიური დახასიათება</div>');
      html.write('<table class="data-table">');
      html.write('<thead><tr><th class="text-left">გენეტიკური ჰორიზონტი</th><th class="text-left">მორფოლოგიური დახასიათება</th><th class="text-left">ინდექსი</th></tr></thead>');
      html.write('<tbody>');
      for (var row in (data['soil_rows'] as List)) {
        html.write('<tr>');
        String geneticHorizon = row['genetic_horizon'] ?? '';
        geneticHorizon = _convertSuperscriptsToHtml(geneticHorizon);
        html.write('<td class="text-left">$geneticHorizon</td>');
        html.write('<td class="text-left">${row['detailed_description'] ?? ''}</td>');
        html.write('<td class="text-left">${row['geohorizon_index'] ?? ''}</td>');
        html.write('</tr>');
      }
      html.write('</tbody></table>');
    }

    if (data['soil_type_name'] != null && data['soil_type_name'].toString().isNotEmpty) {
      html.write('<div class="highlight-box">');
      html.write('<strong>ნიადაგის ტიპი</strong> ${data['soil_type_name']}');
      html.write('</div>');
    }

    if (data['soil_surface_formation'] != null && data['soil_surface_formation'].toString().isNotEmpty) {
      html.write('<div class="highlight-box">');
      html.write('<strong>ნიადაგის ზედაპირული ფორმაციის ტიპი</strong> ${data['soil_surface_formation']}');
      html.write('</div>');
    }

    if (data['biomass_rows'] != null) {
      html.write('<div class="section-header">V. გეომასების კვლევა</div>');
      html.write('<p style="font-size: 12px; color: #666; margin-bottom: 10px; margin-top: 5px;">ბტკ-ის ვერტიკალური პროფილის მიწისზედა ნაწილის გეომასები</p>');
      html.write('<table class="data-table">');
      html.write('<thead>');
      html.write('<tr>');
      html.write('<th rowspan="2">სექციები</th>');
      html.write('<th colspan="3">პედომასები</th>');
      html.write('<th colspan="3">ლითომასები</th>');
      html.write('<th colspan="2">ჰიდრომასები</th>');
      html.write('<th colspan="3">ფიტომასები</th>');
      html.write('</tr>');
      html.write('<tr class="sub-header">');
      html.write('<th>%</th><th>მოც. წონა</th><th>რაოდ.</th>');
      html.write('<th>%</th><th>სიმკვრ.</th><th>რაოდ.</th>');
      html.write('<th>სინოტ.</th><th>რაოდ.</th>');
      html.write('<th>%</th><th>სველი</th><th>მშრალი</th>');
      html.write('</tr>');
      html.write('</thead>');
      html.write('<tbody>');
      
      List rows = data['biomass_rows'] as List;
      if (rows.isEmpty || rows.every((r) => (r as Map).values.every((v) => v == null || v.toString().trim().isEmpty))) {
        for (int i = 0; i < 5; i++) {
          html.write('<tr><td>&nbsp;</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>');
        }
      } else {
        for (var row in rows) {
          html.write('<tr>');
          html.write('<td>${row['section'] ?? ''}</td>');
          html.write('<td>${row['p_percent'] ?? ''}</td>');
          html.write('<td>${row['p_weight'] ?? ''}</td>');
          html.write('<td>${row['p_qty'] ?? ''}</td>');
          html.write('<td>${row['l_percent'] ?? ''}</td>');
          html.write('<td>${row['l_density'] ?? ''}</td>');
          html.write('<td>${row['l_qty'] ?? ''}</td>');
          html.write('<td>${row['h_moist'] ?? ''}</td>');
          html.write('<td>${row['h_qty'] ?? ''}</td>');
          html.write('<td>${row['f_percent'] ?? ''}</td>');
          html.write('<td>${row['f_wet'] ?? ''}</td>');
          html.write('<td>${row['f_dry'] ?? ''}</td>');
          html.write('</tr>');
        }
      }
      html.write('</tbody></table>');
    }

    if (data['tree_taxation_rows'] != null && (data['tree_taxation_rows'] as List).isNotEmpty) {
      html.write('<div class="section-header">VI. მცენარეულობის ტაქსაცია</div>');
      html.write('<table class="data-table">');
      html.write('<thead><tr><th>ხე №</th><th>სახეობა</th><th>D</th><th>H</th><th>K2</th><th>მოცულობა</th></tr></thead>');
      html.write('<tbody>');
      int treeIdx = 1;
      for (var row in (data['tree_taxation_rows'] as List)) {
        if ((row['species']?.isEmpty ?? true) && (row['d']?.isEmpty ?? true) && (row['h']?.isEmpty ?? true) && (row['k2']?.isEmpty ?? true) && (row['volume']?.isEmpty ?? true)) {
          continue;
        }
        html.write('<tr>');
        html.write('<td>$treeIdx</td>');
        html.write('<td>${row['species'] ?? ''}</td>');
        html.write('<td>${row['d'] ?? ''}</td>');
        html.write('<td>${row['h'] ?? ''}</td>');
        html.write('<td>${row['k2'] ?? ''}</td>');
        html.write('<td>${row['volume'] ?? ''}</td>');
        html.write('</tr>');
        treeIdx++;
      }
      html.write('</tbody></table>');
    }

    if (data['taxation_plot_size'] != null && data['taxation_plot_size'].toString().isNotEmpty) {
      html.write('<div class="highlight-box">');
      html.write('<strong>ნაკვეთის ზომა</strong> ${data['taxation_plot_size']}');
      html.write('</div>');
    }

    if (data['tree_phytomass_rows'] != null) {
      html.write('<div class="section-header">VII. ხე მცენარეების ფიტომასა</div>');
      html.write('<table class="data-table">');
      html.write('<thead>');
      html.write('<tr style="border: 2px solid #2c3e50;">');
      html.write('<th rowspan="2" style="border: 2px solid #2c3e50;">სახეობა</th>');
      html.write('<th colspan="3" style="border: 2px solid #2c3e50;">მმოც. წონა ტ/მ³</th>');
      html.write('<th colspan="5" style="border: 2px solid #2c3e50;">სველი ფიტომასა</th>');
      html.write('<th colspan="5" style="border: 2px solid #2c3e50;">მშრალი ფიტომასა</th>');
      html.write('<th rowspan="2" style="border: 2px solid #2c3e50;"></th>');
      html.write('</tr>');
      html.write('<tr class="sub-header" style="border: 2px solid #2c3e50;">');
      html.write('<th style="border: 2px solid #2c3e50;">მმოც.</th><th style="border: 2px solid #2c3e50;">სველი</th><th style="border: 2px solid #2c3e50;">მშრალი</th>');
      html.write('<th style="border: 2px solid #2c3e50;">მერქნ.</th><th style="border: 2px solid #2c3e50;">ფოთლ.</th><th style="border: 2px solid #2c3e50;">ტოტ.</th><th style="border: 2px solid #2c3e50;">ფესვ.</th><th style="border: 2px solid #2c3e50;">ჯამი</th>');
      html.write('<th style="border: 2px solid #2c3e50;">მერქნ.</th><th style="border: 2px solid #2c3e50;">ფოთლ.</th><th style="border: 2px solid #2c3e50;">ტოტ.</th><th style="border: 2px solid #2c3e50;">ფესვ.</th><th style="border: 2px solid #2c3e50;">ჯამი</th>');
      html.write('</tr>');
      html.write('</thead>');
      html.write('<tbody>');
      
      List rows = data['tree_phytomass_rows'] as List;
      List activeRows = rows.where((row) => 
        !((row['species']?.isEmpty ?? true) && (row['v_vol']?.isEmpty ?? true) && (row['w_total']?.isEmpty ?? true))
      ).toList();

      if (activeRows.isEmpty) {
        for (int i = 0; i < 5; i++) {
          html.write('<tr>');
          for (int j = 0; j < 15; j++) {
            html.write('<td>&nbsp;</td>');
          }
          html.write('</tr>');
        }
      } else {
        for (var row in activeRows) {
          html.write('<tr>');
          html.write('<td>${row['species'] ?? ''}</td>');
          html.write('<td>${row['v_vol'] ?? ''}</td>');
          html.write('<td>${row['v_wet'] ?? ''}</td>');
          html.write('<td>${row['v_dry'] ?? ''}</td>');
          html.write('<td>${row['w_wood'] ?? ''}</td>');
          html.write('<td>${row['w_leaf'] ?? ''}</td>');
          html.write('<td>${row['w_branch'] ?? ''}</td>');
          html.write('<td>${row['w_root'] ?? ''}</td>');
          html.write('<td>${row['w_total'] ?? ''}</td>');
          html.write('<td>${row['d_wood'] ?? ''}</td>');
          html.write('<td>${row['d_leaf'] ?? ''}</td>');
          html.write('<td>${row['d_branch'] ?? ''}</td>');
          html.write('<td>${row['d_root'] ?? ''}</td>');
          html.write('<td>${row['d_total'] ?? ''}</td>');
          html.write('<td></td>');
          html.write('</tr>');
        }
      }
      html.write('</tbody></table>');
    }

    final hasSketch = data['sketch_url'] != null || data['sketch_base64'] != null;
    if (hasSketch) {
      html.write('<div class="section-header">VIII. ვერტიკალური სტრუქტურა</div>');
      html.write('<div class="sketch-box">');
      String sTitle = data['sketch_title'] ?? "ვერტიკალური სტრუქტურის სქემა";
      html.write('<div class="sketch-title-bar">$sTitle</div>');
      String index = data['sketch_index'] ?? "";
      String height = data['sketch_height'] ?? "";
      String displayIndex = index.replaceAll(RegExp(r'^ინდექსი:\s*', caseSensitive: false), '').trim();
      String displayHeight = height.replaceAll(RegExp(r'^სიმაღლე:\s*', caseSensitive: false), '').trim();
      if (displayHeight.isEmpty) {
        displayHeight = height.replaceAll(RegExp(r'^სიმაღლითი გრადაცია:\s*', caseSensitive: false), '').trim();
      }

      if (displayIndex.isNotEmpty || displayHeight.isNotEmpty) {
        html.write('<div class="sketch-meta-bar">');
        if (displayIndex.isNotEmpty) html.write('<strong>ინდექსი:</strong> $displayIndex &nbsp;&nbsp;&bull;&nbsp;&nbsp; ');
        if (displayHeight.isNotEmpty) html.write('<strong>სიმაღლითი გრადაცია:</strong> $displayHeight');
        html.write('</div>');
      }
      
      html.write('<div class="sketch-img-container">');
      if (data['sketch_url'] != null) {
        html.write('<img src="${data['sketch_url']}">');
      } else {
        html.write('<img src="data:image/png;base64,${data['sketch_base64']}">');
      }
      html.write('</div>');
      
      String above = data['sketch_above_ground'] ?? "";
      String below = data['sketch_below_ground'] ?? "";
      String totalHeight = data['sketch_total_height'] ?? "";

      if (totalHeight.isNotEmpty || above.isNotEmpty || below.isNotEmpty) {
        html.write('<div class="sketch-note">');
        html.write('<strong>ვერტიკალური პროფილის მიწისზედა ნაწილის დამოკიდებულება მიწისქვედა ნაწილთან.</strong><br/>');
        if (totalHeight.isNotEmpty) html.write('ჯამური სიმაღლე: $totalHeight &nbsp;&nbsp;');
        if (above.isNotEmpty) html.write('მიწისზედა: $above &nbsp;&nbsp;');
        if (below.isNotEmpty) html.write('მიწისქვედა: $below &nbsp;&nbsp;');
        html.write('</div>');
      }

      html.write('</div>');
    }

    html.write('</body></html>');
    return html.toString();
  }

  static void _addInfoRow(StringBuffer html, String label, dynamic value) {
    html.write('<tr><td class="label">$label:</td><td class="value">${value ?? ""}</td></tr>');
  }

  static String _convertSuperscriptsToHtml(String input) {
    if (input.isEmpty) return input;
    
    // Map of Unicode superscript characters to their normal counterparts
    final Map<String, String> superscriptToNormal = {
      '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
      'ᵃ': 'a', 'ᵇ': 'b', 'ᶜ': 'c', 'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g', 'ʰ': 'h', 'ⁱ': 'i', 'ʲ': 'j',
      'ᵏ': 'k', 'ˡ': 'l', 'ᵐ': 'm', 'ⁿ': 'n', 'ᵒ': 'o', 'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's', 'ᵗ': 't', 'ᵘ': 'u',
      'ᵛ': 'v', 'ʷ': 'w', 'ˣ': 'x', 'y': 'y', 'ᶻ': 'z',
      'ᴬ': 'A', 'ᴮ': 'B', 'ᴰ': 'D', 'ᴱ': 'E', 'ᴳ': 'G', 'ᴴ': 'H', 'ᴵ': 'I', 'ᴶ': 'J', 'ᴷ': 'K', 'ᴸ': 'L',
      'ᴹ': 'M', 'ᴺ': 'N', 'ᴼ': 'O', 'ᴾ': 'P', 'ᴿ': 'R', 'ᵀ': 'T', 'ᵁ': 'U', 'ⱽ': 'V', 'ᵂ': 'W',
      '⁺': '+', '⁻': '-', '⁼': '=', '⁽': '(', '⁾': ')', '˙': '.', '’': ',',
    };

    StringBuffer result = StringBuffer();
    bool inSup = false;

    for (int i = 0; i < input.length; i++) {
      String char = input[i];
      if (superscriptToNormal.containsKey(char)) {
        if (!inSup) {
          result.write('<sup>');
          inSup = true;
        }
        result.write(superscriptToNormal[char]);
      } else {
        if (inSup) {
          result.write('</sup>');
          inSup = false;
        }
        result.write(char);
      }
    }
    
    if (inSup) {
      result.write('</sup>');
    }

    return result.toString();
  }

}

class GoogleAuthClient extends http.BaseClient {
  final GoogleSignInAccount _account;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._account);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authHeaders = await _account.authHeaders;
    request.headers.addAll(authHeaders);
    return _client.send(request);
  }
}

class ApiKeyClient extends http.BaseClient {
  final String apiKey;
  final http.Client _client = http.Client();

  ApiKeyClient(this.apiKey);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url.replace(
      queryParameters: Map.from(request.url.queryParameters)..putIfAbsent('key', () => apiKey),
    );
    
    debugPrint('ApiKeyClient: [${request.method}] ${uri.host}${uri.path}');

    // We must create a new request because the URL is final in BaseRequest
    final http.StreamedResponse response;
    
    // Create new request
    final newRequest = http.StreamedRequest(request.method, uri);
    newRequest.headers.addAll(request.headers);
    newRequest.headers.remove('Authorization');
    
    newRequest.contentLength = request.contentLength;
    newRequest.followRedirects = request.followRedirects;
    newRequest.maxRedirects = request.maxRedirects;
    newRequest.persistentConnection = request.persistentConnection;

    // Pipe the body
    request.finalize().listen(
      newRequest.sink.add,
      onError: newRequest.sink.addError,
      onDone: newRequest.sink.close,
      cancelOnError: true,
    );

    response = await _client.send(newRequest);
    
    if (response.statusCode != 200) {
      // Consume stream to get error message
      final body = await response.stream.bytesToString();
      debugPrint('Google API Request Failed: ${response.statusCode} $body');
      // Re-throw with body info
      throw Exception('Google API Error (${response.statusCode}): $body');
    }
    
    return response;
  }
}
