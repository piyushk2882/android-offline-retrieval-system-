import 'dart:async';
import 'dart:io';
import 'package:semantic_memory_frontend/services/document_vector_index.dart';
import 'api_service.dart';
import '../database/database_helper.dart';

/// Scans document folders using async stream so the UI thread is never blocked.
Future<List<File>> scanDocuments() async {
  final Set<String> seenPaths = {};
  final List<File> docs = [];

  // Common Android locations where documents are stored
  final List<String> folders = [
    "/storage/emulated/0/Download",
    "/storage/emulated/0/Downloads",
    "/storage/emulated/0/Documents",
    "/storage/emulated/0/WhatsApp/Media/WhatsApp Documents",
    "/storage/emulated/0/WhatsApp/Documents",
    "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Documents",
    "/storage/emulated/0/Telegram",
    "/storage/emulated/0/Books",
    "/storage/emulated/0/Ebooks",
    "/storage/emulated/0/PDF",
    "/storage/emulated/0/Notes",
  ];

  const allowedExtensions = [".pdf", ".docx", ".pptx", ".txt", ".doc", ".ppt"];

  for (final path in folders) {
    final dir = Directory(path);
    final exists = await dir.exists();
    print("[DocScan] $path — exists: $exists");
    if (!exists) continue;

    try {
      int count = 0;
      // Use async stream — does NOT block the main/UI thread
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final lp = entity.path.toLowerCase();
          if (allowedExtensions.any((ext) => lp.endsWith(ext))) {
            if (seenPaths.add(entity.path)) {
              docs.add(entity);
              count++;
            }
          }
        }
      }
      print("[DocScan] Found $count doc(s) in $path");
    } catch (e) {
      print("[DocScan] Error scanning $path: $e");
    }
  }

  print("[DocScan] Total documents found: ${docs.length}");
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
    print("All documents already indexed.");
    return;
  }

  const batchSize = 3; // Keep small — document embedding is heavier than images

  for (int i = 0; i < newFiles.length; i += batchSize) {
    final int end =
        (i + batchSize > newFiles.length) ? newFiles.length : i + batchSize;
    final List<File> batch = newFiles.sublist(i, end);

    print("Processing document batch ${i ~/ batchSize + 1}/${(newFiles.length / batchSize).ceil()}");

    await processDocumentBatch(batch);
  }

  print("Document indexing complete");
}

Future<void> processDocumentBatch(List<File> batch) async {
  for (final File file in batch) {
    print("Processing document: ${file.path}");

    final response = await ApiService.embedDocument(file);

    if (response == null) continue;

    final List chunks = response["chunks"];
    final List embeddings = response["embeddings"];

    if (chunks.isEmpty) {
      await DatabaseHelper.instance.insertDocumentEmbedding(
        file.path,
        "",
        [],
        -1,
      );
      continue;
    }

    for (int i = 0; i < chunks.length; i++) {
      await DatabaseHelper.instance.insertDocumentEmbedding(
        file.path,
        chunks[i],
        embeddings[i],
        i,
      );

      globalDocumentIndex.add(
        List<double>.from(embeddings[i]),
        file.path,
        chunks[i],
      );
    }
  }
}
