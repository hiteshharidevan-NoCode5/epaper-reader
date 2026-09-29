import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:app_links/app_links.dart';

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
        scaffoldBackgroundColor: const Color(0xFF181818),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF222222),
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
  String? _documentTitle;
  int _pageCount = 0;
  int _currentPage = 1;

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

  // Listens to WhatsApp / Telegram taps
  Future<void> _initIncomingLinks() async {
    // Check initial launch intent
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _loadPdfFromUri(initialUri);
    }

    // Check incoming intent while app is running in background
    _appLinks.uriLinkStream.listen((uri) {
      _loadPdfFromUri(uri);
    });
  }

  Future<void> _loadPdfFromUri(Uri uri) async {
    try {
      PdfDocument document;
      if (uri.scheme == 'content') {
        // Direct stream from Telegram / WhatsApp provider
        document = await PdfDocument.openData(
          await File.fromUri(uri).readAsBytes(),
        );
      } else {
        document = await PdfDocument.openFile(uri.toFilePath());
      }

      _pdfController?.dispose();
      setState(() {
        _documentTitle = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'ePaper Edition';
        _pageCount = document.pagesCount;
        _currentPage = 1;
        _pdfController = PdfControllerPinch(
          document: Future.value(document),
          initialPage: 1,
        );
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load document: $e')),
      );
    }
  }

  void _closeDocument() {
    _pdfController?.dispose();
    setState(() {
      _pdfController = null;
      _documentTitle = null;
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
                _documentTitle ?? 'ePaper Reader',
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
      body: _pdfController == null
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
                  SizedBox(height: 6),
                  Text(
                    'Open any ePaper directly from Telegram or WhatsApp.',
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
