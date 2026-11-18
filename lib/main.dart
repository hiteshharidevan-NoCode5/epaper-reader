import 'dart:io';
import 'dart:async';
import 'dart:convert';
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

class RecentEPaper {
  final String id;
  final String title;
  final String filePath;
  final int openedAtMs;
  final int sizeBytes;

  RecentEPaper({
    required this.id,
    required this.title,
    required this.filePath,
    required this.openedAtMs,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'openedAtMs': openedAtMs,
        'sizeBytes': sizeBytes,
      };

  factory RecentEPaper.fromJson(Map<String, dynamic> json) => RecentEPaper(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        openedAtMs: json['openedAtMs'] as int,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

class ReaderHomeScreen extends StatefulWidget {
  const ReaderHomeScreen({super.key});

  @override
  State<ReaderHomeScreen> createState() => _ReaderHomeScreenState();
}

class _ReaderHomeScreenState extends State<ReaderHomeScreen> {
  static const _intentChannel = MethodChannel('epaper_reader/intent');
  static const String _historyDirPath =
      '/data/user/0/com.example.epaper_reader/files/recent_epapers';
  static const int _maxRecentItems = 8;

  PdfController? _pdfController;
  Uint8List? _pdfBytes;
  final GlobalKey _captureKey = GlobalKey();
  final TransformationController _transformController = TransformationController();

  String _documentTitle = 'NuzEPpr';
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isZoomed = false;
  int _viewerKey = 0;
  List<RecentEPaper> _recentPapers = [];

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _loadRecentHistory();
    _setupNativeIntentListener();
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _pdfController?.dispose();
    super.dispose();
  }

  Future<Directory> _ensureHistoryDir() async {
    final dir = Directory(_historyDirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _loadRecentHistory() async {
    try {
      final dir = await _ensureHistoryDir();
      final indexFile = File('${dir.path}/history.json');
      if (!await indexFile.exists()) return;

      final raw = await indexFile.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      final validItems = <RecentEPaper>[];

      for (final entry in decoded) {
        final item = RecentEPaper.fromJson(Map<String, dynamic>.from(entry as Map));
        if (await File(item.filePath).exists()) {
          validItems.add(item);
        }
      }

      if (!mounted) return;
      setState(() => _recentPapers = validItems);
    } catch (_) {}
  }

  Future<void> _saveToRecentHistory(Uint8List bytes, String title) async {
    try {
      final dir = await _ensureHistoryDir();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = now.toString();
      final cachedPath = '${dir.path}/$id.pdf';

      await File(cachedPath).writeAsBytes(bytes, flush: true);

      final updated = List<RecentEPaper>.from(_recentPapers);
      // Remove older entry with identical title & size to avoid duplicates
      updated.removeWhere((item) {
        final isDup = item.title == title && item.sizeBytes == bytes.length;
        if (isDup) {
          try {
            File(item.filePath).deleteSync();
          } catch (_) {}
        }
        return isDup;
      });

      updated.insert(
        0,
        RecentEPaper(
          id: id,
          title: title,
          filePath: cachedPath,
          openedAtMs: now,
          sizeBytes: bytes.length,
        ),
      );

      while (updated.length > _maxRecentItems) {
        final removed = updated.removeLast();
        try {
          await File(removed.filePath).delete();
        } catch (_) {}
      }

      final indexFile = File('${dir.path}/history.json');
      await indexFile.writeAsString(
        jsonEncode(updated.map((e) => e.toJson()).toList()),
        flush: true,
      );

      if (!mounted) return;
      setState(() => _recentPapers = updated);
    } catch (_) {}
  }

  Future<void> _removeRecentItem(RecentEPaper item) async {
    try {
      final dir = await _ensureHistoryDir();
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();

      final updated = _recentPapers.where((e) => e.id != item.id).toList();
      final indexFile = File('${dir.path}/history.json');
      await indexFile.writeAsString(
        jsonEncode(updated.map((e) => e.toJson()).toList()),
        flush: true,
      );

      if (!mounted) return;
      setState(() => _recentPapers = updated);
    } catch (_) {}
  }

  Future<void> _openRecentItem(RecentEPaper item) async {
    try {
      final file = File(item.filePath);
      if (!await file.exists()) {
        await _removeRecentItem(item);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cached file no longer exists.')),
        );
        return;
      }
      final bytes = await file.readAsBytes();
      await _loadPdfData(bytes, item.title, recordHistory: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open recent ePaper: $e')),
      );
    }
  }

  String _formatMeta(RecentEPaper item) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.openedAtMs);
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final mb = (item.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return '${dt.day} ${months[dt.month - 1]} • $hour:$min $ampm • $mb MB';
  }

  void _onTransformChanged() {
    final zoomed = _transformController.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _toggleDoubleTapZoom() {
    if (_isZoomed) {
      _transformController.value = Matrix4.identity();
    } else {
      _transformController.value = Matrix4.identity()..scale(2.8);
    }
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

  Future<void> _loadPdfData(
    Uint8List bytes,
    String title, {
    bool recordHistory = true,
  }) async {
    setState(() => _isLoading = true);
    try {
      _transformController.value = Matrix4.identity();
      _pdfController?.dispose();
      final controller = PdfController(
        document: PdfDocument.openData(bytes),
        initialPage: 1,
      );
      final doc = await controller.document;

      if (recordHistory) {
        await _saveToRecentHistory(bytes, title);
      }

      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
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
    _transformController.value = Matrix4.identity();
    _pdfController?.dispose();
    setState(() {
      _pdfController = null;
      _pdfBytes = null;
      _documentTitle = 'NuzEPpr';
      _pageCount = 0;
      _currentPage = 1;
    });
  }

  void _nextPage() {
    if (_pdfController != null && _currentPage < _pageCount) {
      _transformController.value = Matrix4.identity();
      _pdfController!.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _prevPage() {
    if (_pdfController != null && _currentPage > 1) {
      _transformController.value = Matrix4.identity();
      _pdfController!.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _resetPageFit() {
    if (_pdfController == null || _pdfBytes == null) return;
    _transformController.value = Matrix4.identity();
    final targetPage = _currentPage;
    _pdfController?.dispose();
    final fresh = PdfController(
      document: PdfDocument.openData(_pdfBytes!),
      initialPage: targetPage,
    );
    setState(() {
      _pdfController = fresh;
      _currentPage = targetPage;
      _viewerKey++;
    });
  }

  Widget _buildHomeBody() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.newspaper_rounded, size: 68, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'NuzEPpr',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Press O or tap below to open any downloaded newspaper.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 18),
            Center(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6B1D1D),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open ePaper from Files (O)'),
                onPressed: _pickLocalFile,
              ),
            ),
            if (_recentPapers.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                children: const [
                  Icon(Icons.history_rounded, size: 18, color: Colors.white60),
                  SizedBox(width: 8),
                  Text(
                    'Recent ePapers',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: _recentPapers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _recentPapers[index];
                    return Material(
                      color: const Color(0xFF1F1F1F),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Color(0xFFE06C6C),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          _formatMeta(item),
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove from history',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Colors.white38,
                          ),
                          onPressed: () => _removeRecentItem(item),
                        ),
                        onTap: () => _openRecentItem(item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
              ? _buildHomeBody()
              : RepaintBoundary(
                  key: _captureKey,
                  child: GestureDetector(
                    onDoubleTap: _toggleDoubleTapZoom,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1.0,
                      maxScale: 10.0,
                      panEnabled: _isZoomed,
                      child: PdfView(
                        key: ValueKey('pdf_view_$_viewerKey'),
                        controller: _pdfController!,
                        scrollDirection: Axis.horizontal,
                        pageSnapping: true,
                        physics: _isZoomed
                            ? const NeverScrollableScrollPhysics()
                            : const PageScrollPhysics(),
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
                  ),
                ),
    );
  }
}
