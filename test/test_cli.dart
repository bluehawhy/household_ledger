import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 데이터 입력 테스트 시작");
  print("--------------------------------------------------");

  final authManager = GoogleAuthManager();
  final sheetService = HouseholdSheetService();

  // 1. 인증 클라이언트 획득
  final client = await authManager.getClient();

  try {
    // 2. 가계부 시트 ID 획득 (이미 생성되어 있다면 해당 ID를 반환하거나 가져옵니다)
    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);
    print("📄 사용 중인 Spreadsheet ID: $spreadsheetId");

    // 3. 테스트용 지출 데이터 입력
    print("💸 지출 내역 기록 중...");
    await sheetService.addTransaction(
      client: client,
      spreadsheetId: spreadsheetId,
      item: LedgerItem(
        date: DateTime.now(),
        type: TransactionType.expense,
        description: "점심 식대 (김치찌개)",
        amount: 10000,
        payMethod: "신용카드",
        category: "식비",
      ),
    );

    // 4. 테스트용 수입 데이터 입력
    print("💰 수입 내역 기록 중...");
    await sheetService.addTransaction(
      client: client,
      spreadsheetId: spreadsheetId,
      item: LedgerItem(
        date: DateTime.now(),
        type: TransactionType.income,
        description: "7월 급여",
        amount: 3500000,
        payMethod: "은행입금",
        category: "주수입",
      ),
    );

    print("--------------------------------------------------");
    print("🎉 데이터 추가 입력 완!");
    print("--------------------------------------------------");

  } catch (e, stackTrace) {
    print("❌ 실패! 에러 내용: $e");
    print("스택 트레이스:\n$stackTrace");
  } finally {
    // 5. 모든 연쇄 작업 완료 후 안전하게 종료
    client.close();
    print("🔒 인증 클라이언트 연결 종료 완료.");
  }
}