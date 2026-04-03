import '../database/database_helper.dart';
import 'vector_utils.dart';

Future<List<Map<String, dynamic>>> searchImages(List<double> queryEmbedding) async {

  var rows = await DatabaseHelper.instance.getAllEmbeddings();

  List<Map<String, dynamic>> results = [];

  for (var row in rows) {

    var embedding = parseEmbedding(row["embedding"]);

    var similarity = cosineSimilarity(queryEmbedding, embedding);

    results.add({
      "path": row["file_path"],
      "score": similarity
    });
  }

  results.sort((a, b) => b["score"].compareTo(a["score"]));

  return results.take(10).toList();
}