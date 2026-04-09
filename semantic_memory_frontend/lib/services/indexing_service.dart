import 'dart:io';
import 'package:semantic_memory_frontend/services/index_loader.dart';

import 'api_service.dart';
import '../database/database_helper.dart';

/// Throttled batch indexer.
/// [onProgress] receives (indexed, total) after each successful batch.
Future<void> startIndexing(
  List<File> files, {
  void Function(int indexed, int total)? onProgress,
}) async {
  List<File> newFiles = [];

  for (var file in files) {
    bool indexed = await DatabaseHelper.instance.isIndexed(file.path);
    if (!indexed) {
      newFiles.add(file);
    }
  }

  print("New files to index: ${newFiles.length}");

  const batchSize = 20;      // smaller batch = less data per request
  const maxConcurrent = 3;   // max parallel requests to avoid flooding server

  int indexed = 0;
  final int total = newFiles.length;

  // Build all batches
  List<List<File>> batches = [];
  for (int i = 0; i < newFiles.length; i += batchSize) {
    batches.add(
      newFiles.sublist(
        i,
        i + batchSize > newFiles.length ? newFiles.length : i + batchSize,
      ),
    );
  }

  // Process with throttled concurrency
  int batchIndex = 0;
  while (batchIndex < batches.length) {
    final window = batches.sublist(
      batchIndex,
      (batchIndex + maxConcurrent) > batches.length
          ? batches.length
          : batchIndex + maxConcurrent,
    );

    await Future.wait(window.map((batch) async {
      await processBatch(batch);
      indexed += batch.length;
      onProgress?.call(indexed, total);
    }));

    batchIndex += maxConcurrent;
  }

  print("Batch indexing complete");
}

Future<void> processBatch(List<File> batch) async {
  print("Processing batch of ${batch.length}");

  var embeddings = await ApiService.embedImagesBatch(batch);

  if (embeddings == null) return;

  for (int i = 0; i < batch.length; i++) {
    await DatabaseHelper.instance.insertEmbedding(
      batch[i].path,
      embeddings[i],
    );
    globalIndex.add(embeddings[i], batch[i].path);
  }
}
