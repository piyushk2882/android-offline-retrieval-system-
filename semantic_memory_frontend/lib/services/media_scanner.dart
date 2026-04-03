import 'package:photo_manager/photo_manager.dart';

class MediaScanner {

  static Future<List<AssetEntity>> getImages() async {

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    List<AssetEntity> allImages = [];

    for (var album in albums) {

      final images = await album.getAssetListPaged(
        page: 0,
        size: 1000,
      );

      allImages.addAll(images);
    }

    return allImages;
  }
}