// 1. stub에서 getAssetLoader를 숨깁니다 (hide)
import 'asset_loader_stub.dart' hide getAssetLoader;

// 2. 플랫폼 조건에 따라 최우선 구현체의 getAssetLoader만 가져옵니다 (show)
import 'asset_loader_io.dart'
    if (dart.library.ui) 'asset_loader_flutter.dart'
    show getAssetLoader;

export 'asset_loader_stub.dart';

class JsonAssetManager {
  static final AssetLoader _loader = getAssetLoader();

  /// JSON 파일 내용을 문자열로 가져옵니다.
  static Future<String> loadJson(String path) {
    return _loader.loadString(path);
  }
}