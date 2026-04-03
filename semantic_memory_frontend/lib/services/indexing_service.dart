import 'dart:io';
import 'package:semantic_memory_frontend/services/index_loader.dart';

import 'api_service.dart';
import '../database/database_helper.dart';
import 'document_indexing_service.dart';

Future<void> startIndexing(List<File> files) async {
  List<File> newFiles = [];

  for (var file in files) {
    bool indexed = await DatabaseHelper.instance.isIndexed(file.path);

    if (!indexed) {
      newFiles.add(file);
    }
  }

  print("New files to index: ${newFiles.length}");

  const batchSize = 50;

  List<Future> workers = [];

  for (int i = 0; i < newFiles.length; i += batchSize) {
    var batch = newFiles.sublist(
      i,
      i + batchSize > newFiles.length ? newFiles.length : i + batchSize,
    );

    workers.add(processBatch(batch));
  }

  await Future.wait(workers);

  print("Batch indexing complete");

  await startDocumentIndexing();
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
