import 'package:googleapis_auth/auth_io.dart';

abstract class GoogleAuthService {
  final List<String> scopes;
  GoogleAuthService(this.scopes);

  Future<AuthClient> getAuthenticatedClient();
}

// 조건부 임포트 시 조건이 맞지 않을 때 호출될 기본 스텁
GoogleAuthService getGoogleAuthService(List<String> scopes) {
  throw UnsupportedError('현재 플랫폼을 지원하지 않습니다.');
}