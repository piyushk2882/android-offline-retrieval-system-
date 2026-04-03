import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class DocumentViewer extends StatelessWidget {
  final String path;
  final String highlightText;

  const DocumentViewer({
    super.key,
    required this.path,
    required this.highlightText,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = path.split("/").last;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fileName,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.pdfRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, size: 16, color: AppColors.pdfRed),
                const SizedBox(width: 4),
                Text(
                  "PDF",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.pdfRed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SfPdfViewer.file(
        File(path),
      ),
    );
  }
}