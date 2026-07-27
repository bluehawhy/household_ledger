// google_auth.dart
import 'package:google_sign_in/google_sign_in.dart'; // 💡 추가
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
    if (dart.library.html) 'google_auth_web.dart'
    if (dart.library.ui) 'google_auth_mobile.dart'
    if (dart.library.io) 'google_auth_desktop.dart'
    show getGoogleAuthService;

export 'google_auth_stub.dart';

class GoogleAuthManager {
  static final List<String> defaultScopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  final GoogleAuthService _authService = getGoogleAuthService(defaultScopes);

  // 💡 추가: 외부(MainUI 등)에서 _authManager.currentUser로 접근할 수 있게 연결
  GoogleSignInAccount? get currentUser => _authService.currentUser;

  Future<AuthClient> getClient() async {
    return await _authService.getAuthenticatedClient();
  }
}