import 'package:photo_manager/photo_manager.dart';

class MediaScanner {

  static Future<List<AssetEntity>> getImages() async {

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );

    // Use a set to deduplicate by asset id across albums
    final Set<String> seen = {};
    final List<AssetEntity> allImages = [];

    for (var album in albums) {
      final int total = await album.assetCountAsync;
      const int pageSize = 200;
      int page = 0;

      while (page * pageSize < total) {
        final images = await album.getAssetListPaged(
          page: page,
          size: pageSize,
        );
        for (final img in images) {
          if (seen.add(img.id)) {
            allImages.add(img);
          }
        }
        page++;
      }
    }

    return allImages;
  }
}