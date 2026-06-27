import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart' as printing;
import 'package:kolia/services/database_helper.dart';

class FormDataStore {
  static List<Map<String, dynamic>> _cachedForms = [];

  static Future<List<Map<String, dynamic>>> get savedForms async {
    _cachedForms = await DatabaseHelper.instance.getAllForms();
    return _cachedForms;
  }

  static Future<int> addForm(Map<String, dynamic> data) async {
    return await DatabaseHelper.instance.insertForm(data);
  }

  static Future<void> deleteForm(int id) async {
    await DatabaseHelper.instance.deleteForm(id);
  }

  static Future<void> clearAllLocalForms() async {
    await DatabaseHelper.instance.clearAllData();
  }

  static String convertToCSV(Map<String, dynamic> data) {
    // Adding BOM for Excel compatibility with Georgian characters
    String csv = '\uFEFFველი,მნიშვნელობა\n';
    
    // If it's a BTK form, we might want to flatten the 'data' map for CSV
    Map<String, dynamic> exportData = Map.from(data);
    if (exportData.containsKey('data') && exportData['data'] is Map) {
      final innerData = exportData['data'] as Map<String, dynamic>;
      innerData.forEach((key, value) {
        if (value is! List) { // Skip tables in simple CSV
          exportData[key] = value;
        }
      });
      exportData.remove('data');
    }

    exportData.forEach((key, value) {
      String strValue = value?.toString() ?? '';
      String escapedValue = strValue.replaceAll('"', '""');
      csv += '$key,"$escapedValue"\n';
    });
    return csv;
  }

  static Future<String> _getExportDirectory() async {
    if (Platform.isAndroid) {
      // Request storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }

      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) {
        return dir.path;
      }
      
      final externalDir = await getExternalStorageDirectory();
      return externalDir?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else {
      final directory = await getDownloadsDirectory();
      return directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    }
  }

  static Future<String> savePdfToFile(Map<String, dynamic> data, String html) async {
    final directoryPath = await _getExportDirectory();
    final type = (data['ტიპი'] ?? 'ფორმა').toString();
    
    String name = (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? '';
    if (name.isEmpty) {
      name = data['ტიპი'] ?? 'ბტკ-ის ბლანკი';
    }

    final fileName = '${type.replaceAll(' ', '_')}_${name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(p.join(directoryPath, fileName));
    
    // Convert HTML to PDF bytes
    final Uint8List pdfBytes = await printing.Printing.convertHtml(
      html: html,
      format: pdf.PdfPageFormat.a4,
    );
    
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  static Future<void> savePdf(Map<String, dynamic> data, String html) async {
    // This is the most reliable way to "Save" on modern Android.
    // It opens the system print spooler where you can click "Save as PDF".
    String name = (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? 'ბტკ_ბლანკი';
    
    await printing.Printing.layoutPdf(
      onLayout: (pdf.PdfPageFormat format) async => await printing.Printing.convertHtml(
        html: html,
        format: format,
      ),
      name: name,
    );
  }

  static Future<void> sharePdf(Map<String, dynamic> data, String html) async {
    final Uint8List pdfBytes = await printing.Printing.convertHtml(
      html: html,
      format: pdf.PdfPageFormat.a4,
    );
    
    String name = (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? 'ბტკ_ბლანკი';
    await printing.Printing.sharePdf(
      bytes: pdfBytes, 
      filename: '${name.replaceAll(' ', '_')}.pdf',
      subject: 'ბტკ აღწერის ბლანკი: $name'
    );
  }

  static Future<void> openPdf(Map<String, dynamic> data, String html) async {
    await printing.Printing.layoutPdf(
      onLayout: (pdf.PdfPageFormat format) async => await printing.Printing.convertHtml(
        html: html,
        format: format,
      ),
      name: (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? 'ბტკ_ბლანკი',
    );
  }

  static Future<String> saveHtmlToFile(Map<String, dynamic> data, String html) async {
    final directoryPath = await _getExportDirectory();
    final type = (data['ტიპი'] ?? 'ფორმა').toString();
    
    String name = (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? '';
    if (name.isEmpty) {
      name = data['ტიპი'] ?? 'ბტკ-ის ბლანკი';
    }

    final fileName = '${type.replaceAll(' ', '_')}_${name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.html';
    final file = File(p.join(directoryPath, fileName));
    await file.writeAsString(html);
    return file.path;
  }

  static Future<String> saveCSVToFile(Map<String, dynamic> data) async {
    final csv = convertToCSV(data);
    final directoryPath = await _getExportDirectory();
    final type = (data['ტიპი'] ?? 'ფორმა').toString();
    
    String name = (data['ბტკ ინდექსი'] ?? data['data']?['btk_index'])?.toString() ?? '';
    if (name.isEmpty) {
      name = data['ტიპი'] ?? 'ბტკ-ის ბლანკი';
    }

    final fileName = '${type.replaceAll(' ', '_')}_${name.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(p.join(directoryPath, fileName));
    await file.writeAsString(csv);
    return file.path;
  }
}
