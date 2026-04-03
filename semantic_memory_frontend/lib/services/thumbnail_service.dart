import 'dart:io';
import 'package:flutter/material.dart';

class ThumbnailService {

  static Future<ImageProvider> loadThumbnail(String path) async {

    var file = File(path);

    return ResizeImage(
      FileImage(file),
      width: 200,
      height: 200,
    );
  }
}