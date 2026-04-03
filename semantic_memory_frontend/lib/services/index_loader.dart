import 'dart:convert';
import '../database/database_helper.dart';
import 'vector_index.dart';
import 'document_vector_index.dart';
import 'vector_utils.dart';

VectorIndex globalIndex = VectorIndex();

Future<void> loadIndex() async {
  // Load images
  var rows = await DatabaseHelper.instance.getAllEmbeddings();
  for (var row in rows) {
    var embedding = parseEmbedding(row["embedding"]);
    globalIndex.add(embedding, row["file_path"]);
  }
  print("Image vector index loaded: ${rows.length} vectors");

  // Load documents
  int totalDocs = await DatabaseHelper.instance.getDocumentEmbeddingsCount();
  const int batchSize = 500;
  bool mismatch = false;

  for (int offset = 0; offset < totalDocs; offset += batchSize) {
    var docRows = await DatabaseHelper.instance.getPaginatedDocumentEmbeddings(batchSize, offset);
    
    for (var row in docRows) {
      var embedding = List<double>.from(jsonDecode(row["embedding"]));
      if (embedding.length != 384) {
        mismatch = true;
        break;
      }
      globalDocumentIndex.add(embedding, row["file_path"], row["chunk_text"]);
    }
    
    if (mismatch) break;
    print("Loaded batch: ${offset + docRows.length} / $totalDocs document chunks");
  }

  if (mismatch) {
    print("Document dimension mismatch detected. Clearing old index...");
    await DatabaseHelper.instance.clearDocumentEmbeddings();
    globalDocumentIndex.vectors.clear();
    globalDocumentIndex.paths.clear();
    globalDocumentIndex.chunks.clear();
  } else {
    print("Document vector index loaded: $totalDocs chunks");
  }
}