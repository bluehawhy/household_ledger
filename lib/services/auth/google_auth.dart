// google_auth.dart

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

// Flutter 전용 타입(GoogleSignInAccount) 대신 공통 인터페이스 사용
import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
    if (dart.library.html) 'google_auth_web.dart'
    if (dart.library.io) 'google_auth_dart.dart' // 👈 io 환경(CLI/Desktop) 로직 연결
    show getGoogleAuthService;

export 'google_auth_stub.dart';

class GoogleAuthManager {
  static final List<String> defaultScopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  final GoogleAuthService _authService = getGoogleAuthService(defaultScopes);

  // 필요 시 GoogleSignInAccount 대신 dynamic 이나 별도 User 모델을 연결
  dynamic get currentUser => _authService.currentUser;

  Future<AuthClient> getClient() async {
    return await _authService.getAuthenticatedClient();
  }
}