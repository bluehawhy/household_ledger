import 'package:googleapis/sheets/v4.dart' as sheets;
// 인증 및 시트 서비스 관련 파일 import (실제 경로에 맞춰 확인)
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 데이터 입력 테스트 시작");
  print("--------------------------------------------------");

  // 1. 서비스 및 인증 객체 생성
  final authManager = GoogleAuthManager();
  final sheetService = HouseholdSheetService();
  final parserService = TextParserService();

  // 2. 파서 및 인증 초기화
  await parserService.init(); // 카테고리 매핑 JSON 로드
  final client = await authManager.getClient(); // Google OAuth 인증 클라이언트 획득
  final sheetsApi = sheets.SheetsApi(client); // 또는 sheetService 내부에서 client를 사용하는 방식

  final String spreadsheetId = "YOUR_SPREADSHEET_ID_HERE"; // 실제 구글 시트 ID

  // 3. 테스트 문자열 데이터
  final List<String> inputLines = [
    "07/25 신한카드 점심 식비 12000원",
    "07/26 월급 3000000원 수입",
    "07/25 신한카드 점심 식비 12000원", // 중복 스킵 테스트용
  ];

  // 4. 순회 처리
  for (final line in inputLines) {
    print("\n📝 처리 입력: $line");
    await parserService.appendParseSingleLine(
      sheetsApi,
      spreadsheetId,
      line,
    );
  }

  print("\n--------------------------------------------------");
  print("🎉 모든 테스트 처리가 완료되었습니다.");
  print("--------------------------------------------------");
}