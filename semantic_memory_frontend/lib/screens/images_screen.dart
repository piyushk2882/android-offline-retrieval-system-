import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:semantic_memory_frontend/database/database_helper.dart';
import 'package:semantic_memory_frontend/screens/image_viewer.dart';
import 'package:semantic_memory_frontend/services/api_service.dart';
import 'package:semantic_memory_frontend/services/fast_search.dart';
import 'package:semantic_memory_frontend/services/index_loader.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class ImagesScreen extends StatefulWidget {
  const ImagesScreen({super.key});

  @override
  State<ImagesScreen> createState() => _ImagesScreenState();
}

class _ImagesScreenState extends State<ImagesScreen> {
  final TextEditingController _searchController = TextEditingController();

  // All indexed image paths
  List<Map<String, dynamic>> _allImages = [];

  // Text search results (null = not searched)
  List<Map<String, dynamic>>? _searchResults;

  // Image-to-image search state
  String? _queryImagePath;     // path of the image used as query
  bool _isImageSearching = false;

  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadAllImages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllImages() async {
    setState(() => _isLoading = true);
    // Lean query: only fetches file_path column, never the embedding blobs.
    // Prevents OOM when 3270+ image vectors are in the DB.
    final paths = await DatabaseHelper.instance.getAllImagePaths();
    setState(() {
      _allImages = paths.map((p) => {'path': p}).toList();
      _isLoading = false;
    });
  }

  Future<void> _performSearch(String rawQuery) async {
    if (rawQuery.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    setState(() => _isSearching = true);

    List<Map<String, dynamic>> results = [];
    bool usedKeywordFallback = false;

    if (globalIndex.vectors.isNotEmpty) {
      // Try vector search first
      final embedding = await ApiService.embedText(rawQuery);
      if (embedding != null) {
        final raw = await fastSearch(embedding);
        results = raw.cast<Map<String, dynamic>>();
      } else {
        // Embedding failed (connection abort / timeout) — fall back to keyword
        usedKeywordFallback = true;
        final raw =
            await DatabaseHelper.instance.searchImagesByPath(rawQuery);
        results = raw.cast<Map<String, dynamic>>();
      }
    } else {
      // Index not ready — keyword search only
      usedKeywordFallback = true;
      final raw =
          await DatabaseHelper.instance.searchImagesByPath(rawQuery);
      results = raw.cast<Map<String, dynamic>>();
    }

    setState(() {
      _searchResults = results;
      _isSearching = false;
    });

    if (usedKeywordFallback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.primary, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text('Server unreachable — showing keyword results'),
              ),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _displayedImages =>
      _searchResults ?? _allImages;

  // ── Image-to-image search ─────────────────────────────────────────────────
  Future<void> _searchByImage(Map<String, dynamic> img) async {
    final path = img['path'] as String;
    setState(() {
      _isImageSearching = true;
      _queryImagePath = path;
      _searchResults = null;        // clear any text search first
      _searchController.clear();
    });

    List<Map<String, dynamic>> results = [];
    bool failed = false;

    if (globalIndex.vectors.isNotEmpty) {
      final embedding = await ApiService.embedImage(File(path));
      if (embedding != null) {
        final raw = await fastSearch(embedding);
        // Exclude the query image itself
        results = raw
            .cast<Map<String, dynamic>>()
            .where((r) => r['path'] != path)
            .toList();
      } else {
        failed = true;
      }
    } else {
      failed = true;
    }

    setState(() {
      _searchResults = results;
      _isImageSearching = false;
    });

    if (failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off_rounded,
                  color: AppColors.primary, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Server unreachable or index not ready — cannot search by image'),
              ),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _clearImageSearch() {
    setState(() {
      _queryImagePath = null;
      _searchResults = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildSearchBar(),
            const SizedBox(height: 8),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final bool inImageSearch = _queryImagePath != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.tertiary.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              inImageSearch ? Icons.close_rounded : Icons.arrow_back_rounded,
              color: AppColors.primary,
            ),
            onPressed:
                inImageSearch ? _clearImageSearch : () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (inImageSearch ? AppColors.primary : AppColors.imgPurple)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              inImageSearch ? Icons.image_search_rounded : Icons.image_rounded,
              color:
                  inImageSearch ? AppColors.primary : AppColors.imgPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inImageSearch ? 'Similar Images' : 'Images',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  inImageSearch
                      ? 'Results for: ${_queryImagePath!.split('/').last}'
                      : '${_allImages.length} indexed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search images…',
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 8),
            child: Icon(Icons.search_rounded, size: 22),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.tertiary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchResults = null);
                  },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: _performSearch,
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_isSearching || _isImageSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              _isImageSearching
                  ? 'Finding similar images…'
                  : 'Searching images…',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    final imgs = _displayedImages;
    if (imgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_rounded,
                size: 56,
                color: AppColors.textHint.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _searchResults != null
                  ? 'No images found'
                  : 'No images indexed yet',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              _searchResults != null
                  ? 'Try a different search term'
                  : 'Images will appear here once indexed',
              style: GoogleFonts.inter(
                  color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final bool inImageSearch = _queryImagePath != null;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: imgs.length,
      itemBuilder: (_, i) {
        final img = imgs[i];
        final heroTag = 'imgs_screen_$i';
        final score = img['score'] as double?;
        return GestureDetector(
          // Short tap: if in gallery mode → image-to-image search;
          //            if already showing similar results → open viewer
          onTap: () {
            if (inImageSearch) {
              // In results mode: open full viewer
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      ImageViewer(path: img['path'], heroTag: heroTag),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            } else {
              // In gallery mode: find similar images
              _searchByImage(img);
            }
          },
          // Long press: always open the full viewer
          onLongPress: () => Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  ImageViewer(path: img['path'], heroTag: heroTag),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 300),
            ),
          ),
          child: Hero(
            tag: heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(img['path']),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surfaceLight,
                      child: const Center(
                        child: Icon(Icons.broken_image,
                            color: AppColors.textHint),
                      ),
                    ),
                  ),
                  // Similarity score badge (shown only in image-search results)
                  if (score != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(score * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  // "Find similar" hint icon (gallery mode only)
                  if (!inImageSearch)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.image_search_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
                        (img['path'] as String).split('/').last,
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
}
