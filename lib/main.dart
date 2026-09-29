import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:app_links/app_links.dart';
import 'package:uri_content/uri_content.dart';

void main() {
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

  String _documentTitle = 'ePaper Edition';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initIncomingLinks();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _initIncomingLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _loadPdfFromUri(initialUri);
      }
    } catch (_) {}

    _appLinks.uriLinkStream.listen((uri) {
      _loadPdfFromUri(uri);
    });
  }

  Future<void> _loadPdfFromUri(Uri uri) async {
    setState(() => _isLoading = true);
    try {
      Uint8List bytes;

      // Safe extraction of bytes from content:// or file:// or network
      if (uri.scheme == 'content') {
        bytes = await _uriContent.from(uri);
      } else if (uri.scheme == 'file') {
        // Only call toFilePath if it's explicitly a file:// scheme
        bytes = await _uriContent.from(uri);
      } else {
        bytes = await _uriContent.from(uri);
      }

      final document = await PdfDocument.openData(bytes);

      // Safe title extraction that never calls .pathSegments on content URIs
      String title = 'ePaper Edition';
      try {
        if (uri.path.isNotEmpty) {
          title = uri.path.split('/').last;
        }
      } catch (_) {}

      _pdfController?.dispose();
      setState(() {
        _documentTitle = title.isNotEmpty ? title : 'ePaper Edition';
        _pageCount = document.pagesCount;
        _currentPage = 1;
        _pdfController = PdfControllerPinch(
          document: Future.value(document),
          initialPage: 1,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load document: $e')),
      );
    }
  }

  void _closeDocument() {
    _pdfController?.dispose();
    setState(() {
      _pdfController = null;
      _documentTitle = 'ePaper Edition';
      _pageCount = 0;
      _currentPage = 1;
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyW) ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_pdfController != null) {
        _closeDocument();
        return true;
      }
    }

    if (_pdfController != null) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.pageDown) {
        _pdfController!.nextPage(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.pageUp) {
        _pdfController!.previousPage(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _pdfController != null
          ? AppBar(
              title: Text(
                _documentTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: 'Previous Page (←)',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _currentPage > 1
                      ? () => _pdfController?.previousPage(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                          )
                      : null,
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
                  onPressed: _currentPage < _pageCount
                      ? () => _pdfController?.nextPage(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                          )
                      : null,
                ),
                IconButton(
                  tooltip: 'Close (Esc / Ctrl+W)',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _closeDocument,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pdfController == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.newspaper_rounded, size: 84, color: Colors.white24),
                      SizedBox(height: 16),
                      Text(
                        'ePaper Reader',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Open any ePaper directly from Telegram, WhatsApp, or Files.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white54),
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
    );
  }
}
