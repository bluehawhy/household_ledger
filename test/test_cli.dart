import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';

// 프로젝트 내부 서비스
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';

void main() async {
  print("==================================================");
  print("📊 가계부 데이터 자동 입력 및 조회 테스트 시작");
  print("==================================================");

  // 1. 서비스 및 인증 객체 초기화
  final authManager = GoogleAuthManager();
  final sheetService = HouseholdSheetService();
  final parserService = TextParserService();

  AuthClient? client;

  try {
    // 2. 파서 초기화 (카테고리 매핑 및 BIN 데이터 JSON 로드)
    print("\n1️⃣ 파서 서비스 초기화 중...");
    await parserService.init();

    // 3. 구글 OAuth 인증 클라이언트 획득
    print("\n2️⃣ Google OAuth 인증 요청...");
    client = await authManager.getClient();
    print("✅ Google OAuth 인증 성공!");

    // 4. 연도별 가계부 시트 확인 및 생성 (예: 가계부_2026)
    print("\n3️⃣ 가계부 스프레드시트 연결 확인 중...");
    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);
    print("📄 연결된 Spreadsheet ID: $spreadsheetId");

    final sheetsApi = sheets.SheetsApi(client);

    // 5. 테스트용 샘플 텍스트 데이터 (신한/삼성 카드 엑셀 복사 및 SMS 문자)
    //final List<String> inputLines = [
    //  "2026/1/3\t\t4987-61**-****-5083\t정상\t일시불\t10,600 \t\t\t쿠팡(쿠페이)-쿠팡(쿠페이)\t\t\t220-81-15770",
    //  "2026/1/2\t\t4579-72**-****-3087\t정상\t일시불\t6,000 \t\t\t어오케이커피 센텀점\t\t\t235-48-01188\t일반과세자",
    //  "07/25 15:04 출금 88,220원 입출금통장(1483) → 메가마트",
    //];

    //// 6. 라인별 파싱 및 시트 데이터 추가 수행
    //print("\n4️⃣ 데이터 파싱 및 스프레드시트 기록 시작...");
    //for (int i = 0; i < inputLines.length; i++) {
    //  final line = inputLines[i];
    //  print("\n--------------------------------------------------");
    //  print("📝 [Line ${i + 1}] 처리할 입력문:");
    //  print("   \"$line\"");

    //  await parserService.appendParseSingleLine(
    //    sheetsApi,
    //    spreadsheetId,
    //    line,
    //  );
    //}

    // 💰 2027년 7월 수입/지출 내역 조회 및 출력
    final targetYear = 2026;
    final targetMonth = 7;

    print("\n--------------------------------------------------");
    print("📥 [$targetYear년 $targetMonth월] 수입/지출 내역 조회 요청 중...");

    // 1) 수입 내역 조회
    final incomes = await sheetService.getMonthlyIncomes(
      client: client,
      year: targetYear,
      month: targetMonth,
    );

    print("\n💵 [수입 내역] 총 ${incomes.length}건");
    if (incomes.isEmpty) {
      print("   내역이 없습니다.");
    } else {
      for (final item in incomes) {
        print("   • [${item.formattedDate}] ${item.description} | ${item.amount}원 (${item.category})");
      }
    }

    // 2) 지출 내역 조회
    final expenses = await sheetService.getMonthlyExpenses(
      client: client,
      year: targetYear,
      month: targetMonth,
    );

    print("\n💳 [지출 내역] 총 ${expenses.length}건");
    if (expenses.isEmpty) {
      print("   내역이 없습니다.");
    } else {
      for (final item in expenses) {
        final payMethodStr = item.payMethod != null ? " | 수단: ${item.payMethod}" : "";
        print("   • [${item.formattedDate}] ${item.description} | ${item.amount}원 (${item.category}$payMethodStr)");
      }
    }

    print("\n==================================================");
    print("🎉 모든 가계부 데이터 테스트 및 조회가 완료되었습니다.");
    print("==================================================");

  } catch (e, stackTrace) {
    print("\n❌ 테스트 진행 중 오류 발생: $e");
    print("📍 Details / StackTrace:\n$stackTrace");
  } finally {
    // 사용한 HTTP 클라이언트 세션 종료
    client?.close();
  }
}