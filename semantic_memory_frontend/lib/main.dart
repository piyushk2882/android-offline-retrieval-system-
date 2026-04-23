import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:semantic_memory_frontend/screens/document_viewer.dart';
import 'package:semantic_memory_frontend/screens/documents_screen.dart';
import 'package:semantic_memory_frontend/screens/image_viewer.dart';
import 'package:semantic_memory_frontend/screens/images_screen.dart';
import 'package:semantic_memory_frontend/screens/splash_screen.dart';
import 'package:semantic_memory_frontend/services/api_service.dart';
import 'package:semantic_memory_frontend/services/fast_search.dart';
import 'package:semantic_memory_frontend/services/voice_service.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:home_widget/home_widget.dart';
import 'package:semantic_memory_frontend/screens/assistant_overlay_screen.dart';
import 'services/media_scanner.dart';
import 'services/permission_service.dart';
import 'services/indexing_service.dart';
import 'services/document_indexing_service.dart';
import 'database/database_helper.dart';
import 'services/index_loader.dart';
import 'services/camera_service.dart';
import 'services/query_processor.dart';

// ── Intent Detection ──────────────────────────────────────────────
class QueryIntent {
  bool isImage = false;
  bool isDocument = false;

  QueryIntent(String query) {
    if (query.contains("image") ||
        query.contains("photo") ||
        query.contains("picture")) {
      isImage = true;
    }

    if (query.contains("pdf") ||
        query.contains("notes") ||
        query.contains("document") ||
        query.contains("ppt") ||
        query.contains("question")) {
      isDocument = true;
    }
  }
}

// ── Year Filter ────────────────────────────────────────────────────
List filterByYear(List results, int year) {
  return results.where((item) {
    final file = File(item["path"] as String);
    final modified = file.lastModifiedSync();
    return modified.year == year;
  }).toList();
}

/// Extracts the first 4-digit year (1900-2099) found in [query], or null.
int? extractYear(String query) {
  final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(query);
  if (match == null) return null;
  return int.tryParse(match.group(0)!);
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool launchedFromWidget = false;
  try {
    var uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (uri != null) {
      launchedFromWidget = true;
    }
  } catch (e) {
    print("HomeWidget Error: $e");
  }

  runApp(MyApp(launchedFromWidget: launchedFromWidget));
}

class MyApp extends StatelessWidget {
  final bool launchedFromWidget;
  const MyApp({super.key, this.launchedFromWidget = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MemoryLens',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme().copyWith(
        scaffoldBackgroundColor: launchedFromWidget ? Colors.transparent : null,
      ),
      home: launchedFromWidget ? const AssistantOverlayScreen() : const SplashScreen(),
    );
  }
}


class HomeScreen extends StatefulWidget {
  final String? initialQuery;
  const HomeScreen({super.key, this.initialQuery});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<File> files = [];
  List imageSearchResults = [];
  List documentSearchResults = [];
  String _searchFilter = "all"; // "all", "documents", "images"
  bool _isSearching = false;
  bool _searchedOnce = false;
  // True once the first batch of vectors is loaded into memory
  bool _indexReady = false;
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _typewriterController;
  late Animation<int> _typewriterAnimation;
  final String _typewriterText = "What can I find for you?";

  // Indexing progress
  int _indexingProgress = 0;
  int _indexingTotal = 0;
  bool get _isIndexing => _indexingTotal > 0 && _indexingProgress < _indexingTotal;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _typewriterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _typewriterAnimation = IntTween(begin: 0, end: _typewriterText.length)
        .animate(
          CurvedAnimation(parent: _typewriterController, curve: Curves.linear),
        );
    _typewriterController.forward();
    startup();

    if (widget.initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handleSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _typewriterController.dispose();
    _searchController.dispose();
    super.dispose();
  }



  void showAssistantPopup() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAssistantPopup(),
    );

    String? query = await VoiceService.listen();
    if (context.mounted) {
      Navigator.pop(context);
    }
    
    if (query != null && query.trim().isNotEmpty) {
      handleSearch(query);
    }
  }

  Widget _buildAssistantPopup() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, child) => Transform.scale(
              scale: _pulseAnimation.value,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 48, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Listening...",
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> scanImages() async {
    bool permission = await PermissionService.requestPermission();
    if (!permission) return;

    var images = await MediaScanner.getImages();
    List<File> imageFiles = [];
    for (var img in images) {
      final file = await img.file;
      if (file != null) imageFiles.add(file);
    }

    setState(() {
      files = imageFiles;
    });

    if (files.isNotEmpty) {
      await startIndexing(
        files,
        onProgress: (indexed, total) {
          setState(() {
            _indexingProgress = indexed;
            _indexingTotal = total;
          });
        },
      );
      // Mark complete
      setState(() {
        _indexingProgress = _indexingTotal;
      });
    }

    var rows = await DatabaseHelper.instance.getAllEmbeddings();
    print("Total indexed images: ${rows.length}");
  }

  Future<void> startup() async {
    // ── Phase 1: load vectors in background (non-blocking) ──────────────
    // Search via DB keyword fallback is available immediately.
    // Vector search unlocks as soon as the first batch is in memory.
    loadIndex(
      onEarlyReady: () {
        if (mounted) setState(() => _indexReady = true);
      },
    ).then((_) {
      if (mounted) setState(() => _indexReady = true);
    });

    // ── Phase 2: scan + index new files (images & docs in parallel) ──────
    final storageGranted = await PermissionService.requestStoragePermission();

    await Future.wait([
      scanImages(),
      if (storageGranted)
        startDocumentIndexing()
      else
        Future(() =>
            print("[Document] Storage permission denied — skipping doc scan")),
    ]);
  }

  // ── Smart Search Pipeline ─────────────────────────────────────
  Future<void> handleSearch(String rawQuery) async {
    if (rawQuery.trim().isEmpty) return;

    String query = processQuery(rawQuery);
    print("Processed Query: $query");

    setState(() {
      _isSearching = true;
      _searchedOnce = true;
      _searchController.text = rawQuery;
    });

    var intent = QueryIntent(query);

    List imageResults = [];
    List docResults = [];

    // Respect manual filter chips; otherwise use intent to skip irrelevant searches
    final bool skipImages =
        _searchFilter == "documents" || intent.isDocument && !intent.isImage;
    final bool skipDocs =
        _searchFilter == "images" || intent.isImage && !intent.isDocument;

    if (_indexReady) {
      // ── Full vector search ──────────────────────────────────────
      if (!skipImages) {
        var clipEmbedding = await ApiService.embedText(query);
        if (clipEmbedding != null) {
          imageResults = await fastSearch(clipEmbedding);
        }
      }
      if (!skipDocs) {
        var docEmbedding = await ApiService.embedTextDoc(query);
        if (docEmbedding != null) {
          docResults = searchDocuments(docEmbedding, query);
        }
      }
    } else {
      // ── DB keyword fallback (index still loading) ───────────────
      print("[Search] Vector index not ready — using keyword fallback");
      if (!skipDocs) {
        docResults =
            await DatabaseHelper.instance.searchDocumentsByKeyword(query);
      }
      if (!skipImages) {
        imageResults =
            await DatabaseHelper.instance.searchImagesByPath(query);
      }
    }

    // Apply dynamic year filter if a year is mentioned in the query
    final int? year = extractYear(query);
    if (year != null) {
      imageResults = filterByYear(imageResults, year);
      docResults = filterByYear(docResults, year);
    }

    setState(() {
      imageSearchResults = imageResults;
      documentSearchResults = docResults;
      _isSearching = false;
    });
  }

  // Keep _performSearch as an alias so onSubmitted still works
  Future<void> _performSearch(String query) => handleSearch(query);

  IconData _getDocIcon(String path) {
    String p = path.toLowerCase();
    if (p.endsWith(".pdf")) return Icons.picture_as_pdf;
    if (p.endsWith(".pptx") || p.endsWith(".ppt")) return Icons.slideshow;
    if (p.endsWith(".docx") || p.endsWith(".doc")) return Icons.description;
    if (p.endsWith(".txt")) return Icons.article;
    if (p.endsWith(".jpg") ||
        p.endsWith(".jpeg") ||
        p.endsWith(".png") ||
        p.endsWith(".gif") ||
        p.endsWith(".webp")) {
      return Icons.image;
    }
    return Icons.insert_drive_file;
  }

  Color _getDocIconColor(String path) {
    String p = path.toLowerCase();
    if (p.endsWith(".pdf")) return AppColors.pdfRed;
    if (p.endsWith(".pptx") || p.endsWith(".ppt")) return AppColors.pptOrange;
    if (p.endsWith(".docx") || p.endsWith(".doc")) return AppColors.docBlue;
    if (p.endsWith(".txt")) return AppColors.txtGreen;
    if (p.endsWith(".jpg") ||
        p.endsWith(".jpeg") ||
        p.endsWith(".png") ||
        p.endsWith(".gif") ||
        p.endsWith(".webp")) {
      return AppColors.imgPurple;
    }
    return AppColors.tertiary;
  }

  bool get _hasResults =>
      imageSearchResults.isNotEmpty || documentSearchResults.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom Header ────────────────────────────────────
            _buildHeader(),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: <Widget>[
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: _searchedOnce
                    ? _buildTopSearchLayout(key: const ValueKey('topView'))
                    : _buildCenteredSearchLayout(
                        key: const ValueKey('centeredView'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSearchLayout({Key? key}) {
    return Column(
      key: key,
      children: [
        const SizedBox(height: 12),
        _buildSearchBar(),
        if (_isIndexing) _buildIndexingProgressBar(),
        if (!_indexReady) _buildIndexLoadingBanner(),
        const SizedBox(height: 6),
        _buildFilterChips(),
        const SizedBox(height: 4),
        Expanded(
          child: _isSearching
              ? _buildSearchingIndicator()
              : _hasResults
              ? _buildSearchResults()
              : _buildNoResults(),
        ),
      ],
    );
  }

  Widget _buildCenteredSearchLayout({Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting + typewriter ─────────────────────────────
          AnimatedBuilder(
            animation: _typewriterAnimation,
            builder: (context, child) {
              return Text(
                _typewriterText.substring(0, _typewriterAnimation.value),
                textAlign: TextAlign.start,
                style: GoogleFonts.inter(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Search across all your indexed content',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 20),

          // ── Global search bar (docs + images) ─────────────────
          _buildSearchBar(),
          if (!_indexReady) _buildIndexLoadingBanner(),
          if (_isIndexing)
            _buildIndexingProgressBar()
          else if (files.isEmpty)
            _buildScanningIndicator(),

          const SizedBox(height: 28),

          // ── Section label ─────────────────────────────────────
          Text(
            'Browse',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textHint,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),

          // ── Documents block ───────────────────────────────────
          _buildSectionBlock(
            title: 'Documents',
            subtitle: 'PDFs, slides, notes & more',
            icon: Icons.description_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            accentColor: AppColors.docBlue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DocumentsScreen()),
            ),
            badgeIcon: Icons.picture_as_pdf,
            extras: [
              _miniTypeBadge('PDF', AppColors.pdfRed),
              const SizedBox(width: 6),
              _miniTypeBadge('PPT', AppColors.pptOrange),
              const SizedBox(width: 6),
              _miniTypeBadge('DOC', AppColors.docBlue),
              const SizedBox(width: 6),
              _miniTypeBadge('TXT', AppColors.txtGreen),
            ],
          ),

          const SizedBox(height: 14),

          // ── Images block ──────────────────────────────────────
          _buildSectionBlock(
            title: 'Images',
            subtitle: 'Photos, screenshots & artwork',
            icon: Icons.image_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            accentColor: AppColors.imgPurple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImagesScreen()),
            ),
            badgeIcon: Icons.photo_library_rounded,
            extras: [
              _miniTypeBadge('JPG', AppColors.imgPurple),
              const SizedBox(width: 6),
              _miniTypeBadge('PNG', const Color(0xFF7C4DFF)),
              const SizedBox(width: 6),
              _miniTypeBadge('GIF', const Color(0xFF26C6DA)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBlock({
    required String title,
    required String subtitle,
    required IconData icon,
    required LinearGradient gradient,
    required Color accentColor,
    required VoidCallback onTap,
    required IconData badgeIcon,
    List<Widget> extras = const [],
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Left accent icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),

                // Title + badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                      if (extras.isNotEmpty) ...[  
                        const SizedBox(height: 10),
                        Row(children: extras),
                      ],
                    ],
                  ),
                ),

                // Chevron
                Icon(
                  Icons.chevron_right_rounded,
                  color: accentColor.withValues(alpha: 0.7),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniTypeBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.tertiary.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Branding icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('lib/assets/logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Semantic Memory",
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Search your files intelligently",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Camera button
          _buildIconButton(
            icon: Icons.camera_alt_rounded,
            onPressed: () async {
              var image = await CameraService.captureImage();
              if (image == null) return;
              setState(() => _isSearching = true);
              var imageEmbedding = await ApiService.embedImage(image);
              var imageResults = imageEmbedding != null
                  ? await fastSearch(imageEmbedding)
                  : [];
              setState(() {
                imageSearchResults = imageResults;
                documentSearchResults = [];
                _isSearching = false;
                _searchedOnce = true; // switch to results layout
              });
              _searchController.text = "📷 Image search results";
            },
          ),

          IconButton(
            icon: const Icon(Icons.mic),
            onPressed: () async {
              final String? text = await VoiceService.listen();
              if (text == null || text.trim().isEmpty) return;
              print("Voice Query: $text");
              await handleSearch(text);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 22),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SEARCH BAR
  // ══════════════════════════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: "Search images, docs, notes…",
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search_rounded, size: 22),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.tertiary,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      imageSearchResults = [];
                      documentSearchResults = [];
                      _searchedOnce = false; // Reset to center
                    });
                  },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}), // refresh suffix icon
        onSubmitted: _performSearch,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  FILTER CHIPS
  // ══════════════════════════════════════════════════════════════
  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _filterChip("All", "all", Icons.layers_rounded),
          const SizedBox(width: 8),
          _filterChip("Docs", "documents", Icons.description_rounded),
          const SizedBox(width: 8),
          _filterChip("Images", "images", Icons.image_rounded),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, IconData icon) {
    final isActive = _searchFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _searchFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.tertiary.withValues(alpha: 0.15),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SEARCHING INDICATOR
  // ══════════════════════════════════════════════════════════════
  Widget _buildSearchingIndicator() {
    return Center(
      key: const ValueKey('searching'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Searching your memory…",
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexingProgressBar() {
    final double frac = _indexingTotal > 0
        ? (_indexingProgress / _indexingTotal).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Indexing images… $_indexingProgress / $_indexingTotal",
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// Subtle banner shown while the in-memory vector index is still loading.
  Widget _buildIndexLoadingBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedOpacity(
        opacity: _indexReady ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 600),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Building vector index… keyword search active",
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Column(
      key: const ValueKey('scanning'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, child) =>
              Opacity(opacity: _pulseAnimation.value, child: child),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: AppColors.primary,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Scanning & indexing your media…",
          style: GoogleFonts.inter(
            fontSize: 15,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "This happens once in the background",
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.textHint),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SEARCH RESULTS
  // ══════════════════════════════════════════════════════════════
  Widget _buildSearchResults() {
    return ListView(
      key: const ValueKey('results'),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        // ── Documents ──────────────────────────────────────────
        if (_searchFilter != "images" && documentSearchResults.isNotEmpty) ...[
          _sectionHeader(
            "Documents",
            Icons.description_rounded,
            documentSearchResults.length,
          ),
          ...documentSearchResults.map((doc) => _buildDocCard(doc)),
          const SizedBox(height: 8),
        ],

        // ── Images ─────────────────────────────────────────────
        if (_searchFilter != "documents" && imageSearchResults.isNotEmpty) ...[
          _sectionHeader(
            "Images",
            Icons.image_rounded,
            imageSearchResults.length,
          ),
          _buildImageGrid(),
        ],

        // ── No results for the active filter ───────────────────
        if ((_searchFilter == "documents" && documentSearchResults.isEmpty) ||
            (_searchFilter == "images" && imageSearchResults.isEmpty))
          _buildNoResults(),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$count",
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocCard(dynamic doc) {
    final path = doc["path"] as String;
    final chunk = doc["chunk"] as String;
    final fileName = path.split("/").last;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFile(path, chunk),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File type icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _getDocIconColor(path).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getDocIcon(path),
                  color: _getDocIconColor(path),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chunk,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: imageSearchResults.length,
      itemBuilder: (context, index) {
        final img = imageSearchResults[index];
        final heroTag = "img_$index";

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) =>
                    ImageViewer(path: img["path"], heroTag: heroTag),
                transitionsBuilder: (_, anim, __, child) {
                  return FadeTransition(opacity: anim, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
          },
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(img["path"]),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppColors.surfaceLight,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image, color: AppColors.textHint),
                      );
                    },
                  ),
                  // Bottom gradient overlay for filename
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.neutral.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                      child: Text(
                        (img["path"] as String).split("/").last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textHint.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              "No results found",
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Try adjusting your search or filter",
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ══════════════════════════════════════════════════════════════

  void _openFile(String path, String highlightText) {
    if (path.toLowerCase().endsWith(".pdf")) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentViewer(path: path, highlightText: highlightText),
        ),
      );
    } else if (_isImageFile(path)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewer(path: path)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                "Viewer for this file type is not available yet.",
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
  }

  bool _isImageFile(String path) {
    final p = path.toLowerCase();
    return p.endsWith(".jpg") ||
        p.endsWith(".jpeg") ||
        p.endsWith(".png") ||
        p.endsWith(".gif") ||
        p.endsWith(".webp");
  }
}
