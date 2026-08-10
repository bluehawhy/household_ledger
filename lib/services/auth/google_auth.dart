//google_auth.dart

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

  // 💡 모바일 환경일 때만 모바일 서비스의 signInSilently() 실행
  Future<dynamic> signInSilently() async {
    try {
      return await (_authService as dynamic).signInSilently();
    } catch (_) {
      return currentUser;
    }
  }

  // 💡 모바일 환경일 때만 모바일 서비스의 signOut() 실행
  Future<void> signOut() async {
    try {
      await (_authService as dynamic).signOut();
    } catch (_) {}
  }
}



