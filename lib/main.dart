import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  runApp(const EPaperReaderApp());
}

class EPaperReaderApp extends StatelessWidget {
  const EPaperReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dedicated E-Paper Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueGrey,
      ),
      home: const EPaperHomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// DATA MODELS
// ---------------------------------------------------------------------------
class ArticleBlock {
  final String id;
  final Rect bounds;
  final String headline;
  final double headlineFontSize;
  final String bodyText;

  ArticleBlock({
    required this.id,
    required this.bounds,
    required this.headline,
    required this.headlineFontSize,
    required this.bodyText,
  });
}

class EPaperPageData {
  final int pageNumber;
  final String pageTitle;
  final List<ArticleBlock> articles;

  EPaperPageData({
    required this.pageNumber,
    required this.pageTitle,
    required this.articles,
  });
}

// ---------------------------------------------------------------------------
// MAIN READER SCREEN (Handles Gestures, Paging, Audio, & File Ingestion)
// ---------------------------------------------------------------------------
class EPaperHomeScreen extends StatefulWidget {
  const EPaperHomeScreen({super.key});

  @override
  State<EPaperHomeScreen> createState() => _EPaperHomeScreenState();
}

class _EPaperHomeScreenState extends State<EPaperHomeScreen> {
  final PageController _pageController = PageController();
  final TransformationController _zoomController = TransformationController();
  final FlutterTts _tts = FlutterTts();

  int _currentPageIndex = 0;
  bool _isPlayingAudio = false;
  String? _openedFilePath;

  // Mock e-paper edition: Two pages with multiple multi-column stories
  final List<EPaperPageData> _editionPages = [
    EPaperPageData(
      pageNumber: 1,
      pageTitle: 'Front Page - Daily Chronicle',
      articles: [
        ArticleBlock(
          id: 'lead_story',
          bounds: const Rect.fromLTWH(20, 40, 360, 220),
          headline: 'GLOBAL CLIMATE ACCORD SIGNED IN GENEVA',
          headlineFontSize: 28.0,
          bodyText:
              'Delegates from over 140 nations finalized a binding agreement late last night. '
              'The treaty mandates accelerated reductions in industrial emissions over the next decade. '
              'Economic ministers signaled broad support despite lingering debate over financing mechanisms.',
        ),
        ArticleBlock(
          id: 'secondary_story',
          bounds: const Rect.fromLTWH(20, 280, 170, 260),
          headline: 'Tech Markets Rebound After Quarter Lull',
          headlineFontSize: 18.0,
          bodyText:
              'Hardware and chip stocks led a midday rally, reversing losses accumulated '
              'over recent weeks. Analysts credit renewed enterprise spending and steady supply chains.',
        ),
        ArticleBlock(
          id: 'metro_brief',
          bounds: const Rect.fromLTWH(200, 280, 180, 260),
          headline: 'City Metro Phase 3 Begins Tunneling',
          headlineFontSize: 14.0,
          bodyText:
              'Boring machines broke ground on the northern transit corridor this morning. '
              'Commuters can expect temporary diversions along Main Street through late autumn.',
        ),
      ],
    ),
    EPaperPageData(
      pageNumber: 2,
      pageTitle: 'Business & Economy - Page 2',
      articles: [
        ArticleBlock(
          id: 'biz_lead',
          bounds: const Rect.fromLTWH(20, 40, 360, 200),
          headline: 'CENTRAL BANK HOLDS BENCHMARK RATES STEADY',
          headlineFontSize: 24.0,
          bodyText:
              'Citing balanced employment figures and cooling core inflation, the monetary council '
              'decided against rate adjustments for the third straight quarter.',
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _setupShareIntentListeners();
  }

  void _initTts() {
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);
  }

  void _setupShareIntentListeners() {
    // 1. For sharing while the app is running in memory
    ReceiveSharingIntent.getMediaStream().listen((sharedFiles) {
      if (sharedFiles.isNotEmpty) {
        _handleIncomingFile(sharedFiles.first.path);
      }
    });

    // 2. For sharing when the app was closed
    ReceiveSharingIntent.getInitialMedia().then((sharedFiles) {
      if (sharedFiles.isNotEmpty) {
        _handleIncomingFile(sharedFiles.first.path);
      }
    });
  }

  void _handleIncomingFile(String path) {
    if (path.toLowerCase().endsWith('.pdf')) {
      setState(() {
        _openedFilePath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-Paper loaded: ${path.split("/").last}')),
      );
    }
  }

  void _zoomInOnArticle(ArticleBlock article) {
    if (_zoomController.value != Matrix4.identity()) {
      _zoomController.value = Matrix4.identity();
      return;
    }

    final matrix = Matrix4.identity()
      ..translate(-article.bounds.left * 1.5, -article.bounds.top * 1.5)
      ..scale(2.2);

    setState(() {
      _zoomController.value = matrix;
    });
  }

  void _reflowArticle(ArticleBlock article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  article.headline,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif',
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ARTICLE REFLOW MODE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Divider(height: 32),
                Text(
                  article.bodyText,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.65,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleHierarchicalReading() async {
    if (_isPlayingAudio) {
      await _tts.stop();
      setState(() => _isPlayingAudio = false);
      return;
    }

    setState(() => _isPlayingAudio = true);

    final currentPage = _editionPages[_currentPageIndex];
    final sortedArticles = List<ArticleBlock>.from(currentPage.articles)
      ..sort((a, b) => b.headlineFontSize.compareTo(a.headlineFontSize));

    for (final article in sortedArticles) {
      if (!_isPlayingAudio) break;

      await _tts.speak('Headline: ${article.headline}');
      await _tts.awaitSpeakCompletion(true);

      if (!_isPlayingAudio) break;

      await _tts.speak(article.bodyText);
      await _tts.awaitSpeakCompletion(true);

      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (mounted) {
      setState(() => _isPlayingAudio = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _zoomController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = _editionPages[_currentPageIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _openedFilePath != null
                  ? _openedFilePath!.split(Platform.pathSeparator).last
                  : currentPage.pageTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Page ${_currentPageIndex + 1} of ${_editionPages.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Audible Overview',
            icon: Icon(
              _isPlayingAudio ? Icons.stop_circle : Icons.volume_up_rounded,
              color: _isPlayingAudio ? Colors.red : Colors.black87,
              size: 28,
            ),
            onPressed: _toggleHierarchicalReading,
          ),
          IconButton(
            tooltip: 'Reset Zoom',
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () {
              _zoomController.value = Matrix4.identity();
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _editionPages.length,
        onPageChanged: (idx) {
          setState(() {
            _currentPageIndex = idx;
            _zoomController.value = Matrix4.identity();
          });
          if (_isPlayingAudio) {
            _tts.stop();
            setState(() => _isPlayingAudio = false);
          }
        },
        itemBuilder: (context, index) {
          final pageData = _editionPages[index];

          return Center(
            child: InteractiveViewer(
              transformationController: _zoomController,
              minScale: 1.0,
              maxScale: 4.0,
              child: AspectRatio(
                aspectRatio: 1 / 1.414,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ...pageData.articles.map((article) {
                        return Positioned(
                          left: article.bounds.left,
                          top: article.bounds.top,
                          width: article.bounds.width,
                          height: article.bounds.height,
                          child: GestureDetector(
                            onDoubleTap: () => _zoomInOnArticle(article),
                            onLongPress: () => _reflowArticle(article),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                color: Colors.grey.shade50,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    article.headline,
                                    style: TextStyle(
                                      fontSize: article.headlineFontSize / 1.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Serif',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: Text(
                                      article.bodyText,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        height: 1.3,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.fade,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
