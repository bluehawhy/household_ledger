abstract class AssetLoader {
  Future<String> loadString(String path);
}

/// 조건이 맞지 않거나 기본 상태일 때 호출되는 스텁 함수
AssetLoader getAssetLoader() =>
    throw UnsupportedError('현재 플랫폼에서 AssetLoader를 지원하지 않습니다.');