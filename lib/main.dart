import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const EPaperApp());
}

class EPaperApp extends StatelessWidget {
  const EPaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ePaper Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6B1D1D),
        scaffoldBackgroundColor: const Color(0xFFF7F5F0),
      ),
      home: const EPaperViewerScreen(),
    );
  }
}

class EPaperViewerScreen extends StatefulWidget {
  const EPaperViewerScreen({super.key});

  @override
  State<EPaperViewerScreen> createState() => _EPaperViewerScreenState();
}

class _EPaperViewerScreenState extends State<EPaperViewerScreen> {
  File? _pdfFile;
  String? _pdfFileName;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final FlutterTts _tts = FlutterTts();

  bool _isPlaying = false;
  int _currentPage = 1;
  int _pageCount = 0;
  double _speechRate = 0.5;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(_speechRate);

    _tts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
      });
    });

    _tts.setErrorHandler((msg) {
      setState(() {
        _isPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio Error: $msg')),
      );
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _pickPdfFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        await _tts.stop();
        setState(() {
          _pdfFile = File(result.files.single.path!);
          _pdfFileName = result.files.single.name;
          _isPlaying = false;
          _currentPage = 1;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load file: $e')),
      );
    }
  }

  Future<void> _readAloudCurrentPage() async {
    if (_pdfFile == null) return;

    if (_isPlaying) {
      await _tts.stop();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      final List<int> bytes = await _pdfFile!.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      int targetIndex = _currentPage - 1;
      if (targetIndex < 0) targetIndex = 0;
      if (targetIndex >= document.pages.count) targetIndex = document.pages.count - 1;

      PdfTextExtractor extractor = PdfTextExtractor(document);
      String text = extractor.extractText(startPageIndex: targetIndex, endPageIndex: targetIndex);
      document.dispose();

      text = text.trim();
      if (text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No selectable text found on this page (it might be a scanned image).'),
          ),
        );
        return;
      }

      setState(() => _isPlaying = true);
      await _tts.setSpeechRate(_speechRate);
      await _tts.speak(text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading text: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pdfFileName ?? 'ePaper Reader',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Open ePaper PDF',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: _pickPdfFile,
          ),
        ],
      ),
      body: _pdfFile == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.newspaper_rounded, size: 90, color: Colors.brown.shade300),
                    const SizedBox(height: 20),
                    const Text(
                      'No ePaper loaded',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select a downloaded newspaper PDF from your files to read or listen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _pickPdfFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Open Newspaper PDF', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            )
          : SfPdfViewer.file(
              _pdfFile!,
              controller: _pdfViewerController,
              canShowScrollHead: true,
              canShowScrollStatus: true,
              enableDoubleTapZooming: true,
              onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                setState(() {
                  _pageCount = details.document.pages.count;
                  _currentPage = 1;
                });
              },
              onPageChanged: (PdfPageChangedDetails details) {
                setState(() {
                  _currentPage = details.newPageNumber;
                });
              },
            ),
      bottomNavigationBar: _pdfFile != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Text(
                      'Page $_currentPage / $_pageCount',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    // Read Aloud / Stop button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _isPlaying ? Colors.red.shade700 : const Color(0xFF6B1D1D),
                      ),
                      onPressed: _readAloudCurrentPage,
                      icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded),
                      label: Text(_isPlaying ? 'Stop' : 'Listen Page'),
                    ),
                    const SizedBox(width: 8),
                    // Speech Speed Dropdown
                    PopupMenuButton<double>(
                      tooltip: 'Reading Speed',
                      initialValue: _speechRate,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          '${(_speechRate * 2).toStringAsFixed(2)}x',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      onSelected: (val) {
                        setState(() => _speechRate = val);
                        _tts.setSpeechRate(val);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 0.35, child: Text('0.7x Slow')),
                        const PopupMenuItem(value: 0.5, child: Text('1.0x Normal')),
                        const PopupMenuItem(value: 0.65, child: Text('1.3x Fast')),
                        const PopupMenuItem(value: 0.8, child: Text('1.6x Very Fast')),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
