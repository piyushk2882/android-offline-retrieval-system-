import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

class PermissionService {
  /// Request photo/media permission (for image scanning via PhotoManager).
  static Future<bool> requestPermission() async {
    final permission = await PhotoManager.requestPermissionExtend();
    return permission.isAuth;
  }

  /// Request full external-storage access.
  /// On Android 11+ (API 30+) this is MANAGE_EXTERNAL_STORAGE, which sends
  /// the user to the system "All files access" settings page.
  /// On older Android versions we fall back to READ_EXTERNAL_STORAGE.
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 11+ — request "All files access"
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      // If the dedicated permission isn't available (Android < 11), fall back
      final fallback = await Permission.storage.request();
      return fallback.isGranted;
    }
    return true; // iOS / desktop — not needed
  }
}