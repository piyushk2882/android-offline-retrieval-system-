import 'dart:io';

class FileScanner {

  static List<String> supportedExtensions = [
    ".jpg",
    ".jpeg",
    ".png",
    ".heic",
    ".HEIC",
    ".pdf",
    ".docx",
    ".pptx"
  ];

  static Future<List<File>> scanFolders(List<String> folders) async {

    List<File> files = [];

    for (var folder in folders) {

      final dir = Directory(folder);

      if (!dir.existsSync()) continue;

      final entities = dir.listSync(recursive: true);

      for (var entity in entities) {

        if (entity is File) {

          if (supportedExtensions.any((ext) =>
              entity.path.toLowerCase().endsWith(ext))) {

            files.add(entity);
          }
        }
      }
    }

    return files;
  }
}