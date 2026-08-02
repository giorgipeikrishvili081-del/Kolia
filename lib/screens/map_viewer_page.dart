import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class MapViewerPage extends StatefulWidget {
  final File file;
  final String title;

  const MapViewerPage({super.key, required this.file, required this.title});

  @override
  State<MapViewerPage> createState() => _MapViewerPageState();
}

class _MapViewerPageState extends State<MapViewerPage> {
  late PdfControllerPinch _pdfController;
  bool _isPdf = false;

  @override
  void initState() {
    super.initState();
    _isPdf = widget.file.path.toLowerCase().endsWith('.pdf');
    if (_isPdf) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.file.path),
      );
    }
  }

  @override
  void dispose() {
    if (_isPdf) {
      _pdfController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for better viewing
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: _isPdf ? _buildPdfView() : _buildImageView(),
    );
  }

  Widget _buildPdfView() {
    return PdfViewPinch(
      controller: _pdfController,
    );
  }

  Widget _buildImageView() {
    return InteractiveViewer(
      panEnabled: true,
      minScale: 0.1,
      maxScale: 10.0, // Increased zoom limit
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: Center(
        child: Image.file(
          widget.file,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
