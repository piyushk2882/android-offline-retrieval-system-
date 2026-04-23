import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:semantic_memory_frontend/database/database_helper.dart';
import 'package:semantic_memory_frontend/screens/document_viewer.dart';
import 'package:semantic_memory_frontend/services/api_service.dart';
import 'package:semantic_memory_frontend/services/document_vector_index.dart';
import 'package:semantic_memory_frontend/services/fast_search.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final TextEditingController _searchController = TextEditingController();

  // All indexed document paths (deduplicated)
  List<Map<String, dynamic>> _allDocuments = [];

  // Search result list (null = not searched yet)
  List<Map<String, dynamic>>? _searchResults;

  bool _isLoading = true;
  bool _isSearching = false;

  // Group filter: all, pdf, pptx, docx, txt
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAllDocuments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllDocuments() async {
    setState(() => _isLoading = true);
    // Lean query: only fetches file_path + first chunk_text per document.
    // Never loads embedding columns — prevents OOM with 38k+ chunks.
    final docs = await DatabaseHelper.instance.getDistinctDocumentPaths();
    setState(() {
      _allDocuments = docs;
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

    if (globalDocumentIndex.vectors.isNotEmpty) {
      // Try vector search first
      final embedding = await ApiService.embedTextDoc(rawQuery);
      if (embedding != null) {
        final raw = searchDocuments(embedding, rawQuery);
        results = raw.cast<Map<String, dynamic>>();
      } else {
        // Embedding failed (connection abort / timeout) — fall back to keyword
        usedKeywordFallback = true;
        final raw =
            await DatabaseHelper.instance.searchDocumentsByKeyword(rawQuery);
        results = raw.cast<Map<String, dynamic>>();
      }
    } else {
      // Index not ready — keyword search only
      usedKeywordFallback = true;
      final raw =
          await DatabaseHelper.instance.searchDocumentsByKeyword(rawQuery);
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

  List<Map<String, dynamic>> get _displayedDocs {
    final source = _searchResults ?? _allDocuments;
    if (_typeFilter == 'all') return source;
    return source.where((d) {
      final p = (d['path'] as String).toLowerCase();
      switch (_typeFilter) {
        case 'pdf':
          return p.endsWith('.pdf');
        case 'pptx':
          return p.endsWith('.pptx') || p.endsWith('.ppt');
        case 'docx':
          return p.endsWith('.docx') || p.endsWith('.doc');
        case 'txt':
          return p.endsWith('.txt');
        default:
          return true;
      }
    }).toList();
  }

  IconData _getDocIcon(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (p.endsWith('.pptx') || p.endsWith('.ppt')) return Icons.slideshow;
    if (p.endsWith('.docx') || p.endsWith('.doc')) return Icons.description;
    if (p.endsWith('.txt')) return Icons.article;
    return Icons.insert_drive_file;
  }

  Color _getDocIconColor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.pdf')) return AppColors.pdfRed;
    if (p.endsWith('.pptx') || p.endsWith('.ppt')) return AppColors.pptOrange;
    if (p.endsWith('.docx') || p.endsWith('.doc')) return AppColors.docBlue;
    if (p.endsWith('.txt')) return AppColors.txtGreen;
    return AppColors.tertiary;
  }

  String _docTypeLabel(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.pdf')) return 'PDF';
    if (p.endsWith('.pptx') || p.endsWith('.ppt')) return 'PPT';
    if (p.endsWith('.docx') || p.endsWith('.doc')) return 'DOC';
    if (p.endsWith('.txt')) return 'TXT';
    return 'FILE';
  }

  void _openDocument(String path, String chunk) {
    if (path.toLowerCase().endsWith('.pdf')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentViewer(path: path, highlightText: chunk),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Viewer for this file type is not available yet.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral,
      body: SafeArea(
        child: Column(
          children: [
            // ── AppBar ─────────────────────────────────────────
            _buildAppBar(),

            // ── Search bar ────────────────────────────────────
            _buildSearchBar(),
            const SizedBox(height: 8),

            // ── Type filter chips ─────────────────────────────
            _buildTypeFilterChips(),
            const SizedBox(height: 4),

            // ── Content ───────────────────────────────────────
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
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
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.docBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description_rounded,
                color: AppColors.docBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documents',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${_allDocuments.length} indexed',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
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
          hintText: 'Search documents…',
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

  Widget _buildTypeFilterChips() {
    final chips = [
      ('All', 'all', Icons.layers_rounded),
      ('PDF', 'pdf', Icons.picture_as_pdf),
      ('PPT', 'pptx', Icons.slideshow),
      ('DOC', 'docx', Icons.description),
      ('TXT', 'txt', Icons.article),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, value, icon) = chips[i];
          final isActive = _typeFilter == value;
          return GestureDetector(
            onTap: () => setState(() => _typeFilter = value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                  Icon(icon,
                      size: 14,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Searching documents…',
                style: GoogleFonts.inter(
                    color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    final docs = _displayedDocs;
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 56,
                color: AppColors.textHint.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _searchResults != null
                  ? 'No documents found'
                  : 'No documents indexed yet',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              _searchResults != null
                  ? 'Try a different search term'
                  : 'Documents will appear here once indexed',
              style: GoogleFonts.inter(
                  color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildDocCard(docs[i]),
    );
  }

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final path = doc['path'] as String;
    final chunk = doc['chunk'] as String? ?? '';
    final fileName = path.split('/').last;
    final iconColor = _getDocIconColor(path);
    final typeLabel = _docTypeLabel(path);

    // File existence check
    final exists = File(path).existsSync();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDocument(path, chunk),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(_getDocIcon(path),
                          color: iconColor, size: 24),
                    ),
                    if (!exists)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: AppColors.pdfRed,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 8, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fileName,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: iconColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (chunk.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        chunk,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 10, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
