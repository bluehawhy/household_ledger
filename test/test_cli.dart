import 'package:googleapis/sheets/v4.dart' as sheets;

// 💡 프로젝트 내부 서비스 import
import 'package:household_ledger/services/auth/google_auth_dart.dart';
import 'package:household_ledger/services/auth/google_auth_stub.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';

void main() async {
  print("--------------------------------------------------");
  print("📊 가계부 통합 테스트 (입력 & 수정 케이스) 시작");
  print("--------------------------------------------------");

  // ⚙️ [테스트 제어 플래그] 실행하려는 테스트 케이스를 true / false 로 설정하세요.
  const bool runInsertTest = false; // 👈 입력 테스트 실행 여부
  const bool runUpdateTest = false; // 👈 업데이트 테스트 실행 여부

  // 1. 서비스 및 인증 객체 생성
  final GoogleAuthService authService = DesktopGoogleAuthService([
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/spreadsheets',
  ]);

  final sheetService = LedgerDataService();
  // 🚀 이관된 비즈니스 로직을 담당하는 Ingestion 서비스 생성
  final ingestionService = LedgerIngestionService();

  try {
    // 2. Google OAuth 인증
    final client = await authService.getAuthenticatedClient();
    print("🔐 Google OAuth 인증 성공!");

    // 3. 연도별 가계부 시트 ID 자동 획득/설정
    final spreadsheetId = await sheetService.sheetSetupService
        .setupLedgerSpreadsheetForYear(client, DateTime.now().year);
    print("📄 연결된 Spreadsheet ID: $spreadsheetId");

    // =========================================================================
    // 📥 [CASE 1] 가계부 데이터 입력(Insert) 테스트
    // =========================================================================
    if (runInsertTest) {
      print("\n==================================================");
      print("🚀 [TEST 1] 가계부 데이터 입력(Insert) 테스트 시작");
      print("==================================================");

      final List<String> rawInputs = [
        "2026.08.27 월급 1400000\n2026.07.27 11:52\t신한카드\t네이버페이-제로맥주구매\t3,000\t\n2026.07.27 09:54\t신한카드\t사단법인해운대구스포츠클럽\t38,500\t\n2026.07.23 06:06\t신한카드\t네이버페이 - 양파구매\t2,490\t\n2026.07.22 17:08\t신한카드\t정쌤 미용실\t16,000\t\n2026.07.22 11:09\t신한카드\t네이버플러스 멤버십\t4,900\t\n2026.07.21 16:29\t신한카드\t파랑약국\t6,230\t\n2026.07.21 16:26\t신한카드\t권순완소아과의원\t2,900\t\n2026.07.20 08:32\t신한카드\tKT통신요금 자동납부\t41,300",
        "2026.8.30 11:18\t신한카드\t에스케이텔레콤 (주) - 우주패스 구독\t14,900\t고정지출\n\n 2026.07.27 16:14\t신한카드\t주식회사 하이파킹\t10,000\t\n\n 2026.08.21 11:50\t카드\tAPPLE 일반\t14,000\t미입력"
      ];

      int overallSuccessCount = 0;
      int overallDuplicateCount = 0;
      int overallFailCount = 0;

      for (int i = 0; i < rawInputs.length; i++) {
        final rawInput = rawInputs[i];
        print("\n--------------------------------------------------");
        print("📌 [입력 케이스 ${i + 1}] 원본 입력:");
        print(rawInput);
        print("--------------------------------------------------");

        // 🚀 이관된 LedgerIngestionService의 processAndSubmit() 단일 메서드 호출
        final LedgerSubmitResult result = await ingestionService.processAndSubmit(
          authClient: client,
          rawInput: rawInput,
        );

        if (result.isSuccess) {
          print(" 📊 [전송 결과] 총: ${result.total}건 | 성공: ${result.success}건 | 중복: ${result.duplicate}건 | 실패: ${result.fail}건");
          
          overallSuccessCount += result.success;
          overallDuplicateCount += result.duplicate;
          overallFailCount += result.fail;
        } else {
          print(" ❌ [전송 실패] 원인: ${result.errorMessage}");
          overallFailCount += result.total;
        }
      }

      print("\n🎉 입력 테스트 완료!");
      print("📊 누적 결과 -> 성공: $overallSuccessCount건 | 중복: $overallDuplicateCount건 | 실패: $overallFailCount건");
    } else {
      print("\n⏭️ [TEST 1] 가계부 데이터 입력 테스트는 건너뜁니다. (runInsertTest = false)");
    }

    // =========================================================================
    // 🔄 [CASE 2] 가계부 데이터 업데이트(Update) 테스트
    // =========================================================================
    if (runUpdateTest) {
      print("\n==================================================");
      print("🔄 [TEST 2] 가계부 Map 데이터 수정(Update) 테스트 시작");
      print("==================================================");

      final Map<String, dynamic> originalMap = {
        'date': DateTime.parse('2026-08-21'),
        'type': TransactionType.expense,
        'payMethod': '카드',
        'category': '미입력',
        'description': 'APPLE 일반',
        'amount': 14000,
        'memo': '',
      };

      final Map<String, dynamic> updatedMap = {
        'date': DateTime.parse('2026-08-21'),
        'type': TransactionType.expense,
        'payMethod': '카드',
        'category': '고정비용',
        'description': 'APPLE 일반',
        'amount': 15000,
        'memo': '수정 테스트 메모',
      };

      print("📌 [UI 입력 데이터 확인]");
      print(" 🔹 기존 내역 (original): $originalMap");
      print(" 🔹 변경 내역 (updated) : $updatedMap");

      final originalItem = LedgerItem.fromMap(originalMap);
      final updatedItem = LedgerItem.fromMap(updatedMap);

      final bool isSuccess = await sheetService.updateTransaction(
        client: client,
        oldItem: originalItem,
        newItem: updatedItem,
        spreadsheetId: spreadsheetId,
      );

      if (isSuccess) {
        print("\n✅ [성공] 기존 내역을 찾아서 성공적으로 업데이트했습니다.");
      } else {
        print("\n❌ [실패] 내역 업데이트 대상을 찾지 못했거나 오류가 발생했습니다.");
      }
    } else {
      print("\n⏭️ [TEST 2] 가계부 데이터 업데이트 테스트는 건너뜁니다. (runUpdateTest = false)");
    }

    print("\n--------------------------------------------------");
    print("🏁 모든 테스트 시나리오가 정상 종료되었습니다.");
    print("--------------------------------------------------");
  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}