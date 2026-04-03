import 'dart:io';
import 'package:semantic_memory_frontend/services/document_vector_index.dart';
import 'api_service.dart';
import '../database/database_helper.dart';

Future<List<File>> scanDocuments() async {
  List<File> docs = [];

  List<String> folders = [
    "/storage/emulated/0/Download",
    "/storage/emulated/0/Documents",
    "/storage/emulated/0/WhatsApp/Documents"
  ];

  for (var path in folders) {
    var dir = Directory(path);

    if (!await dir.exists()) continue;

    var files = dir.listSync(recursive: true);

    for (var f in files) {
      if (f is File) {
        if (f.path.endsWith(".pdf") ||
            f.path.endsWith(".docx") ||
            f.path.endsWith(".pptx") ||
            f.path.endsWith(".txt")) {
          docs.add(f);
        }
      }
    }
  }

  return docs;
}

Future<void> startDocumentIndexing() async {
  print("Starting document scan...");

  List<File> files = await scanDocuments();

  if (files.isEmpty) {
    print("No documents found");
    return;
  }

  print("Documents detected: ${files.length}");

  List<File> newFiles = [];
  for (var file in files) {
    bool isIndexed = await DatabaseHelper.instance.isDocumentIndexed(file.path);
    if (!isIndexed) {
      newFiles.add(file);
    }
  }

  print("New documents to index: ${newFiles.length}");

  if (newFiles.isEmpty) {
    return;
  }

  const batchSize = 5;

  for (int i = 0; i < newFiles.length; i += batchSize) {
    int end = (i + batchSize > newFiles.length) ? newFiles.length : i + batchSize;

    List<File> batch = newFiles.sublist(i, end);

    print("Processing document batch ${i ~/ batchSize + 1}");

    await processDocumentBatch(batch);
  }

  print("Document indexing complete");
}

Future<void> processDocumentBatch(List<File> batch) async {
  for (File file in batch) {
    print("Processing document: ${file.path}");

    var response = await ApiService.embedDocument(file);

    if (response == null) continue;

    List chunks = response["chunks"];
    List embeddings = response["embeddings"];

    for (int i = 0; i < chunks.length; i++) {
      await DatabaseHelper.instance.insertDocumentEmbedding(
        file.path,
        chunks[i],
        embeddings[i],
        i,
      );

      globalDocumentIndex.add(embeddings[i], file.path, chunks[i]);
    }
  }
}
