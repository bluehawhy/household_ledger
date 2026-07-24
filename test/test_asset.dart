import 'dart:convert';
import 'package:household_ledger/services/utils/asset_loader.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

// 1. Dart 실행을 위한 main 함수 추가
void main() async {
  print("🚀 Asset 로딩 테스트 시작...");
  await loadConfig();
  print("🎉 테스트 완료!");
}

Future<void> loadConfig() async {
  // Flutter 앱, Dart CLI 양쪽 모두 동일하게 사용 가능!
  final jsonString = await JsonAssetManager.loadJson('assets/card_bin_data.json');
  final Map<String, dynamic> data = jsonDecode(jsonString);
  
  print("성공적으로 JSON 로드 완료: ${data.length}개 항목");
}