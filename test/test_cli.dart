import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
// 💡 조건부 임포트 대신 데스크톱 전용 파일 직접 임포트
import 'package:household_ledger/services/auth/google_auth_desktop.dart'; 

void main() async {
  print("--------------------------------------------------");
  print("🔑 1단계: 구글 인증(Google Auth) CLI 테스트 시작");
  print("--------------------------------------------------");

  try {
    final scopes = [
      drive.DriveApi.driveFileScope,
      sheets.SheetsApi.spreadsheetsScope,
    ];

    print("📡 데스크톱 인증 서비스 생성 중...");
    // desktop 파일의 getGoogleAuthService 직접 호출
    final authService = getGoogleAuthService(scopes);

    print("🔑 로그인 및 인증 클라이언트(AuthClient) 요청 중...");
    final client = await authService.getAuthenticatedClient();

    print("--------------------------------------------------");
    print("✅ 구글 인증 성공!");
    print("🔑 Client 객체: ${client.runtimeType}");
    print("--------------------------------------------------");

    client.close();
  } catch (e, stackTrace) {
    print("--------------------------------------------------");
    print("❌ 구글 인증 실패!");
    print("에러 내용: $e");
    print("스택 트레이스:\n$stackTrace");
    print("--------------------------------------------------");
  }
}