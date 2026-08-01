import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

// Flutter 전용 타입(GoogleSignInAccount) 대신 공통 인터페이스 사용
import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
    if (dart.library.html) 'google_auth_web.dart'
    if (dart.library.io) 'google_auth_mobile.dart' // 👈 google_auth_dart.dart 대신 mobile로 변경!
    show getGoogleAuthService;

export 'google_auth_stub.dart';

class GoogleAuthManager {
  static final List<String> defaultScopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  final GoogleAuthService _authService = getGoogleAuthService(defaultScopes);

  dynamic get currentUser => _authService.currentUser;

  Future<AuthClient> getClient() async {
    return await _authService.getAuthenticatedClient();
  }
}