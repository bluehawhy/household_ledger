import 'package:googleapis/sheets/v4.dart' as sheets;

// 프로젝트 경로에 맞게 import 확인해주세요!
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 데이터 입력 테스트 시작 (UI 완전 일치 버전)");
  print("--------------------------------------------------");

  // 1. 서비스 및 인증 객체 생성
  final authManager = GoogleAuthManager();
  final sheetService = HouseholdSheetService();
  final textParserService = TextParserService();
  final singleEntryService = SingleEntryService();
  final multiEntryService = MultiEntryService();

  try {
    // 2. 파서 초기화 (카테고리 매핑 JSON 로드)
    await textParserService.init();

    // 3. 인증 클라이언트 획득
    final client = await authManager.getClient();
    print("🔐 Google OAuth 인증 성공!");

    // 4. 연도별 가계부 시트 ID 자동 획득 (가계부_2026 확인 또는 생성)
    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);
    print("📄 연결된 Spreadsheet ID: $spreadsheetId");

    final sheetsApi = sheets.SheetsApi(client);

    // 5. 테스트 입력 데이터
    final List<String> rawInputs = [
      "2026.07.27 월급 1400000\n2026.07.27 11:52	신한카드	네이버페이-제로맥주구매	3,000	\n\2026.07.27 09:54	신한카드	사단법인해운대구스포츠클럽	38,500	\n\2026.07.23 06:06	신한카드	네이버페이 - 양파구매	2,490	\n\2026.07.22 17:08	신한카드	정쌤 미용실	16,000	\n\2026.07.22 11:09	신한카드	네이버플러스 멤버십	4,900	\n\2026.07.21 16:29	신한카드	파랑약국	6,230	\n\2026.07.21 16:26	신한카드	권순완소아과의원	2,900	\n\2026.07.20 08:32	신한카드	KT통신요금 자동납부	41,300",
      "2026.07.30 11:18	신한카드	에스케이텔레콤 (주) - 우주패스 구둑	14,900	고정지출\n\n 2026.07.27 16:14	신한카드	주식회사 하이파킹	10,000	\n\n 2<PASSWORD>.<PASSWORD> 11:5<PASSWORD> 신한카드	네이버페이-제로맥주구매	3,<PASSWORD>	\n\n "
    ];

    int overallSuccessCount = 0;
    int overallDuplicateCount = 0;
    int overallFailCount = 0;

    // 6. rawInputs 케이스별 처리 실행 (UI submitLedgerEntry 내부 로직 반영)
    for (int i = 0; i < rawInputs.length; i++) {
      final rawInput = rawInputs[i];
      print("\n--------------------------------------------------");
      print("📌 [테스트 케이스 ${i + 1}] 원본 입력:");
      print(rawInput);
      print("--------------------------------------------------");

      // 6-1. UI와 동일한 라인 분할 전처리
      final List<String> lines = textParserService.parseInputLines(rawInput);
      print("✂️ 분할된 문장 수: ${lines.length}개");

      // -----------------------------------------------------------------
      // 🔀 [분기] 1줄이면 SingleEntryService, 2줄 이상이면 MultiEntryService
      // -----------------------------------------------------------------
      if (lines.length == 1) {
        // [단일 라인 처리]
        print("  📝 [SingleEntryService] 단일 항목 처리 실행");
        final Map<String, dynamic> itemMap = textParserService.parseSingleLineToMap(lines.first);
        print("  🔍 파싱 결과: $itemMap");

        final ParseResult result = await singleEntryService.appendParseSingleLine(
          sheetsApi,
          spreadsheetId,
          itemMap,
        );

        if (result == ParseResult.success) {
          print("  ✅ [성공] 단일 항목 시트 추가 완료");
          overallSuccessCount++;
        } else if (result == ParseResult.duplicate) {
          print("  ⚠️ [중복] 이미 존재하는 내역으로 건너뜀");
          overallDuplicateCount++;
        } else {
          print("  ❌ [실패] 저장 중 오류 발생");
          overallFailCount++;
        }

      } else if (lines.length > 1) {
        // [다중 라인 처리]
        print("  🚀 [MultiEntryService] ${lines.length}개 다중 항목 일괄 처리 실행");

        // 전체 라인을 Map 리스트로 변환
        final List<Map<String, dynamic>> itemMaps = lines
            .map((line) {
              final parsed = textParserService.parseSingleLineToMap(line);
              print("    🔍 파싱 항목: $parsed");
              return parsed;
            })
            .toList();

        // UI에서 호출하는 서비스 함수 및 반환타입(Map<ParseResult, int>) 그대로 반영
        final Map<ParseResult, int> resultMap = await multiEntryService.appendParseMultiLines(
          sheetsApi,
          spreadsheetId,
          itemMaps,
        );

        final int success = resultMap[ParseResult.success] ?? 0;
        final int duplicate = resultMap[ParseResult.duplicate] ?? 0;
        final int fail = resultMap[ParseResult.fail] ?? 0;

        overallSuccessCount += success;
        overallDuplicateCount += duplicate;
        overallFailCount += fail;

        print("  📊 [다중 항목 전송 결과] 성공: $success건 | 중복: $duplicate건 | 실패: $fail건");
      }
    }

    print("\n--------------------------------------------------");
    print("🎉 모든 테스트 처리가 완료되었습니다.");
    print("📊 최종 누적 결과 -> 성공: $overallSuccessCount건 | 중복 스킵: $overallDuplicateCount건 | 실패: $overallFailCount건");
    print("--------------------------------------------------");

  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}