import 'package:photo_manager/photo_manager.dart';

class PermissionService {

  static Future<bool> requestPermission() async {

    final permission = await PhotoManager.requestPermissionExtend();

    return permission.isAuth;
  }
}