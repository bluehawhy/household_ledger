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

  Stream<dynamic> get onCurrentUserChanged =>
      (_authService as dynamic).onCurrentUserChanged;

  Future<dynamic> signIn() async {
    return await (_authService as dynamic).signIn();
  }

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

  /// 현재 로그인 계정이 API scope를 사용할 수 있는지 확인한다.
  ///
  /// 권한 상태를 알 수 없는 경우 true로 간주하지 않는다.
  /// 웹에서는 로그인(Authentication)과 API 권한(Authorization)이
  /// 별개이므로, false이면 사용자 동작으로 authorizeScopes()를 호출해야 한다.
  Future<bool> canAccessScopes() async {
    try {
      return await (_authService as dynamic).canAccessScopes();
    } catch (_) {
      return false;
    }
  }

  /// 사용자 동작으로 API scope 권한을 요청한다.
  ///
  /// 권한 요청 실패/취소를 성공으로 간주하지 않는다.
  Future<bool> authorizeScopes() async {
    try {
      final result = await (_authService as dynamic).requestAuthorization();
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await (_authService as dynamic).signOut();
    } catch (_) {}
  }
}
