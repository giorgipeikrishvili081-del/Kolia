import 'dart:io';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/secrets.dart';

class GoogleDriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // NOTE: For Drive API to work on Android, you MUST provide the WEB Client ID here
    // even though this is an Android app.
    serverClientId: AppSecrets.googleDriveClientId,
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
  );

  static Future<GoogleSignInAccount?> signIn() async {
    // Try to sign in without prompting first
    var account = await _googleSignIn.signInSilently();
    // If that fails, show the popup
    account ??= await _googleSignIn.signIn();
    return account;
  }

  static Future<void> uploadAsGoogleDoc({
    required String title,
    required String htmlContent,
  }) async {
    final GoogleSignInAccount? account = await _googleSignIn.signIn();
    if (account == null) throw Exception('Google Sign-In failed or cancelled');

    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(authenticateClient);

    final driveFile = drive.File();
    driveFile.name = title;
    // Specify the target MIME type as Google Docs
    driveFile.mimeType = 'application/vnd.google-apps.document';

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

  static Future<void> uploadFormAsGoogleDoc(Map<String, dynamic> rawData) async {
    // Sanitize data for JSON encoding (handle Timestamps and other non-encodable types)
    final Map<String, dynamic> data = json.decode(json.encode(rawData, toEncodable: (item) {
      if (item is Timestamp) {
        return item.toDate().toIso8601String();
      }
      if (item is DateTime) {
        return item.toIso8601String();
      }
      // Return a string representation for anything else JSON doesn't know
      return item.toString();
    }));

    final String htmlContent = generateHtmlContent(data);
    
    final String? btkId = data['btk_index']?.toString();
    final String title = (btkId != null && btkId.isNotEmpty) 
        ? 'ბტკ ბლანკი - $btkId (${data['date'] ?? ''})'
        : 'ბტკ ბლანკი (${data['date'] ?? ''})';

    await uploadAsGoogleDoc(title: title, htmlContent: htmlContent);

    // Mark as uploaded in Firebase
    if (rawData['id'] != null) {
      await FirebaseService.markAsUploadedToDrive(rawData['id']);
    }
  }

  static String generateHtmlContent(Map<String, dynamic> data) {
    final StringBuffer html = StringBuffer();
    
    // Get team color from data, fallback to a dark blue-grey if not found
    String primaryColor = '#2c3e50'; // Default
    if (data['team_color'] != null) {
      try {
        final int colorValue = data['team_color'] is int 
            ? data['team_color'] 
            : int.parse(data['team_color'].toString());
        // Convert ARGB int to hex string #RRGGBB
        primaryColor = '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      } catch (e) {
        // Fallback on error
      }
    }

    html.write('<!DOCTYPE html><html><head><meta charset="utf-8">');
    html.write('<style>');
    html.write('body { font-family: "DejaVu Sans", "Helvetica", Arial, sans-serif; line-height: 1.5; color: #333; margin: 0; padding: 20px; }');
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

    // Vegetation Table
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

    // Soil Table
    if (data['soil_rows'] != null && (data['soil_rows'] as List).isNotEmpty) {
      html.write('<div class="section-header">IV. ნიადაგის პროფილის მორფოლოგიური დახასიათება</div>');
      html.write('<table class="data-table">');
      html.write('<thead><tr><th class="text-left">გენეტიკური ჰორიზონტი</th><th class="text-left">მორფოლოგიური დახასიათება</th><th class="text-left">ინდექსი</th></tr></thead>');
      html.write('<tbody>');
      for (var row in (data['soil_rows'] as List)) {
        html.write('<tr>');
        html.write('<td class="text-left">${row['genetic_horizon'] ?? ''}</td>');
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

    // Biomass Table (Page 4)
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
      // If no rows or all rows are empty, show at least 5 empty rows
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

    // Tree Taxation (Requested to be right after Biomass Study)
    if (data['tree_taxation_rows'] != null && (data['tree_taxation_rows'] as List).isNotEmpty) {
      html.write('<div class="section-header">VI. მცენარეულობის ტაქსაცია</div>');
      html.write('<table class="data-table">');
      html.write('<thead><tr><th>ხე №</th><th>სახეობა</th><th>D</th><th>H</th><th>K2</th><th>მოცულობა</th></tr></thead>');
      html.write('<tbody>');
      int treeIdx = 1;
      for (var row in (data['tree_taxation_rows'] as List)) {
        // Skip completely empty rows
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

    // Plot Size (Requested to be below Vegetation Taxation)
    if (data['taxation_plot_size'] != null && data['taxation_plot_size'].toString().isNotEmpty) {
      html.write('<div class="highlight-box">');
      html.write('<strong>ნაკვეთის ზომა</strong> ${data['taxation_plot_size']}');
      html.write('</div>');
    }

    // Tree Phytomass Table (Page 6)
    if (data['tree_phytomass_rows'] != null) {
      html.write('<div class="section-header">VII. ხე მცენარეების ფიტომასა</div>');
      html.write('<table class="data-table">');
      html.write('<thead>');
      html.write('<tr style="border: 2px solid #2c3e50;">');
      html.write('<th rowspan="2" style="border: 2px solid #2c3e50;">სახეობა</th>');
      html.write('<th colspan="3" style="border: 2px solid #2c3e50;">მმოც. წონა ტ/მ³</th>');
      html.write('<th colspan="5" style="border: 2px solid #2c3e50;">სველი ფიტომასა</th>');
      html.write('<th colspan="5" style="border: 2px solid #2c3e50;">მშრალი ფიტომასა</th>');
      html.write('<th rowspan="2" style="border: 2px solid #2c3e50;"></th>'); // Empty header for symmetry if needed
      html.write('</tr>');
      html.write('<tr class="sub-header" style="border: 2px solid #2c3e50;">');
      html.write('<th style="border: 2px solid #2c3e50;">მმოც.</th><th style="border: 2px solid #2c3e50;">სველი</th><th style="border: 2px solid #2c3e50;">მშრალი</th>');
      html.write('<th style="border: 2px solid #2c3e50;">მერქნ.</th><th style="border: 2px solid #2c3e50;">ფოთლ.</th><th style="border: 2px solid #2c3e50;">ტოტ.</th><th style="border: 2px solid #2c3e50;">ფესვ.</th><th style="border: 2px solid #2c3e50;">ჯამი</th>');
      html.write('<th style="border: 2px solid #2c3e50;">მერქნ.</th><th style="border: 2px solid #2c3e50;">ფოთლ.</th><th style="border: 2px solid #2c3e50;">ტოტ.</th><th style="border: 2px solid #2c3e50;">ფესვ.</th><th style="border: 2px solid #2c3e50;">ჯამი</th>');
      html.write('</tr>');
      html.write('</thead>');
      html.write('<tbody>');
      
      List rows = data['tree_phytomass_rows'] as List;
      // Filter out actually empty rows
      List activeRows = rows.where((row) => 
        !((row['species']?.isEmpty ?? true) && (row['v_vol']?.isEmpty ?? true) && (row['w_total']?.isEmpty ?? true))
      ).toList();

      if (activeRows.isEmpty) {
        // If all rows are empty, show 5 empty rows
        for (int i = 0; i < 5; i++) {
          html.write('<tr>');
          for (int j = 0; j < 15; j++) html.write('<td>&nbsp;</td>');
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

    // Vertical Structure Sketch
    final hasSketch = data['sketch_url'] != null || data['sketch_base64'] != null;
    if (hasSketch) {
      html.write('<div class="section-header">VIII. ვერტიკალური სტრუქტურა</div>');
      html.write('<div class="sketch-box">');
      
      // Title Bar
      String sTitle = data['sketch_title'] ?? "ვერტიკალური სტრუქტურის სქემა";
      html.write('<div class="sketch-title-bar">$sTitle</div>');
      
      // Meta Bar (Index / Height)
      String index = data['sketch_index'] ?? "";
      String height = data['sketch_height'] ?? "";
      
      // Clean up potential redundant labels from the data
      String displayIndex = index.replaceAll(RegExp(r'^ინდექსი:\s*', caseSensitive: false), '').trim();
      String displayHeight = height.replaceAll(RegExp(r'^სიმაღლე:\s*', caseSensitive: false), '').trim();

      if (displayIndex.isNotEmpty || displayHeight.isNotEmpty) {
        html.write('<div class="sketch-meta-bar">');
        if (displayIndex.isNotEmpty) html.write('<strong>ინდექსი:</strong> $displayIndex &nbsp;&nbsp;&bull;&nbsp;&nbsp; ');
        if (displayHeight.isNotEmpty) html.write('<strong>სიმაღლე:</strong> $displayHeight');
        html.write('</div>');
      }
      
      // Image Content
      html.write('<div class="sketch-img-container">');
      if (data['sketch_url'] != null) {
        // Use Cloud URL if available
        html.write('<img src="${data['sketch_url']}">');
      } else {
        // Fallback to local Base64
        html.write('<img src="data:image/png;base64,${data['sketch_base64']}">');
      }
      html.write('</div>');
      
      // Note/Footer
      String above = data['sketch_above_ground'] ?? "";
      String below = data['sketch_below_ground'] ?? "";

      if (height.isNotEmpty || above.isNotEmpty || below.isNotEmpty) {
        html.write('<div class="sketch-note">');
        html.write('<strong>ვერტიკალური პროფილის მიწისზედა ნაწილის დამოკიდებულება მიწისქვედა ნაწილთან.</strong><br/>');
        if (height.isNotEmpty) html.write('სიმაღლე: $height &nbsp;&nbsp;');
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

}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
