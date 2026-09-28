import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
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
  PDFViewController? _pdfViewController;
  final FlutterTts _tts = FlutterTts();
  final FocusNode _focusNode = FocusNode();

  bool _isPlaying = false;
  int _currentPage = 0;
  int _totalPages = 0;
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
    _focusNode.dispose();
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
          _currentPage = 0;
        });
        // Request keyboard focus for arrow navigation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load file: $e')),
      );
    }
  }

  void _nextPage() {
    if (_pdfViewController != null && _currentPage < _totalPages - 1) {
      _pdfViewController!.setPage(_currentPage + 1);
    }
  }

  void _previousPage() {
    if (_pdfViewController != null && _currentPage > 0) {
      _pdfViewController!.setPage(_currentPage - 1);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.pageDown) {
        _nextPage();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.pageUp) {
        _previousPage();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _showListenDialog() {
    final textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7F5F0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Listen to Article',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste or enter the article text from this page to read aloud:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Paste news report or editorial text here...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6B1D1D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Reading Aloud'),
              onPressed: () async {
                final txt = textController.text.trim();
                if (txt.isNotEmpty) {
                  Navigator.pop(ctx);
                  await _tts.stop();
                  setState(() => _isPlaying = true);
                  await _tts.setSpeechRate(_speechRate);
                  await _tts.speak(txt);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAudio() async {
    if (_isPlaying) {
      await _tts.stop();
      setState(() => _isPlaying = false);
    } else {
      _showListenDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _pdfFileName ?? 'ePaper Reader',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Previous Page (Left Arrow)',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _currentPage > 0 ? _previousPage : null,
            ),
            IconButton(
              tooltip: 'Next Page (Right Arrow)',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
            ),
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
            : GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: PDFView(
                  filePath: _pdfFile!.path,
                  enableSwipe: true,
                  swipeHorizontal: true,
                  autoSpacing: false,
                  pageFling: false,
                  onRender: (pages) {
                    setState(() {
                      _totalPages = pages ?? 0;
                    });
                  },
                  onViewCreated: (PDFViewController vc) {
                    _pdfViewController = vc;
                    _focusNode.requestFocus();
                  },
                  onPageChanged: (page, total) {
                    setState(() {
                      _currentPage = page ?? 0;
                      _totalPages = total ?? 0;
                    });
                  },
                  onError: (error) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('PDF render error: $error')),
                    );
                  },
                ),
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
                        'Page ${_currentPage + 1} / $_totalPages',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '(Use ← / → keys)',
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _isPlaying ? Colors.red.shade700 : const Color(0xFF6B1D1D),
                        ),
                        onPressed: _toggleAudio,
                        icon: Icon(_isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded),
                        label: Text(_isPlaying ? 'Stop' : 'Listen Article'),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<double>(
                        tooltip: 'Reading Speed',
                        initialValue: _speechRate,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '${(_speechRate * 2).toStringAsFixed(1)}x',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        onSelected: (val) {
                          setState(() => _speechRate = val);
                          _tts.setSpeechRate(val);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 0.35, child: Text('0.7x Slow')),
                          PopupMenuItem(value: 0.5, child: Text('1.0x Normal')),
                          PopupMenuItem(value: 0.65, child: Text('1.3x Fast')),
                          PopupMenuItem(value: 0.8, child: Text('1.6x Very Fast')),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
