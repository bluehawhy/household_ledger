// google_auth.dart

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
    if (dart.library.html) 'google_auth_web.dart'
    if (dart.library.io) 'google_auth_mobile.dart'
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

  Future<dynamic> signInSilently() async {
    try {
      return await (_authService as dynamic).signInSilently();
    } catch (_) {
      return currentUser;
    }
  }

  /// 웹에서 Drive/Sheets OAuth 권한을 사용자에게 요청한다.
  /// 모바일에서는 이미 로그인 과정에서 권한이 처리되므로 현재 클라이언트를
  /// 그대로 사용할 수 있게 true를 반환한다.
  Future<bool> authorizeScopes() async {
    try {
      final result = await (_authService as dynamic).requestAuthorization();
      return result == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> signOut() async {
    try {
      await (_authService as dynamic).signOut();
    } catch (_) {}
  }
}
