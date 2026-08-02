import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart' as printing;

class FileExportService {
  static String convertToCSV(Map<String, dynamic> data) {
    String csv = '\uFEFFველი,მნიშვნელობა\n';
    
    final tables = {
      'vegetation_rows': 'მცენარეულობის სახეობრივი შემადგენლობა',
      'soil_rows': 'ნიადაგის პროფილის მორფოლოგიური დახასიათება',
      'biomass_rows': 'გეომასების კვლევა',
      'tree_taxation_rows': 'მცენარეულობის ტაქსაცია',
      'tree_phytomass_rows': 'ხე მცენარეების ფიტომასა'
    };

    Map<String, dynamic> exportData = {};
    final ignoreKeys = {
      'sketch_base64', 'id', 'db_id', 'source', 'is_synced', 
      'is_uploaded', 'data', 'updated_at', 'created_at', 'team_color', 'edited_by_admin'
    };

    _processMapIntoExport(data, exportData, tables, ignoreKeys);
    if (data.containsKey('data') && data['data'] is Map) {
      _processMapIntoExport(data['data'] as Map<String, dynamic>, exportData, tables, ignoreKeys);
    }

    exportData.forEach((key, value) {
      if (value == null || value.toString().isEmpty) return;
      String valStr = value.toString();
      if (key.contains('ნიადაგის პროფილის მორფოლოგიური დახასიათება')) {
        valStr = _normalizeSuperscripts(valStr);
      }
      csv += '"${key.replaceAll('"', '""')}","${valStr.replaceAll('"', '""')}"\n';
    });
    return csv;
  }

  static String _normalizeSuperscripts(String input) {
    final Map<String, String> superscriptToNormal = {
      '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
      'ᵃ': 'a', 'ᵇ': 'b', 'ᶜ': 'c', 'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g', 'ʰ': 'h', 'ⁱ': 'i', 'ʲ': 'j',
      'ᵏ': 'k', 'ˡ': 'l', 'ᵐ': 'm', 'ⁿ': 'n', 'ᵒ': 'o', 'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's', 'ᵗ': 't', 'ᵘ': 'u',
      'ᵛ': 'v', 'ʷ': 'w', 'ˣ': 'x', 'y': 'y', 'ᶻ': 'z',
      'ᴬ': 'A', 'ᴮ': 'B', 'ᴰ': 'D', 'ᴱ': 'E', 'ᴳ': 'G', 'ᴴ': 'H', 'ᴵ': 'I', 'ᴶ': 'J', 'ᴷ': 'K', 'ᴸ': 'L',
      'ᴹ': 'M', 'ᴺ': 'N', 'ᴼ': 'O', 'ᴾ': 'P', 'ᴿ': 'R', 'ᵀ': 'T', 'ᵁ': 'U', 'ⱽ': 'V', 'ᵂ': 'W',
      '⁺': '+', '⁻': '-', '⁼': '=', '⁽': '(', '⁾': ')', '˙': '.', '’': ',',
    };
    
    String result = input;
    superscriptToNormal.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    return result;
  }

  static void _processMapIntoExport(Map<String, dynamic> source, Map<String, dynamic> target, Map<String, String> tables, Set<String> ignoreKeys) {
    source.forEach((key, value) {
      if (ignoreKeys.contains(key)) return;
      if (tables.containsKey(key)) {
        if (value is List && value.isNotEmpty) {
          for (int i = 0; i < value.length; i++) {
            final row = value[i];
            if (row is Map) {
              String rowStr = row.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).map((e) => '${e.key}: ${e.value}').join(' | ');
              if (rowStr.isNotEmpty) target['${tables[key]} #${i + 1}'] = rowStr;
            }
          }
        }
      } else if (value is! List && !target.containsKey(key)) {
        target[key] = value;
      }
    });
  }

  static Future<String> _getExportDirectory() async {
    if (Platform.isAndroid) {
      if (!await Permission.storage.isGranted) await Permission.storage.request();
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir.path;
      return (await getExternalStorageDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
    }
    return (await getDownloadsDirectory())?.path ?? (await getApplicationDocumentsDirectory()).path;
  }

  static Future<void> savePdf(Map<String, dynamic> data, String html) async {
    String name = (data['btk_index'] ?? data['data']?['btk_index'])?.toString() ?? 'ბტკ_ბლანკი';
    await printing.Printing.layoutPdf(
      onLayout: (format) async => await printing.Printing.convertHtml(html: html, format: format),
      name: name,
    );
  }

  static Future<String> saveCSVToFile(Map<String, dynamic> data) async {
    final csv = convertToCSV(data);
    final directoryPath = await _getExportDirectory();
    String name = (data['btk_index'] ?? data['data']?['btk_index'])?.toString() ?? 'ბლანკი';
    final fileName = 'BTK_${name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(directoryPath, fileName));
    await file.writeAsString(csv);
    return file.path;
  }

  static Future<String> saveAllToCSV(List<Map<String, dynamic>> forms) async {
    if (forms.isEmpty) return '';
    final directoryPath = await _getExportDirectory();
    final file = File(p.join(directoryPath, 'BTK_Bulk_Export_${DateTime.now().millisecondsSinceEpoch}.csv'));
    
    Set<String> headersSet = {};
    final tables = {'vegetation_rows': 'მცენარეულობის სახეობრივი შემადგენლობა', 'soil_rows': 'ნიადაგის პროფილის მორფოლოგიური დახასიათება', 'biomass_rows': 'გეომასების კვლევა', 'tree_taxation_rows': 'მცენარეულობის ტაქსაცია', 'tree_phytomass_rows': 'ხე მცენარეების ფიტომასა'};

    for (var form in forms) {
      void process(Map<String, dynamic> m) {
        m.forEach((key, value) {
          if (tables.containsKey(key)) headersSet.add(tables[key]!);
          else if (value is! List && value is! Map && !['sketch_base64', 'id', 'db_id', 'data'].contains(key)) headersSet.add(key);
        });
      }
      process(form);
      if (form['data'] is Map) process(form['data']);
    }

    List<String> headers = headersSet.toList()..sort();
    String csv = '\uFEFF${headers.map((h) => '"${h.replaceAll('"', '""')}"').join(',')}\n';
    
    for (var form in forms) {
      Map<String, dynamic> flattened = {};
      void fill(Map<String, dynamic> s) {
        s.forEach((k, v) {
          if (tables.containsKey(k) && v is List) {
            String val = v.map((r) => r is Map ? r.entries.map((e) => '${e.key}: ${e.value}').join(' | ') : r.toString()).join(' || ');
            if (k == 'soil_rows') {
              val = _normalizeSuperscripts(val);
            }
            flattened[tables[k]!] = val;
          }
          else if (v is! List && v is! Map) flattened[k] = v;
        });
      }
      fill(form);
      if (form['data'] is Map) fill(form['data']);
      csv += '${headers.map((h) => '"${flattened[h]?.toString().replaceAll('"', '""') ?? ''}"').join(',')}\n';
    }
    await file.writeAsString(csv);
    return file.path;
  }
}
