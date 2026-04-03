import 'dart:math';

class VectorIndex {

  List<List<double>> vectors = [];
  List<String> paths = [];

  void add(List<double> vector, String path) {
    vectors.add(vector);
    paths.add(path);
  }

  List<Map<String, dynamic>> search(List<double> query, int k) {

    List<Map<String, dynamic>> results = [];

    for (int i = 0; i < vectors.length; i++) {

      double sim = cosineSimilarity(query, vectors[i]);

      results.add({
        "path": paths[i],
        "score": sim
      });
    }

    results.sort((a, b) => b["score"].compareTo(a["score"]));

    return results.take(k).toList();
  }

  double cosineSimilarity(List<double> a, List<double> b) {

    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {

      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    return dot / (sqrt(normA) * sqrt(normB));
  }
}