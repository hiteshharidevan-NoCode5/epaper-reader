import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
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
  StreamSubscription<Uri>? _linkSubscription;

  String _documentTitle = 'ePaper Edition';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initIncomingLinks();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _linkSubscription?.cancel();
    _pdfController?.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed;

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.3);
      return true;
    }

    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.77);
      return true;
    }

    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _zoomReset();
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.bracketRight) {
      _nextPage();
      return true;
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.bracketLeft) {
      _prevPage();
      return true;
    }

    if ((isCtrl && key == LogicalKeyboardKey.keyO) || key == LogicalKeyboardKey.keyO) {
      _pickLocalFile();
      return true;
    }

    if ((isCtrl && key == LogicalKeyboardKey.keyW) ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.keyQ ||
        key == LogicalKeyboardKey.keyX) {
      if (_pdfController != null) {
        _closeDocument();
        return true;
      }
    }

    return false;
  }

  Future<void> _initIncomingLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingUri(uri),
      onError: (_) {},
    );
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      String title = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'ePaper Edition';

      if (uri.scheme == 'file') {
        final file = File(uri.toFilePath());
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          await _loadPdfData(bytes, title);
          return;
        }
      }

      // If passed as raw string path
      if (File(uri.path).existsSync()) {
        final bytes = await File(uri.path).readAsBytes();
        await _loadPdfData(bytes, title);
        return;
      }

      throw Exception('Direct stream unavailable');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file directly. Press O to pick from Files.')),
      );
    }
  }

  Future<void> _loadPdfData(Uint8List bytes, String title) async {
    try {
      _pdfController?.dispose();
      final controller = PdfControllerPinch(
        document: PdfDocument.openData(bytes),
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
        withData: true, // Loads bytes directly across ChromeOS container boundary
      );

      if (result != null && result.files.single.bytes != null) {
        await _loadPdfData(result.files.single.bytes!, result.files.single.name);
      } else if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        await _loadPdfData(bytes, result.files.single.name);
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

  void _zoomBy(double factor) {
    if (_pdfController == null) return;
    try {
      final Size screenSize = MediaQuery.of(context).size;
      final Offset center = Offset(screenSize.width / 2, screenSize.height / 2);

      final Matrix4 current = _pdfController!.value;
      final Matrix4 translationToCenter = Matrix4.translationValues(-center.dx, -center.dy, 0);
      final Matrix4 scaleMatrix = Matrix4.diagonal3Values(factor, factor, 1.0);
      final Matrix4 translationBack = Matrix4.translationValues(center.dx, center.dy, 0);

      final Matrix4 newMatrix = translationBack * scaleMatrix * translationToCenter * current;

      _pdfController!.goTo(
        destination: newMatrix,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } catch (_) {}
  }

  void _zoomReset() {
    if (_pdfController == null) return;
    try {
      final matrix = _pdfController!.calculatePageFitMatrix(pageNumber: _currentPage);
      if (matrix != null) {
        _pdfController!.goTo(
          destination: matrix,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pdfController != null ? _documentTitle : 'ePaper Reader',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pdfController != null) ...[
            IconButton(
              tooltip: 'Zoom Out (-)',
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: () => _zoomBy(0.77),
            ),
            IconButton(
              tooltip: 'Reset Fit (0)',
              icon: const Icon(Icons.fit_screen_rounded),
              onPressed: _zoomReset,
            ),
            IconButton(
              tooltip: 'Zoom In (+)',
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _zoomBy(1.3),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Previous Page (←)',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _currentPage > 1 ? _prevPage : null,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
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
              tooltip: 'Close (Esc / Q)',
              icon: const Icon(Icons.close_rounded),
              onPressed: _closeDocument,
            ),
          ],
          IconButton(
            tooltip: 'Open PDF (O)',
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
                        'Press O or click below to open any downloaded newspaper.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1D1D),
                        ),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Open ePaper from Files (O)'),
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
    );
  }
}
