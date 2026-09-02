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

  Future<bool> canAccessScopes() async {
    try {
      return await (_authService as dynamic).canAccessScopes();
    } catch (_) {
      return true;
    }
  }

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
