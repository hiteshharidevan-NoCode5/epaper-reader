import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:app_links/app_links.dart';
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
  final FocusNode _keyboardFocusNode = FocusNode();
  StreamSubscription<Uri>? _linkSubscription;

  String _documentTitle = 'ePaper Edition';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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
        _handleUri(initialUri);
      }
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (_) {},
    );
  }

  Future<void> _handleUri(Uri uri) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      String path = uri.toFilePath();
      await _openFilePath(path, uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'ePaper Edition');
    } catch (_) {
      // Fallback for content:// or non-standard file paths
      try {
        final filePath = uri.path;
        if (filePath.isNotEmpty && File(filePath).existsSync()) {
          await _openFilePath(filePath, 'ePaper Edition');
        } else {
          throw Exception('Unable to read direct URI');
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open document from link. Please use Ctrl+O to select.')),
        );
      }
    }
  }

  Future<void> _openFilePath(String path, String title) async {
    try {
      _pdfController?.dispose();
      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(path),
        initialPage: 1,
      );

      final doc = await controller.document;

      if (!mounted) return;
      setState(() {
        _documentTitle = title;
        _pageCount = doc.pagesCount;
        _currentPage = 1;
        _pdfController = controller;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keyboardFocusNode.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load PDF: $e')),
      );
    }
  }

  Future<void> _pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        await _openFilePath(path, result.files.single.name);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error choosing file: $e')),
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
    _keyboardFocusNode.requestFocus();
  }

  void _nextPage() {
    if (_pdfController != null && _currentPage < _pageCount) {
      _pdfController!.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _prevPage() {
    if (_pdfController != null && _currentPage > 1) {
      _pdfController!.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl + O: Open file
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyO) {
      _pickLocalFile();
      return KeyEventResult.handled;
    }

    // Ctrl + W or Escape: Close
    if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyW) ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_pdfController != null) {
        _closeDocument();
        return KeyEventResult.handled;
      }
    }

    // Arrow keys & Page navigation
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
                            'Press Ctrl + O to open a newspaper PDF.',
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
