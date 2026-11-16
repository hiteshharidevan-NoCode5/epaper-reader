import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
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
      title: 'NuzEPpr',
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
  static const _intentChannel = MethodChannel('epaper_reader/intent');

  PdfController? _pdfController;
  final GlobalKey _captureKey = GlobalKey();

  String _documentTitle = 'NuzEPpr';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;
  int _viewerKey = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _setupNativeIntentListener();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _setupNativeIntentListener() async {
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewPdf' && call.arguments is Map) {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        final bytes = map['bytes'] as Uint8List?;
        final title = map['title'] as String? ?? 'NuzEPpr';
        if (bytes != null) await _loadPdfData(bytes, title);
      }
    });

    try {
      final result = await _intentChannel.invokeMethod('getInitialPdf');
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        final bytes = map['bytes'] as Uint8List?;
        final title = map['title'] as String? ?? 'NuzEPpr';
        if (bytes != null) await _loadPdfData(bytes, title);
      }
    } catch (_) {}
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyS && _pdfController != null) {
      _takeScreenshot();
      return true;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetPageFit();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.bracketRight ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.bracketLeft) {
      _prevPage();
      return true;
    }
    if (key == LogicalKeyboardKey.keyO) {
      _pickLocalFile();
      return true;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.keyQ ||
        key == LogicalKeyboardKey.keyX) {
      if (_pdfController != null) {
        _closeDocument();
        return true;
      }
    }
    return false;
  }

  Future<void> _takeScreenshot() async {
    if (_pdfController == null) return;
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'ePaper_p${_currentPage}_$timestamp.png';

      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final file = File('${downloadDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved screenshot: $fileName in Downloads'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Screenshot failed: $e')),
      );
    }
  }

  Future<void> _loadPdfData(Uint8List bytes, String title) async {
    setState(() => _isLoading = true);
    try {
      _pdfController?.dispose();
      final controller = PdfController(
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
        _viewerKey++;
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
        withData: true,
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
      _documentTitle = 'NuzEPpr';
      _pageCount = 0;
      _currentPage = 1;
    });
  }

  void _nextPage() {
    if (_pdfController != null && _currentPage < _pageCount) {
      _pdfController!.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _prevPage() {
    if (_pdfController != null && _currentPage > 1) {
      _pdfController!.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _resetPageFit() {
    if (_pdfController == null) return;
    _pdfController!.initialPage = _currentPage;
    setState(() => _viewerKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pdfController != null ? _documentTitle : 'NuzEPpr',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pdfController != null) ...[
            IconButton(
              focusNode: FocusNode(canRequestFocus: false),
              tooltip: 'Screenshot View (S)',
              icon: const Icon(Icons.camera_alt_outlined),
              onPressed: _takeScreenshot,
            ),
            IconButton(
              focusNode: FocusNode(canRequestFocus: false),
              tooltip: 'Fit Page to Screen (0)',
              icon: const Icon(Icons.fit_screen_rounded),
              onPressed: _resetPageFit,
            ),
            IconButton(
              focusNode: FocusNode(canRequestFocus: false),
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
              focusNode: FocusNode(canRequestFocus: false),
              tooltip: 'Next Page (→)',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _currentPage < _pageCount ? _nextPage : null,
            ),
            IconButton(
              focusNode: FocusNode(canRequestFocus: false),
              tooltip: 'Close (Esc / Q)',
              icon: const Icon(Icons.close_rounded),
              onPressed: _closeDocument,
            ),
          ],
          IconButton(
            focusNode: FocusNode(canRequestFocus: false),
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
                        'NuzEPpr',
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
              : RepaintBoundary(
                  key: _captureKey,
                  child: PdfView(
                    key: ValueKey('pdf_view_$_viewerKey'),
                    controller: _pdfController!,
                    scrollDirection: Axis.horizontal,
                    pageSnapping: true,
                    onDocumentLoaded: (doc) {
                      setState(() => _pageCount = doc.pagesCount);
                    },
                    onPageChanged: (page) {
                      setState(() => _currentPage = page);
                    },
                    builders: PdfViewBuilders<DefaultBuilderOptions>(
                      options: const DefaultBuilderOptions(),
                      documentLoaderBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      pageLoaderBuilder: (_) =>
                          const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, error) => Center(
                        child: Text('Error rendering page: $error'),
                      ),
                    ),
                  ),
                ),
    );
  }
}
