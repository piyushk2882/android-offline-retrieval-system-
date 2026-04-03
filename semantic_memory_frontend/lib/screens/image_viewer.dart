import 'dart:io';
import 'package:flutter/material.dart';
import 'package:semantic_memory_frontend/theme/app_theme.dart';

class ImageViewer extends StatelessWidget {
  final String path;
  final String heroTag;

  const ImageViewer({
    super.key,
    required this.path,
    this.heroTag = '',
  });

  @override
  Widget build(BuildContext context) {
    final fileName = path.split("/").last;

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
            child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
            Navigator.pop(context);
          }
        },
        child: Center(
          child: heroTag.isNotEmpty
              ? Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                  ),
                ),
        ),
      ),
    );
  }
}
