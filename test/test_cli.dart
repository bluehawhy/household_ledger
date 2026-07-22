import '../lib/services/auth/google_auth.dart';

void main() async {
  print("--------------------------------------------------");
  print("🚀 CLI 환경에서 가계부 연동 테스트 시작");
  print("--------------------------------------------------");

  try {
    final manager = GoogleSheetManager();
    final spreadsheetId = await manager.runHouseholdLedgerSetup();

    print("--------------------------------------------------");
    print("🎉 성공적으로 시트 설정이 완료되었습니다!");
    print("📄 Spreadsheet ID: $spreadsheetId");
    print("--------------------------------------------------");
  } catch (e) {
    print("❌ 오류 발생: $e");
  }
}