import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';

void main() {
  // Flutter 테스트 환경에서 에셋(rootBundle)을 읽을 수 있도록 동기화
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter rootBundle 환경에서 에셋 로드 테스트', () async {
    final jsonString = await JsonAssetManager.loadJson('assets/ledger_ingestion_info.json');
    
    print("✅ Flutter 에셋 로드 성공! 길이: ${jsonString.length}");
    expect(jsonString, isNotEmpty);
  });
}