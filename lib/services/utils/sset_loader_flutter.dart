import 'package:flutter/services.dart' show rootBundle;
import 'asset_loader_stub.dart';

class FlutterAssetLoader implements AssetLoader {
  @override
  Future<String> loadString(String path) async {
    // Flutter 앱에서는 assets/ 경로를 그대로 로드
    return await rootBundle.loadString(path);
  }
}

AssetLoader getAssetLoader() => FlutterAssetLoader();