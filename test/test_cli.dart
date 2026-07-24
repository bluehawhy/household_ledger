import 'package:googleapis/sheets/v4.dart' as sheets;
// 프로젝트 경로에 맞게 import 확인해주세요!
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

  try {
    // 2. 파서 초기화 (카테고리 매핑 JSON 로드)
    await parserService.init();

    // 3. 인증 클라이언트 획득
    final client = await authManager.getClient();
    print("🔐 Google OAuth 인증 성공!");

    // 4. 연도별 가계부 시트 ID 자동 획득 (가계부_2026 확인 또는 생성)
    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);
    print("📄 연결된 Spreadsheet ID: $spreadsheetId");

    final sheetsApi = sheets.SheetsApi(client);

    // 5. 테스트 입력 데이터
    final List<String> inputLines = [
      "2026/1/3		4987-61**-****-5083	정상	일시불	10,600 			쿠팡(쿠페이)-쿠팡(쿠페이)			220-81-15770",
      "2026/1/2		4579-72**-****-3087	정상	일시불	6,000 			어오케이커피 센텀점			235-48-01188	일반과세자",
    ];

    // 6. 라인별 파싱 및 시트 기입 실행
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

  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}