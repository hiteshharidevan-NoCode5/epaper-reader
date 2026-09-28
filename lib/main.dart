import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const EPaperReaderApp());
}

class EPaperReaderApp extends StatefulWidget {
  const EPaperReaderApp({super.key});

  @override
  State<EPaperReaderApp> createState() => _EPaperReaderAppState();
}

class _EPaperReaderAppState extends State<EPaperReaderApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Paper Reader',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFBF8F1),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEFE9DA),
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2C2C2C),
          foregroundColor: Colors.white70,
          elevation: 0,
        ),
      ),
      home: ReaderHomeScreen(onToggleTheme: toggleTheme),
    );
  }
}

class NewspaperEdition {
  final String title;
  final String date;
  final List<ArticleItem> articles;

  NewspaperEdition({
    required this.title,
    required this.date,
    required this.articles,
  });
}

class ArticleItem {
  final String headline;
  final String category;
  final String bodyText;
  final double headlineFontSize;

  ArticleItem({
    required this.headline,
    required this.category,
    required this.bodyText,
    this.headlineFontSize = 26.0,
  });
}

class ReaderHomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const ReaderHomeScreen({super.key, required this.onToggleTheme});

  @override
  State<ReaderHomeScreen> createState() => _ReaderHomeScreenState();
}

class _ReaderHomeScreenState extends State<ReaderHomeScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _isPlaying = false;
  double _fontSize = 18.0;

  final List<NewspaperEdition> _editions = [
    NewspaperEdition(
      title: 'Daily Chronicle - Morning Edition',
      date: 'September 28, 2026',
      articles: [
        ArticleItem(
          headline: 'Clean Energy Grid Reaches New Output Peak Across Region',
          category: 'INFRASTRUCTURE',
          headlineFontSize: 28.0,
          bodyText:
              'Grid operators recorded historical transmission volumes this morning as regional solar arrays and wind corridors supplied over seventy-eight percent of peak municipal consumption. Regional planners emphasized steady base-load performance alongside continued integration of high-density battery storage nodes.',
        ),
        ArticleItem(
          headline: 'Central Bank Concludes Quarterly Session on Steady Policy',
          category: 'FINANCE',
          headlineFontSize: 24.0,
          bodyText:
              'Citing balanced employment figures and cooling core inflation, the monetary council decided against rate adjustments for the third straight quarter.',
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);
  }

  Future<void> _speakText(String text) async {
    if (_isPlaying) {
      await _tts.stop();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      _tts.setCompletionHandler(() {
        setState(() => _isPlaying = false);
      });
      await _tts.speak(text);
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _showAddArticleDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Article / Notes'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Headline'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bodyController,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Body Text / Article Content'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty && bodyController.text.isNotEmpty) {
                setState(() {
                  _editions.first.articles.insert(
                    0,
                    ArticleItem(
                      headline: titleController.text,
                      category: 'CUSTOM',
                      bodyText: bodyController.text,
                    ),
                  );
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final edition = _editions.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          edition.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            tooltip: 'Increase Font Size',
            onPressed: () {
              setState(() {
                _fontSize = _fontSize >= 26.0 ? 16.0 : _fontSize + 2.0;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.brightness_medium),
            tooltip: 'Toggle Day/Night Mode',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Add Custom Article',
            onPressed: _showAddArticleDialog,
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        itemCount: edition.articles.length,
        separatorBuilder: (context, index) => const Divider(thickness: 1.5, height: 32),
        itemBuilder: (context, index) {
          final article = edition.articles[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  article.category,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.headline,
                style: TextStyle(
                  fontSize: article.headlineFontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'serif',
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                article.bodyText,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: 1.6,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _speakText('${article.headline}. ${article.bodyText}'),
                    icon: Icon(_isPlaying ? Icons.stop_circle : Icons.volume_up),
                    label: Text(_isPlaying ? 'Stop Reading' : 'Listen'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
