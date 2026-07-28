import 'package:googleapis_auth/auth_io.dart';

abstract class GoogleAuthService {
  final List<String> scopes;

  GoogleAuthService(this.scopes);

  /// Flutter에서는 GoogleSignInAccount,
  /// CLI에서는 null 또는 다른 객체를 사용할 수 있도록 Object? 사용
  Object? get currentUser;

  Future<AuthClient> getAuthenticatedClient();
}

GoogleAuthService getGoogleAuthService(List<String> scopes) {
  throw UnsupportedError('현재 플랫폼을 지원하지 않습니다.');
}