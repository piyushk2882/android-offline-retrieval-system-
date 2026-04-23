import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import 'vector_index.dart';
import 'document_vector_index.dart';
import 'vector_utils.dart';

VectorIndex globalIndex = VectorIndex();

/// Set to true once enough of the in-memory index has been loaded that
/// vector-similarity search is meaningful.
bool indexReady = false;

/// Loads image vectors and document chunk vectors into memory.
///
/// [onEarlyReady] is called after the image index + first document batch are
/// loaded, so the caller can unlock vector search early without waiting for
/// every chunk.
Future<void> loadIndex({VoidCallback? onEarlyReady}) async {
  // ── 1. Image index (usually fast, load all at once) ────────────────────
  var rows = await DatabaseHelper.instance.getAllEmbeddings();
  for (var row in rows) {
    if (!File(row["file_path"]).existsSync()) {
      await DatabaseHelper.instance.deleteEmbeddingByPath(row["file_path"]);
      continue;
    }
    var embedding = parseEmbedding(row["embedding"]);
    globalIndex.add(embedding, row["file_path"]);
  }
  print(
      "Image vector index loaded: ${globalIndex.vectors.length}/${rows.length} vectors");

  // ── 2. Document chunks — load in batches ───────────────────────────────
  int totalDocs = await DatabaseHelper.instance.getDocumentEmbeddingsCount();
  const int batchSize = 200; // smaller first batch → earlier unlock
  bool mismatch = false;
  bool earlyReadyFired = false;

  for (int offset = 0; offset < totalDocs; offset += batchSize) {
    var docRows = await DatabaseHelper.instance
        .getPaginatedDocumentEmbeddings(batchSize, offset);

    for (var row in docRows) {
      if (!File(row["file_path"]).existsSync()) {
        await DatabaseHelper.instance
            .deleteDocumentEmbeddingByPath(row["file_path"]);
        continue;
      }
      if (row["chunk_index"] == -1) continue;

      var embedding = List<double>.from(jsonDecode(row["embedding"]));
      if (embedding.length != 384) {
        mismatch = true;
        break;
      }
      globalDocumentIndex.add(embedding, row["file_path"], row["chunk_text"]);
    }

    if (mismatch) break;

    print(
        "Loaded batch: ${offset + docRows.length} / $totalDocs document chunks");

    // After the first batch is in memory, unlock search immediately
    if (!earlyReadyFired) {
      earlyReadyFired = true;
      indexReady = true;
      onEarlyReady?.call();
    }
  }

  if (mismatch) {
    print("Document dimension mismatch detected. Clearing old index...");
    await DatabaseHelper.instance.clearDocumentEmbeddings();
    globalDocumentIndex.vectors.clear();
    globalDocumentIndex.paths.clear();
    globalDocumentIndex.chunks.clear();
    indexReady = false;
  } else {
    indexReady = true;
    print(
        "Document vector index loaded: ${globalDocumentIndex.vectors.length} chunks");
  }
}