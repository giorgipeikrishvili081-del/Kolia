import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kolia/services/plant_id_service.dart';

class PlantIdPage extends StatefulWidget {
  const PlantIdPage({super.key});

  @override
  State<PlantIdPage> createState() => _PlantIdPageState();
}

class _PlantIdPageState extends State<PlantIdPage> {
  File? _image;
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  final _service = PlantIdService();
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
          _result = null;
          _errorMessage = null;
        });
        _identifyPlant();
      }
    } catch (e) {
      setState(() => _errorMessage = "Camera access error: $e");
    }
  }

  Future<void> _identifyPlant() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Calling the service which returns a PlantIdResponse object
    final response = await _service.identifyPlant(_image!);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.success) {
          // Assigning the nested 'data' Map to _result
          _result = response.data;
        } else {
          _errorMessage = response.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('მცენარის იდენტიფიკაცია', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_image!, height: 300, width: double.infinity, fit: BoxFit.cover),
              )
            else
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_enhance_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('გადაიღეთ ან აირჩიეთ ფოთლის ფოტო', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('კამერა'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('გალერეა'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('მიმდინარეობს ანალიზი...', style: TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              )
            else if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              )
            else if (_result != null)
              _buildResults(_result!)
          ],
        ),
      ),
    );
  }

  Widget _buildResults(Map<String, dynamic> result) {
    final results = result['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) {
      return const Center(child: Text('მცენარის სახეობა ვერ მოიძებნა.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'საუკეთესო შედეგები',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...results.take(5).map((res) {
          final species = (res['species'] as Map<String, dynamic>?) ?? {};
          final scoreNum = res['score'] as num? ?? 0.0;
          final score = scoreNum.toDouble() * 100;
          final commonNames = species['commonNames'] as List<dynamic>? ?? [];
          final scientificName = species['scientificNameWithoutAuthor'] ?? species['scientificName'] ?? 'უცნობი სახეობა';
          
          // Display the first common name if available, otherwise fallback to scientific name
          final displayName = commonNames.isNotEmpty ? commonNames.first.toString() : scientificName;
          final familyName = species['family']?['scientificNameWithoutAuthor'] ?? species['family']?['scientificName'] ?? 'უცნობია';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              onTap: () {
                Navigator.pop(context, displayName);
              },
              title: Text(
                displayName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.primary),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (commonNames.isNotEmpty)
                    Text('სამეცნიერო სახელი: $scientificName', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic))
                  else
                    Text('ოჯახი: $familyName', style: const TextStyle(fontSize: 13)),
                  
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      color: score > 70 ? Colors.green : Colors.orange,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('სიზუსტე: ${score.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
