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

  PdfControllerPinch? _pdfController;
  final GlobalKey _captureKey = GlobalKey();

  String _documentTitle = 'NuzEPpr';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

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
        if (bytes != null) {
          await _loadPdfData(bytes, title);
        }
      }
    });

    try {
      final result = await _intentChannel.invokeMethod('getInitialPdf');
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        final bytes = map['bytes'] as Uint8List?;
        final title = map['title'] as String? ?? 'NuzEPpr';
        if (bytes != null) {
          await _loadPdfData(bytes, title);
        }
      }
    } catch (_) {}
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed;

    if (key == LogicalKeyboardKey.keyS && _pdfController != null) {
      _takeScreenshot();
      return true;
    }

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

  Future<void> _takeScreenshot() async {
    if (_pdfController == null) return;
    try {
      final RenderRepaintBoundary? boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final Uint8List pngBytes = byteData.buffer.asUint8List();
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

  bool get _isZoomedIn {
    if (_pdfController == null) return false;
    try {
      final fit = _pdfController!.calculatePageFitMatrix(pageNumber: _currentPage);
      final curScale = _pdfController!.value.getMaxScaleOnAxis();
      final fitScale = fit?.getMaxScaleOnAxis() ?? 1.0;
      return curScale > (fitScale * 1.08);
    } catch (_) {
      return false;
    }
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    if (_isZoomedIn) return;
    final vx = details.primaryVelocity ?? 0;
    if (vx < -250) {
      _nextPage();
    } else if (vx > 250) {
      _prevPage();
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
          _pdfController != null ? _documentTitle : 'NuzEPpr',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pdfController != null) ...[
            IconButton(
              tooltip: 'Screenshot View (S)',
              icon: const Icon(Icons.camera_alt_outlined),
              onPressed: _takeScreenshot,
            ),
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
              : Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        _nextPage();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        _prevPage();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: _handleHorizontalSwipe,
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: PdfViewPinch(
                        controller: _pdfController!,
                        onPageChanged: (page) {
                          setState(() => _currentPage = page);
                        },
                      ),
                    ),
                  ),
                ),
    );
  }
}
