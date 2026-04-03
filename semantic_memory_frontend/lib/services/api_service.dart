import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const baseUrl = "http://10.93.150.7:8000";

  static Future<List<double>?> embedImage(File file) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/embed_image"),
      );

      request.files.add(await http.MultipartFile.fromPath("file", file.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();

        var jsonData = json.decode(body);

        return List<double>.from(jsonData["embedding"]);
      }
    } catch (e) {
      print("Embedding error: $e");
    }

    return null;
  }

  static Future<List<List<double>>?> embedImagesBatch(List<File> files) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/embed_images_batch"),
      );

      for (var file in files) {
        request.files.add(
          await http.MultipartFile.fromPath("files", file.path),
        );
      }

      var response = await request.send();

      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();

        var jsonData = json.decode(body);

        return (jsonData["embeddings"] as List)
            .map((e) => List<double>.from(e))
            .toList();
      }
    } catch (e) {
      print("Batch embedding error: $e");
    }

    return null;
  }

  static Future<List<double>?> embedTextDoc(String text) async {
    try {
      final url = Uri.parse("$baseUrl/embed_text_doc").replace(
        queryParameters: {"text": text},
      );

      print("Doc embed URL: $url");

      final response = await http.get(url);

      print("Doc embed status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List<double> embedding = List<double>.from(data["embedding"]);
        print("Doc query embedding dim: ${embedding.length}");

        return embedding;
      }
    } catch (e) {
      print("Doc embedding error: $e");
    }

    return null;
  }

  static Future<List<double>?> embedText(String text) async {
    try {
      var response = await http.post(
        Uri.parse("$baseUrl/embed_text?text=$text"),
      );

      if (response.statusCode == 200) {
        var jsonData = json.decode(response.body);

        return List<double>.from(jsonData["embedding"]);
      }

      print("Server response: ${response.body}");
    } catch (e) {
      print("Text embedding error: $e");
    }

    return null;
  }

  static Future<Map<String, dynamic>?> embedDocument(File file) async {
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/embed_document"),
      );

      request.files.add(await http.MultipartFile.fromPath("file", file.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();

        return json.decode(body);
      }
    } catch (e) {
      print("Document embedding error: $e");
    }

    return null;
  }
}
