import 'package:flutter/services.dart' show rootBundle;
// asset_loader_io.dart 및 asset_loader_flutter.dart 상단
import 'asset_loader_stub.dart'; 
export 'asset_loader_stub.dart'; // AssetLoader 추상 클래스 타입을 밖으로 전달

class FlutterAssetLoader implements AssetLoader {
  @override
  Future<String> loadString(String path) async {
    // Flutter 앱에서는 assets/ 경로를 그대로 로드
    return await rootBundle.loadString(path);
  }
}

AssetLoader getAssetLoader() => FlutterAssetLoader();