import 'package:googleapis/sheets/v4.dart' as sheets;

// 💡 Pure Dart 전용 서비스 및 스텁 참조
import 'package:household_ledger/services/auth/google_auth_dart.dart';
import 'package:household_ledger/services/auth/google_auth_stub.dart';

import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 Map 데이터 수정(UI 데이터 연동) 테스트 시작");
  print("--------------------------------------------------");

  // 1. Pure Dart 전용 DesktopGoogleAuthService 생성
  final GoogleAuthService authService = DesktopGoogleAuthService([
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/spreadsheets',
  ]);

  final sheetService = HouseholdSheetService();

  try {
    // 2. AuthClient 획득
    final client = await authService.getAuthenticatedClient();
    print("🔐 Google OAuth 인증 성공!");

    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);
    print("📄 연결된 Spreadsheet ID: $spreadsheetId");

 // 💡 시트에 기록된 데이터와 토씨 하나 안 틀리고 똑같이 매칭시킵니다.
    final Map<String, dynamic> originalMap = {
      'date': DateTime.parse('2026-08-21'),
      'paymentMethod': '카드',
      'category': '미입력',
      'title': 'APPLE 일반',
      'description': 'APPLE 일반', // 👈 LedgerItem 내부에서 description으로 매핑되는 경우 대비
      'amount': 14000,
    };

    final Map<String, dynamic> updatedMap = {
      'date': DateTime.parse('2026-08-21'),
      'paymentMethod': '카드',
      'category': '고정비용', // 👈 수정하려는 카테고리
      'title': 'APPLE 일반',
      'description': 'APPLE 일반',
      'amount': 15000,      // 👈 수정하려는 금액
    };

    print("\n📌 [UI 입력 데이터 확인]");
    print(" 🔹 기존 내역 (original): $originalMap");
    print(" 🔹 변경 내역 (updated) : $updatedMap");

    // Map -> LedgerItem 변환
    final originalItem = LedgerItem.fromMap(originalMap);
    final updatedItem = LedgerItem.fromMap(updatedMap);

    // 4. HouseholdSheetService의 updateTransaction 호출
    final bool isSuccess = await sheetService.updateTransaction(
      client: client,
      oldItem: originalItem,
      newItem: updatedItem,
      spreadsheetId: spreadsheetId,
    );

    // 5. 결과 확인
    if (isSuccess) {
      print("\n✅ [성공] 기존 내역을 찾아서 성공적으로 업데이트했습니다.");
    } else {
      print("\n❌ [실패] 내역 업데이트 대상을 찾지 못했거나 오류가 발생했습니다.");
    }

    print("--------------------------------------------------");

  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}