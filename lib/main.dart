import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:app_links/app_links.dart';
import 'package:uri_content/uri_content.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LightweightEPaperApp());
}

class LightweightEPaperApp extends StatelessWidget {
  const LightweightEPaperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ePaper Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF141414),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const ReaderHomeScreen(),
    );
  }
}

class ReaderHomeScreen extends StatefulWidget {
  const ReaderHomeScreen({super.key});

  @override
  State<ReaderHomeScreen> createState() => _ReaderHomeScreenState();
}

class _ReaderHomeScreenState extends State<ReaderHomeScreen> {
  PdfControllerPinch? _pdfController;
  final _appLinks = AppLinks();
  final _uriContent = UriContent();
  final FocusNode _keyboardFocusNode = FocusNode();
  StreamSubscription<Uri>? _linkSubscription;

  String _documentTitle = 'ePaper Edition';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Non-blocking initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initIncomingLinks();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _keyboardFocusNode.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _initIncomingLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (initialUri != null) {
        _loadPdfFromUri(initialUri);
      }
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _loadPdfFromUri(uri);
      },
      onError: (_) {},
    );
  }

  Future<void> _pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final bytes = await file.readAsBytes();
        _openPdfData(bytes, result.files.single.name);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open file: $e')),
      );
    }
  }

  Future<void> _loadPdfFromUri(Uri uri) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // 5-second timeout to prevent indefinite hangs if permission was revoked
      final Uint8List bytes = await _uriContent.from(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('File access timed out'),
      );

      String title = 'ePaper Edition';
      try {
        if (uri.pathSegments.isNotEmpty) {
          title = uri.pathSegments.last;
        }
      } catch (_) {}

      await _openPdfData(bytes, title);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $e')),
      );
    }
  }

  Future<void> _openPdfData(Uint8List bytes, String title) async {
    _pdfController?.dispose();
    final controller = PdfControllerPinch(
      document: PdfDocument.openData(bytes),
      initialPage: 1,
    );

    final doc = await controller.document;

    if (!mounted) return;
    setState(() {
      _documentTitle = title.isNotEmpty ? title : 'ePaper Edition';
      _pageCount = doc.pagesCount;
      _currentPage = 1;
      _pdfController = controller;
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  void _closeDocument() {
    _pdfController?.dispose();
    setState(() {
      _pdfController = null;
      _documentTitle = 'ePaper Edition';
      _pageCount = 0;
      _currentPage = 1;
    });
    _keyboardFocusNode.requestFocus();
  }

  void _nextPage() {
    if (_pdfController != null && _currentPage < _pageCount) {
      _pdfController!.nextPage(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _prevPage() {
    if (_pdfController != null && _currentPage > 1) {
      _pdfController!.previousPage(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyO) {
      _pickLocalFile();
      return KeyEventResult.handled;
    }

    if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyW) ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_pdfController != null) {
        _closeDocument();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _nextPage();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _prevPage();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _keyboardFocusNode.requestFocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _pdfController != null ? _documentTitle : 'ePaper Reader',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_pdfController != null) ...[
                IconButton(
                  tooltip: 'Previous Page (←)',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _currentPage > 1 ? _prevPage : null,
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      '$_currentPage / $_pageCount',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next Page (→)',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _currentPage < _pageCount ? _nextPage : null,
                ),
                IconButton(
                  tooltip: 'Close (Esc / Ctrl+W)',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _closeDocument,
                ),
              ],
              IconButton(
                tooltip: 'Open PDF (Ctrl+O)',
                icon: const Icon(Icons.folder_open_rounded),
                onPressed: _pickLocalFile,
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _pdfController == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.newspaper_rounded, size: 84, color: Colors.white24),
                          const SizedBox(height: 16),
                          const Text(
                            'ePaper Reader',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap any ePaper in Telegram, WhatsApp, or press Ctrl + O.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.white54),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6B1D1D),
                            ),
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Open ePaper (Ctrl+O)'),
                            onPressed: _pickLocalFile,
                          ),
                        ],
                      ),
                    )
                  : PdfViewPinch(
                      controller: _pdfController!,
                      onPageChanged: (page) {
                        setState(() => _currentPage = page);
                      },
                    ),
        ),
      ),
    );
  }
}
