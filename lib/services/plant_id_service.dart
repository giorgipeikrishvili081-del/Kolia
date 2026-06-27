import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kolia/services/secrets.dart';

class PlantIdResponse {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  PlantIdResponse({required this.success, this.data, this.error});
}

class PlantIdService {
  // Your API key
  static const String _apiKey = AppSecrets.plantIdApiKey;
  
  // Using separate components for Uri.https to prevent URL corruption
  static const String _authority = 'my-api.plantnet.org';
  static const String _path = '/v2/identify/all';

  Future<PlantIdResponse> identifyPlant(File imageFile) async {
    try {
      // This builds: https://my-api.plantnet.org/v2/identify/all?api-key=...
      // It ensures that "include-common-names" is NOT part of the request.
      // Adding 'lang': 'ka' to request names in Georgian (ISO 639-1 code)
      final uri = Uri.https(_authority, _path, {
        'api-key': _apiKey,
      });
      
      // Verification print: Check your "Run" tab in Android Studio for this line!
      if (kDebugMode) {
        print('--- PLANT ID API CALL: $uri ---');
      }

      var request = http.MultipartRequest('POST', uri);
      
      // Add the image file
      var file = await http.MultipartFile.fromPath(
        'images',
        imageFile.path,
      );
      request.files.add(file);
      
      // Mandatory field for Pl@ntNet
      request.fields['organs'] = 'auto';

      // Send the request with a timeout
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return PlantIdResponse(
          success: true,
          data: jsonDecode(response.body),
        );
      } else {
        String errorDetail = 'Status ${response.statusCode}';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            errorDetail = body['message'] ?? body['error'] ?? errorDetail;
          }
        } catch (_) {}
        
        return PlantIdResponse(
          success: false, 
          error: 'Pl@ntNet-ის შეცდომა: $errorDetail'
        );
      }
    } catch (e) {
      return PlantIdResponse(
        success: false, 
        error: 'ქსელის შეცდომა: $e'
      );
    }
  }
}
