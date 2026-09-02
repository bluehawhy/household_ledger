// 💡 프로젝트 내부 서비스 import
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/auth/google_auth_dart.dart';
import 'package:household_ledger/services/auth/google_auth_stub.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_ingestion_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_transaction_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

void main() async {
  AppLogger.i("--------------------------------------------------");
  AppLogger.i("📊 가계부 통합 테스트 (입력 & 수정 & 시트 검색) 시작");
  AppLogger.i("--------------------------------------------------");

  // ⚙️ [테스트 제어 플래그] 실행하려는 테스트 케이스를 true / false 로 설정하세요.
  const bool runInsertTest = false; // 👈 입력 테스트 실행 여부
  const bool runUpdateTest = false; // 👈 업데이트 테스트 실행 여부
  const bool runSpreadsheetSearchTest = true; // 👈 Google Drive 시트 검색 테스트

  // 1. 서비스 및 인증 객체 생성
  // ⚠️ 공유 폴더/파일 검색 확인을 위해 drive.file 대신 전체 Drive scope 사용
  final GoogleAuthService authService = DesktopGoogleAuthService([
    'https://www.googleapis.com/auth/drive',
    'https://www.googleapis.com/auth/spreadsheets',
  ]);

  final sheetService = LedgerDataService();
  // 🚀 이관된 비즈니스 로직을 담당하는 Ingestion 서비스 생성
  final ingestionService = LedgerIngestionService();

  try {
    // 2. Google OAuth 인증
    final client = await authService.getAuthenticatedClient();
    AppLogger.i("🔐 Google OAuth 인증 성공!");

    // =========================================================================
    // 🔎 [CASE 0] Google Drive 스프레드시트 검색 진단 테스트
    // =========================================================================
    if (runSpreadsheetSearchTest) {
      AppLogger.i("\n==================================================");
      AppLogger.i("🔎 [TEST 0] Google Drive 스프레드시트 검색 진단 시작");
      AppLogger.i("==================================================");

      final driveApi = drive.DriveApi(client);
      final driveSheetService = DriveSheetService(driveApi);

      // ------------------------------------------------------------
      // 0-1. 현재 계정에서 보이는 모든 스프레드시트 검색
      // ------------------------------------------------------------
      AppLogger.i("🔎 [전체 시트 검색] 시작");
      AppLogger.i("🔎 Query: mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false");

      int totalSpreadsheetCount = 0;
      String? pageToken;

      do {
        final result = await driveApi.files.list(
          q: "mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
          spaces: 'drive',
          corpora: 'user',
          includeItemsFromAllDrives: true,
          pageToken: pageToken,
          $fields: 'nextPageToken,incompleteSearch,files(id,name,owners(emailAddress),sharingUser(emailAddress),driveId,shared,parents)',
        );

        final files = result.files ?? const <drive.File>[];
        totalSpreadsheetCount += files.length;

        AppLogger.i(
          "🔎 [전체 시트 검색 Page] ${files.length}개, "
          "incompleteSearch=${result.incompleteSearch == true}, "
          "nextPage=${result.nextPageToken != null}",
        );

        for (final file in files) {
          AppLogger.i(
            "   ├─ name=${file.name}, id=${file.id}, "
            "owners=${file.owners?.map((o) => o.emailAddress).toList()}, "
            "sharingUser=${file.sharingUser?.emailAddress}, "
            "driveId=${file.driveId}, shared=${file.shared}, "
            "parents=${file.parents}",
          );
        }

        pageToken = result.nextPageToken;
      } while (pageToken != null);

      AppLogger.i("🔎 [전체 시트 검색 완료] 총 $totalSpreadsheetCount개");

      // ------------------------------------------------------------
      // 0-2. '가계부' 이름을 포함하는 스프레드시트 검색
      // ------------------------------------------------------------
      AppLogger.i("🔎 ['가계부' 시트 검색] 시작");
      const sheetQuery =
          "name contains '가계부' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
      AppLogger.i("🔎 Query: $sheetQuery");

      final namedResult = await driveApi.files.list(
        q: sheetQuery,
        spaces: 'drive',
        corpora: 'user',
        includeItemsFromAllDrives: true,
        $fields: 'files(id,name,owners(emailAddress),sharingUser(emailAddress),driveId,shared,parents)',
      );

      final namedFiles = namedResult.files ?? const <drive.File>[];
      AppLogger.i("🔎 ['가계부' 시트 검색 결과] 총 ${namedFiles.length}개");
      for (final file in namedFiles) {
        AppLogger.i(
          "   ├─ name=${file.name}, id=${file.id}, "
          "owners=${file.owners?.map((o) => o.emailAddress).toList()}, "
          "sharingUser=${file.sharingUser?.emailAddress}, "
          "shared=${file.shared}, parents=${file.parents}",
        );
      }

      // ------------------------------------------------------------
      // 0-3. 기존 DriveSheetService의 폴더 내부 시트 검색 API 자체 확인
      //      (현재 공유 폴더 ID를 알고 있다면 아래 ID를 넣어서 테스트 가능)
      // ------------------------------------------------------------
      const knownFolderId = '';
      if (knownFolderId.isNotEmpty) {
        AppLogger.i("🔎 [폴더 내부 시트 검색] Folder ID: $knownFolderId");
        final folderSheets = await driveSheetService.getSpreadsheetsInFolder(
          folderId: knownFolderId,
        );
        AppLogger.i("📊 [폴더 내부 시트 검색 결과] $folderSheets");
      } else {
        AppLogger.i("⏭️ [폴더 내부 시트 검색] Folder ID 미지정 → 건너뜁니다.");
      }

      AppLogger.i("🏁 [TEST 0] Google Drive 스프레드시트 검색 진단 완료");
    } else {
      AppLogger.i("⏭️ [TEST 0] Google Drive 스프레드시트 검색 테스트는 건너뜁니다. (runSpreadsheetSearchTest = false)");
    }

    // 3. 연도별 가계부 시트 ID 자동 획득/설정
    final spreadsheetId = await sheetService.sheetSetupService
        .setupLedgerSpreadsheetForYear(client, DateTime.now().year);
    AppLogger.i("📄 연결된 Spreadsheet ID: $spreadsheetId");

    // =========================================================================
    // 📥 [CASE 1] 가계부 데이터 입력(Insert) 테스트
    // =========================================================================
    if (runInsertTest) {
      AppLogger.i("\n==================================================");
      AppLogger.i("🚀 [TEST 1] 가계부 데이터 입력(Insert) 테스트 시작");
      AppLogger.i("==================================================");

      final List<String> rawInputs = [
        "2026.08.27 월급 1400000\n2026.07.27 11:52\t신한카드\t네이버페이-제로맥주구매\t3,000\t\n2026.07.27 09:54\t신한카드\t사단법인해운대구스포츠클럽\t38,500\t\n2026.07.23 06:06\t신한카드\t네이버페이 - 양파구매\t2,490\t\n2026.07.22 17:08\t신한카드\t정쌤 미용실\t16,000\t\n2026.07.22 11:09\t신한카드\t네이버플러스 멤버십\t4,900\t\n2026.07.21 16:29\t신한카드\t파랑약국\t6,230\t\n2026.07.21 16:26\t신한카드\t권순완소아과의원\t2,900\t\n2026.07.20 08:32\t신한카드\tKT통신요금 자동납부\t41,300",
        "2026.8.30 11:18\t신한카드\t에스케이텔레콤 (주) - 우주패스 구독\t14,900\t고정지출\n\n 2026.07.27 16:14\t신한카드\t주식회사 하이파킹\t10,000\t\n\n 2026.08.21 11:50\t카드\tAPPLE 일반\t14,000\t미입력"
      ];

      int overallSuccessCount = 0;
      int overallDuplicateCount = 0;
      int overallFailCount = 0;

      for (int i = 0; i < rawInputs.length; i++) {
        final rawInput = rawInputs[i];
        AppLogger.i("\n--------------------------------------------------");
        AppLogger.i("📌 [입력 케이스 ${i + 1}] 원본 입력:");
        AppLogger.i(rawInput);
        AppLogger.i("--------------------------------------------------");

        // 🚀 이관된 LedgerIngestionService의 processAndSubmit() 단일 메서드 호출
        final LedgerSubmitResult result = await ingestionService.processAndSubmit(
          authClient: client,
          rawInput: rawInput,
        );

        if (result.isSuccess) {
          AppLogger.i(" 📊 [전송 결과] 총: ${result.total}건 | 성공: ${result.success}건 | 중복: ${result.duplicate}건 | 실패: ${result.fail}건");
          
          overallSuccessCount += result.success;
          overallDuplicateCount += result.duplicate;
          overallFailCount += result.fail;
        } else {
          AppLogger.i(" ❌ [전송 실패] 원인: ${result.errorMessage}");
          overallFailCount += result.total;
        }
      }

      AppLogger.i("\n🎉 입력 테스트 완료!");
      AppLogger.i("📊 누적 결과 -> 성공: $overallSuccessCount건 | 중복: $overallDuplicateCount건 | 실패: $overallFailCount건");
    } else {
      AppLogger.i("⏭️ [TEST 1] 가계부 데이터 입력 테스트는 건너뜁니다. (runInsertTest = false)");
    }

    // =========================================================================
    // 🔄 [CASE 2] 가계부 데이터 업데이트(Update) 테스트
    // =========================================================================
    if (runUpdateTest) {
      AppLogger.i("\n==================================================");
      AppLogger.i("🔄 [TEST 2] 가계부 Map 데이터 수정(Update) 테스트 시작");
      AppLogger.i("==================================================");

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

      AppLogger.i("📌 [UI 입력 데이터 확인]");
      AppLogger.i(" 🔹 기존 내역 (original): $originalMap");
      AppLogger.i(" 🔹 변경 내역 (updated) : $updatedMap");

      final originalItem = LedgerItem.fromMap(originalMap);
      final updatedItem = LedgerItem.fromMap(updatedMap);

      final bool isSuccess = await sheetService.updateTransaction(
        client: client,
        oldItem: originalItem,
        newItem: updatedItem,
        spreadsheetId: spreadsheetId,
      );

      if (isSuccess) {
        AppLogger.i("✅ [성공] 기존 내역을 찾아서 성공적으로 업데이트했습니다.");
      } else {
        AppLogger.i("❌ [실패] 내역 업데이트 대상을 찾지 못했거나 오류가 발생했습니다.");
      }
    } else {
      AppLogger.i("⏭️ [TEST 2] 가계부 데이터 업데이트 테스트는 건너뜁니다. (runUpdateTest = false)");
    }

    AppLogger.i("--------------------------------------------------");
    AppLogger.i("🏁 모든 테스트 시나리오가 정상 종료되었습니다.");
    AppLogger.i("--------------------------------------------------");
  } catch (e, stackTrace) {
    AppLogger.i("❌ 테스트 도중 에러 발생: $e");
    AppLogger.i("📍 스택 트레이스:\n$stackTrace");
  }
}
