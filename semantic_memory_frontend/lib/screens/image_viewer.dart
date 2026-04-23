import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:semantic_memory_frontend/services/api_service.dart';
import 'package:semantic_memory_frontend/services/fast_search.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class ImageViewer extends StatefulWidget {
  final String path;
  final String heroTag;

  const ImageViewer({
    super.key,
    required this.path,
    this.heroTag = '',
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  bool _isFindingSimilar = false;

  Future<void> _findSimilar() async {
    if (_isFindingSimilar) return;
    setState(() => _isFindingSimilar = true);

    final file = File(widget.path);
    final embedding = await ApiService.embedImage(file);

    if (!mounted) return;

    if (embedding == null) {
      setState(() => _isFindingSimilar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
          content: Row(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: AppColors.pdfRed, size: 18),
              const SizedBox(width: 10),
              Text(
                'Server unreachable — cannot embed image',
                style: GoogleFonts.inter(
                    color: AppColors.textPrimary, fontSize: 13),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final results = await fastSearch(embedding);
    setState(() => _isFindingSimilar = false);

    if (!mounted) return;

    // Filter out the current image from results
    final filtered =
        results.where((r) => r['path'] != widget.path).toList();

    _showSimilarBottomSheet(filtered);
  }

  void _showSimilarBottomSheet(List<Map<String, dynamic>> results) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SimilarImagesSheet(
        results: results,
        onImageTap: (path, heroTag) {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  ImageViewer(path: path, heroTag: heroTag),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 300),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.path.split('/').last;

    return Scaffold(
      backgroundColor: AppColors.neutral,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          fileName,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back,
                color: AppColors.primary, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isFindingSimilar
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Find Similar Images',
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.image_search_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    onPressed: _findSimilar,
                  ),
          ),
        ],
      ),
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 300) {
            Navigator.pop(context);
          }
        },
        child: Center(
          child: widget.heroTag.isNotEmpty
              ? Hero(
                  tag: widget.heroTag,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.file(
                      File(widget.path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return _brokenImagePlaceholder();
                      },
                    ),
                  ),
                )
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    File(widget.path),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return _brokenImagePlaceholder();
                    },
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isFindingSimilar ? null : _findSimilar,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: _isFindingSimilar
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : const Icon(Icons.image_search_rounded, size: 20),
        label: Text(
          _isFindingSimilar ? 'Searching…' : 'Find Similar',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  Widget _brokenImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.broken_image,
            color: AppColors.textHint, size: 64),
        const SizedBox(height: 16),
        Text(
          'Cannot load image',
          style: GoogleFonts.inter(color: AppColors.textHint),
        ),
      ],
    );
  }
}

// ── Bottom sheet widget ────────────────────────────────────────────────────────

class _SimilarImagesSheet extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final void Function(String path, String heroTag) onImageTap;

  const _SimilarImagesSheet({
    required this.results,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── drag handle ──────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── header ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.imgPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.image_search_rounded,
                          color: AppColors.imgPurple, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Similar Images',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            results.isEmpty
                                ? 'No similar images found'
                                : '${results.length} result${results.length == 1 ? '' : 's'} found',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textHint, size: 22),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── results ──────────────────────────────────────────────
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_not_supported_rounded,
                              size: 52,
                              color:
                                  AppColors.textHint.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No visually similar images found',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try indexing more images first',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textHint),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final img = results[i];
                          final heroTag = 'similar_$i';
                          final score = img['score'] as double? ?? 0.0;
                          return GestureDetector(
                            onTap: () =>
                                onImageTap(img['path'] as String, heroTag),
                            child: Hero(
                              tag: heroTag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      File(img['path'] as String),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                        color: AppColors.surfaceLight,
                                        child: const Center(
                                          child: Icon(Icons.broken_image,
                                              color: AppColors.textHint),
                                        ),
                                      ),
                                    ),
                                    // similarity score badge
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                    // filename gradient
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                            6, 18, 6, 6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black
                                                  .withValues(alpha: 0.65),
                                            ],
                                          ),
                                        ),
                                        child: Text(
                                          (img['path'] as String)
                                              .split('/')
                                              .last,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            color: Colors.white,
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
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
