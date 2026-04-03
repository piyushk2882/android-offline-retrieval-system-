import 'dart:math';
List<double> parseEmbedding(String embedding) {

  return embedding
      .split(",")
      .map((e) => double.parse(e))
      .toList();
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) return 0.0;

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