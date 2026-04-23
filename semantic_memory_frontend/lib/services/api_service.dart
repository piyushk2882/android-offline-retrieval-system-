import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  static const baseUrl = "http://10.41.229.7:8000";

  // ── Server health-check cache ──────────────────────────────────────────────
  // Avoids 24-second waits when the server is down: one cheap probe per 30s.
  static bool _serverReachable = false;
  static DateTime? _lastHealthCheck;
  static const _healthCheckInterval = Duration(seconds: 30);
  static const _healthCheckTimeout = Duration(seconds: 2);
  static const _embedTimeout = Duration(seconds: 10);

  /// Returns true if the server responds within 2 seconds.
  /// Result is cached for 30 seconds so repeated calls are free.
  static Future<bool> isServerReachable() async {
    final now = DateTime.now();
    if (_lastHealthCheck != null &&
        now.difference(_lastHealthCheck!) < _healthCheckInterval) {
      return _serverReachable;
    }

    try {
      final response = await http
          .get(Uri.parse("$baseUrl/health"))
          .timeout(_healthCheckTimeout);
      _serverReachable = response.statusCode < 500;
    } catch (_) {
      _serverReachable = false;
    }

    _lastHealthCheck = now;
    print("[ApiService] Server reachable: $_serverReachable");
    return _serverReachable;
  }

  /// Call after a successful API response to mark the server as up
  /// without waiting for the next health-check cycle.
  static void _markServerUp() {
    _serverReachable = true;
    _lastHealthCheck = DateTime.now();
  }

  /// Call after a failed API response to force a fresh probe next time.
  static void _markServerDown() {
    _serverReachable = false;
    _lastHealthCheck = null; // force re-probe on next request
  }

  // ── Image embedding ────────────────────────────────────────────────────────
  static Future<List<double>?> embedImage(File file) async {
    if (!await isServerReachable()) return null;
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/embed_image"),
      );
      request.files.add(await http.MultipartFile.fromPath("file", file.path));
      var response = await request.send().timeout(_embedTimeout);
      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();
        _markServerUp();
        return List<double>.from(json.decode(body)["embedding"]);
      }
    } catch (e) {
      print("Embedding error: $e");
      _markServerDown();
    }
    return null;
  }

  // ── Batch image embedding ──────────────────────────────────────────────────
  static Future<List<List<double>>?> embedImagesBatch(List<File> files) async {
    if (!await isServerReachable()) return null;
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
      var response = await request.send().timeout(_embedTimeout);
      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();
        _markServerUp();
        return (json.decode(body)["embeddings"] as List)
            .map((e) => List<double>.from(e))
            .toList();
      }
    } catch (e) {
      print("Batch embedding error: $e");
      _markServerDown();
    }
    return null;
  }

  // ── Document text embedding ────────────────────────────────────────────────
  static Future<List<double>?> embedTextDoc(String text) async {
    if (!await isServerReachable()) {
      print("[ApiService] embedTextDoc skipped — server unreachable");
      return null;
    }

    try {
      final url = Uri.parse("$baseUrl/embed_text_doc")
          .replace(queryParameters: {"text": text});

      print("Doc embed URL: $url");

      final response = await http.get(url).timeout(_embedTimeout);

      print("Doc embed status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final embedding = List<double>.from(data["embedding"]);
        print("Doc query embedding dim: ${embedding.length}");
        _markServerUp();
        return embedding;
      }
    } catch (e) {
      print("Doc embedding error: $e");
      _markServerDown();
    }
    return null;
  }

  // ── Image text embedding ───────────────────────────────────────────────────
  static Future<List<double>?> embedText(String text) async {
    if (!await isServerReachable()) {
      print("[ApiService] embedText skipped — server unreachable");
      return null;
    }

    try {
      final response = await http
          .post(Uri.parse("$baseUrl/embed_text?text=$text"))
          .timeout(_embedTimeout);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _markServerUp();
        return List<double>.from(jsonData["embedding"]);
      }
      print("Server response: ${response.body}");
    } catch (e) {
      print("Text embedding error: $e");
      _markServerDown();
    }
    return null;
  }

  // ── Document file embedding (indexing) ─────────────────────────────────────
  static Future<Map<String, dynamic>?> embedDocument(File file) async {
    if (!await isServerReachable()) return null;
    try {
      var request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/embed_document"),
      );
      request.files.add(await http.MultipartFile.fromPath("file", file.path));
      var response = await request.send().timeout(_embedTimeout);
      if (response.statusCode == 200) {
        var body = await response.stream.bytesToString();
        _markServerUp();
        return json.decode(body);
      }
    } catch (e) {
      print("Document embedding error: $e");
      _markServerDown();
    }
    return null;
  }
}
