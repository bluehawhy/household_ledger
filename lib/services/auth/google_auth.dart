// google_auth.dart

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
    if (dart.library.html) 'google_auth_web.dart'
    if (dart.library.io) 'google_auth_mobile.dart'
    show getGoogleAuthService;

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

  /// 새로고침 후 이미 살아 있는 Web API 인증 클라이언트를 복원한다.
  /// 모바일에서는 일반 getClient() 흐름을 사용하므로 null을 반환한다.
  Future<AuthClient?> restoreAuthorizedClient() async {
    try {
      final result = await (_authService as dynamic).restoreAuthorizedClient();
      return result is AuthClient ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// 현재 로그인 계정이 API scope를 사용할 수 있는지 확인한다.
  Future<bool> canAccessScopes() async {
    try {
      return await (_authService as dynamic).canAccessScopes();
    } catch (_) {
      return false;
    }
  }

  /// 사용자 동작으로 API scope 권한을 요청한다.
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
