import 'index_loader.dart';
import 'document_vector_index.dart';
import 'vector_utils.dart';

Future<List<Map<String, dynamic>>> fastSearch(List<double> query) async {
  print("Index size: ${globalIndex.vectors.length}");
  return globalIndex.search(query, 10);
}

List<Map<String, dynamic>> searchDocuments(List<double> query, String queryText) {

  print("Document search: query dim=${query.length}, index size=${globalDocumentIndex.vectors.length}");

  if (globalDocumentIndex.vectors.isNotEmpty) {
    print("Document vector dim: ${globalDocumentIndex.vectors[0].length}");
  }

  List<Map<String, dynamic>> allResults = [];

  List<String> queryWords =
      queryText.toLowerCase().split(RegExp(r'\s+'));

  double maxSim = -1.0;

  for (int i = 0; i < globalDocumentIndex.vectors.length; i++) {

    double sim = cosineSimilarity(
      query,
      globalDocumentIndex.vectors[i],
    );

    if (sim > maxSim) maxSim = sim;

    // Only consider documents above a minimum semantic similarity
    if (sim < 0.15) continue;

    String path = globalDocumentIndex.paths[i].toLowerCase();
    String chunk = globalDocumentIndex.chunks[i].toLowerCase();

    double boost = 0.0;

    // Filename boost (minor tie-breaker)
    for (var word in queryWords) {
      if (word.length > 2 && path.contains(word)) {
        boost += 0.05;
      }
    }

    // Chunk keyword boost (minor tie-breaker)
    for (var word in queryWords) {
      if (word.length > 2 && chunk.contains(word)) {
        boost += 0.03;
      }
    }

    allResults.add({
      "path": globalDocumentIndex.paths[i],
      "chunk": globalDocumentIndex.chunks[i],
      "score": sim + boost,
      "type": "document"
    });
  }

  print("Document search: maxSim=$maxSim, results above threshold=${allResults.length}");

  allResults.sort((a, b) =>
      (b["score"] as double).compareTo(a["score"] as double));

  // Deduplicate by file path
  Map<String, Map<String, dynamic>> deduped = {};

  for (var res in allResults) {
    String path = res["path"];

    if (!deduped.containsKey(path)) {
      deduped[path] = res;
    }
  }

  return deduped.values.toList().take(5).toList();
}