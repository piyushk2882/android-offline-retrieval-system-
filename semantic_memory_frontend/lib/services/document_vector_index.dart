class DocumentVectorIndex {

  List<List<double>> vectors = [];
  List<String> paths = [];
  List<String> chunks = [];

  void add(List embedding, String path, String chunk) {

    vectors.add(List<double>.from(embedding));
    paths.add(path);
    chunks.add(chunk);
  }
}

final globalDocumentIndex = DocumentVectorIndex();