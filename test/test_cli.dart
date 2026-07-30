import 'package:googleapis/sheets/v4.dart' as sheets;

// 프로젝트 경로에 맞게 import 확인해주세요!
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/ledger_ingestion/single_entry_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 데이터 입력 테스트 시작");
  print("--------------------------------------------------");

  // 1. 서비스 및 인증 객체 생성
  final authManager = GoogleAuthManager();
  final sheetService = HouseholdSheetService();
  final parserService = TextParserService();
  final singleEntryService = SingleEntryService();

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

    // 5. 테스트 입력 데이터 (단일 라인 + 엔터/줄바꿈 포함 다중 라인 테스트 케이스)
    final List<String> rawInputs = [
      // 케이스 1: 카드 내역 복사 탭 구분 텍스트 (단일)
      "2026/1/3\t\t4987-61**-****-5083\t정상\t일시불\t10,600 \t\t\t쿠팡(쿠페이)-쿠팡(쿠페이)\t\t\t220-81-15770",
      
      // 케이스 2: 엔터(\n)가 포함된 여러 건의 카드/통장 알림 문자 복사본
      "2026/1/2\t\t4579-72**-****-3087\t정상\t일시불\t6,000 \t\t\t어오케이커피 센텀점\t\t\t235-48-01188\t일반과세자\n"
      "07/25 15:04\n 출금 \n\n88,220원 입출금통장(1483) → 메가마트\n"
      "2026-02-10 15,000원 택시비 지출",
      
      // 케이스 3: 자연어 형태의 단일 내역
      "어제 12,500원 스타벅스 신한카드"
    ];

    int overallSuccessCount = 0;
    int overallDuplicateCount = 0;
    int overallFailCount = 0;

    // 6. rawInputs 케이스별 처리 실행
    for (int i = 0; i < rawInputs.length; i++) {
      final rawInput = rawInputs[i];
      print("\n--------------------------------------------------");
      print("📌 [테스트 케이스 ${i + 1}] 원본 입력:");
      print(rawInput);
      print("--------------------------------------------------");

      // 6-1. TextParserService로 줄바꿈/날짜 기준 텍스트 전처리 및 라인 분할
      final List<String> lines = rawInput
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
      print("✂️ 분할된 문장 수: ${lines.length}개");

      for (final line in lines) {
        print("\n  📝 processing line: $line");

        // 6-2. 텍스트 -> Map 파싱
        final Map<String, dynamic> itemMap = parserService.parseSingleLineToMap(line);
        print("  🔍 파싱 결과: $itemMap");

        // 6-3. Google Sheet 저장 및 중복 체크
        final ParseResult result = await singleEntryService.appendParseSingleLine(
          sheetsApi,
          spreadsheetId,
          itemMap,
        );

        if (result == ParseResult.success) {
          print("  ✅ [성공] 시트 추가 완료");
          overallSuccessCount++;
        } else if (result == ParseResult.duplicate) {
          print("  ⚠️ [중복] 이미 존재하는 내역으로 건너뜀");
          overallDuplicateCount++;
        } else {
          print("  ❌ [실패] 저장 중 오류 발생");
          overallFailCount++;
        }
      }
    }

    print("\n--------------------------------------------------");
    print("🎉 모든 테스트 처리가 완료되었습니다.");
    print("📊 최종 결과 -> 성공: $overallSuccessCount건 | 중복 스킵: $overallDuplicateCount건 | 실패: $overallFailCount건");
    print("--------------------------------------------------");

  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}