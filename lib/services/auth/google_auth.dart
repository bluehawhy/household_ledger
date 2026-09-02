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

  /// 사용자가 로그인 버튼을 눌렀을 때 호출하는 실제 Google 로그인.
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

  /// 현재 Google 계정에 Drive/Sheets 권한이 이미 승인되어 있는지 확인한다.
  Future<bool> canAccessScopes() async {
    try {
      return await (_authService as dynamic).canAccessScopes();
    } catch (_) {
      // 모바일은 로그인 과정에서 필요한 scope가 함께 처리되므로 true로 본다.
      return true;
    }
  }

  /// 웹에서 Drive/Sheets OAuth 권한을 사용자에게 요청한다.
  /// 모바일에서는 이미 로그인 과정에서 권한이 처리되므로 true를 반환한다.
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
