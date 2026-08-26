import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/drive/v3.dart' as drive;

// 💡 프로젝트 내부 서비스 import
import 'package:household_ledger/services/auth/google_auth_dart.dart';
import 'package:household_ledger/services/auth/google_auth_stub.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';

void main() async {
  print("--------------------------------------------------");
  print("🔐 GoogleSpreadsheetService 공유/해제 기능 테스트 시작");
  print("--------------------------------------------------");

  // ⚙️ [테스트 제어 플래그]
  const bool runShareSheetTest = true;   // 👈 1. 시트 공유 테스트 실행 여부
  const bool runShareFolderTest = true;  // 👈 2. 폴더 공유 테스트 실행 여부
  const bool runRemoveFolderShareTest = false; // 👈 3. 폴더 공유 해제 테스트 실행 여부
  const bool runRemoveSheetShareTest = false;  // 👈 4. 시트 공유 해제 테스트 실행 여부

  // 1. 테스트 파라미터 설정
  // ⚠️ 실제 안내 메일이 발송되므로 테스트 가능한 이메일을 입력하세요.
  // 💡 테스트할 대상 ID (본인의 실제 Spreadsheet ID / Drive Folder ID 입력)
  // 이건 mk24244
  //const String sampleSpreadsheetId = "19GPgo7F7swEi7b9k2aH5K_y38zw20rbHfjzGbB2gt-g";
  //const String sampleFolderId = "1SvmU3hOU--ZnYYT0o-L1vlJMfqVQXl_D";
  // const String targetEmail = "bluehawhy@gmail.com"; 

  const String sampleSpreadsheetId = "19GPgo7F7swEi7b9k2aH5K_y38zw20rbHfjzGbB2gt-g";
  const String sampleFolderId = "1SvmU3hOU--ZnYYT0o-L1vlJMfqVQXl_D";
  const String targetEmail = "mk24244@gmail.com"; 

  
  // 2. OAuth 인증 서비스 생성 (Drive API 접근 권한 Scope 필요)
  final GoogleAuthService authService = DesktopGoogleAuthService([
    'https://www.googleapis.com/auth/drive', // Google Drive 전체 접근 권한
    'https://www.googleapis.com/auth/spreadsheets',
  ]);

  try {
    // 3. Google OAuth 인증 실행 및 AuthClient 획득
    final AuthClient client = await authService.getAuthenticatedClient();
    print("🔐 Google OAuth 인증 성공!");

    // 4. 작성하신 GoogleSpreadsheetService 인스턴스 생성
    final spreadsheetService = GoogleSpreadsheetService(client);

    // =========================================================================
    // 📄 [CASE 1] 특정 스프레드시트(Sheet) 공유 테스트
    // =========================================================================
    if (runShareSheetTest) {
      print("\n==================================================");
      print("🚀 [TEST 1] 스프레드시트(Sheet) 공유 테스트 시작");
      print("==================================================");
      print("📌 대상 Sheet ID : $sampleSpreadsheetId");
      print("📌 공유 대상 메일: $targetEmail");
      print("📌 권한 수준     : writer (편집자)");
      print("--------------------------------------------------");

      final drive.Permission permission = await spreadsheetService.shareFileOrFolder(
        fileOrFolderId: sampleSpreadsheetId,
        email: targetEmail,
        role: 'writer',
        sendNotificationEmail: true,
      );

      print("✅ [성공] 스프레드시트 공유 완료!");
      print(" 🆔 Permission ID: ${permission.id}");
      print(" 👤 공유 이메일  : ${permission.emailAddress ?? targetEmail}");
      print(" 🔑 부여된 권한  : ${permission.role}");
    } else {
      print("\n⏭️ [TEST 1] 스프레드시트 공유 테스트는 건너뜁니다.");
    }

    // =========================================================================
    // 📁 [CASE 2] Google Drive 폴더(Folder) 공유 테스트
    // =========================================================================
    if (runShareFolderTest) {
      print("\n==================================================");
      print("📁 [TEST 2] Google Drive 폴더 공유 테스트 시작");
      print("==================================================");
      print("📌 대상 Folder ID: $sampleFolderId");
      print("📌 공유 대상 메일: $targetEmail");
      print("📌 권한 수준     : reader (읽기 전용)");
      print("--------------------------------------------------");

      final drive.Permission permission = await spreadsheetService.shareFileOrFolder(
        fileOrFolderId: sampleFolderId,
        email: targetEmail,
        role: 'reader',
        sendNotificationEmail: false, // 알림 메일 미발송 테스트
      );

      print("✅ [성공] Drive 폴더 공유 완료!");
      print(" 🆔 Permission ID: ${permission.id}");
      print(" 👤 공유 이메일  : ${permission.emailAddress ?? targetEmail}");
      print(" 🔑 부여된 권한  : ${permission.role}");
    } else {
      print("\n⏭️ [TEST 2] Google Drive 폴더 공유 테스트는 건너뜁니다.");
    }

    // =========================================================================
    // 🗑️ [CASE 3] Google Drive 폴더(Folder) 공유 해제 테스트 (폴더부터 해제)
    // =========================================================================
    if (runRemoveFolderShareTest) {
      print("\n==================================================");
      print("🗑️ [TEST 3] Google Drive 폴더 공유 해제 테스트 시작");
      print("==================================================");
      print("📌 대상 Folder ID: $sampleFolderId");
      print("📌 삭제 대상 메일: $targetEmail");
      print("--------------------------------------------------");

      final bool isRemoved = await spreadsheetService.removeShare(
        fileOrFolderId: sampleFolderId,
        email: targetEmail,
      );

      if (isRemoved) {
        print("✅ [성공] Drive 폴더 공유 해제 완료!");
      } else {
        print("ℹ️ [안내] 기존 공유 권한이 없어 삭제 작업을 건너뛰었습니다.");
      }
    } else {
      print("\n⏭️ [TEST 3] Google Drive 폴더 공유 해제 테스트는 건너뜁니다.");
    }

    // =========================================================================
    // 🗑️ [CASE 4] 스프레드시트(Sheet) 공유 해제 테스트 (폴더 해제 후 파일 해제)
    // =========================================================================
    if (runRemoveSheetShareTest) {
      print("\n==================================================");
      print("🗑️ [TEST 4] 스프레드시트(Sheet) 공유 해제 테스트 시작");
      print("==================================================");
      print("📌 대상 Sheet ID : $sampleSpreadsheetId");
      print("📌 삭제 대상 메일: $targetEmail");
      print("--------------------------------------------------");

      final bool isRemoved = await spreadsheetService.removeShare(
        fileOrFolderId: sampleSpreadsheetId,
        email: targetEmail,
      );

      if (isRemoved) {
        print("✅ [성공] 스프레드시트 공유 해제 완료!");
      } else {
        print("ℹ️ [안내] 기존 공유 권한이 없어 삭제 작업을 건너뛰었습니다.");
      }
    } else {
      print("\n⏭️ [TEST 4] 스프레드시트 공유 해제 테스트는 건너뜁니다.");
    }

    print("\n--------------------------------------------------");
    print("🏁 모든 공유/해제 테스트 시나리오가 정상 종료되었습니다.");
    print("--------------------------------------------------");
  } catch (e, stackTrace) {
    print("\n❌ 테스트 도중 에러 발생: $e");
    print("📍 스택 트레이스:\n$stackTrace");
  }
}