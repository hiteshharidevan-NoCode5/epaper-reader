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

    // --- ZOOM IN (+, =, or Ctrl + =) ---
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.3);
      return true;
    }

    // --- ZOOM OUT (-, or Ctrl + -) ---
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.77);
      return true;
    }

    // --- RESET ZOOM (0) ---
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _zoomReset();
      return true;
    }

    // --- TURN PAGES (Left/Right, PageUp/PageDown, [ / ]) ---
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

    // --- OPEN FILE (Ctrl+O or 'O') ---
    if ((isCtrl && key == LogicalKeyboardKey.keyO) || key == LogicalKeyboardKey.keyO) {
      _pickLocalFile();
      return true;
    }

    // --- CLOSE DOCUMENT (Ctrl+W, Esc, 'Q', or 'X') ---
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load PDF: $e')),
      );
    }
  }

  Future<void> _openFileBytes(Uint8List bytes, String title) async {
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
        SnackBar(content: Text('Failed to load PDF from data: $e')),
      );
    }
  }

  Future<void> _pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;

      if (file.path != null && file.path!.isNotEmpty) {
        await _openFilePath(file.path!, file.name);
      } else if (file.bytes != null) {
        await _openFileBytes(file.bytes!, file.name);
      } else {
        throw Exception("File data could not be retrieved.");
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
                        'Press O or Ctrl+O to open a newspaper PDF.\nUse + / - to Zoom, 0 to Reset, and ← / → to turn pages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6B1D1D),
                        ),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Open ePaper (O)'),
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
