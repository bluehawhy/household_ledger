// google_auth.dart
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

import 'google_auth_stub.dart' hide getGoogleAuthService;
import 'google_auth_stub.dart'
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

  /// 인증된 클라이언트만 발급해주고, 클라이언트의 생명주기(close) 관리는 호출자에게 위임합니다.
  Future<AuthClient> getClient() async {
    return await _authService.getAuthenticatedClient();
  }
}