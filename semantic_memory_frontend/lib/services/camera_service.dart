import 'dart:io';
import 'package:image_picker/image_picker.dart';

class CameraService {

  static final ImagePicker _picker = ImagePicker();

  static Future<File?> captureImage() async {

    final XFile? photo =
        await _picker.pickImage(source: ImageSource.camera);

    if (photo == null) return null;

    return File(photo.path);
  }
}