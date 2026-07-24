import 'dart:io';
import 'asset_loader_stub.dart';

class IoAssetLoader implements AssetLoader {
  @override
  Future<String> loadString(String path) async {
    // CLI 실행 기준 위치(루트)에서 파일 읽기
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('❌ CLI 환경에서 파일을 찾을 수 없습니다: $path');
    }
    return await file.readAsString();
  }
}

AssetLoader getAssetLoader() => IoAssetLoader();