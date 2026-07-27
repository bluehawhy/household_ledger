// google_auth_stub.dart
import 'package:google_sign_in/google_sign_in.dart'; // 💡 추가
import 'package:googleapis_auth/auth_io.dart';

abstract class GoogleAuthService {
  final List<String> scopes;
  GoogleAuthService(this.scopes);

  // 💡 추가: 현재 로그인된 계정 정보를 가져오는 getter
  GoogleSignInAccount? get currentUser;

  Future<AuthClient> getAuthenticatedClient();
}

GoogleAuthService getGoogleAuthService(List<String> scopes) {
  throw UnsupportedError('현재 플랫폼을 지원하지 않습니다.');
}