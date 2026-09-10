import 'dart:convert';
import 'package:household_ledger/services/utils/asset_loader.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


// 1. Dart 실행을 위한 main 함수 추가
void main() async {
  AppLogger.i("🚀 Asset 로딩 테스트 시작...");
  await loadConfig();
  AppLogger.i("🎉 테스트 완료!");
}

Future<void> loadConfig() async {
  // Flutter 앱, Dart CLI 양쪽 모두 동일하게 사용 가능!
  final jsonString = await JsonAssetManager.loadJson('assets/data/card_bin_data.json');
  final Map<String, dynamic> data = jsonDecode(jsonString);
  
  AppLogger.i("성공적으로 JSON 로드 완료: ${data.length}개 항목");
}