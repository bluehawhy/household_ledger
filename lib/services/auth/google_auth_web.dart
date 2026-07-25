// google_auth_web.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'google_auth_stub.dart';

GoogleAuthService getGoogleAuthService(List<String> scopes) {
  return GoogleAuthWebService(scopes);
}

class GoogleAuthWebService implements GoogleAuthService {
  final List<String> scopes;
  late final GoogleSignIn _googleSignIn;

  GoogleAuthWebService(this.scopes) {
    _googleSignIn = GoogleSignIn(scopes: scopes);
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    // 1. 먼저 기존 로그인 세션이 있는지 확인 (자동 로그인)
    GoogleSignInAccount? account = await _googleSignIn.signInSilently();

    // 2. 이미 로그인되어 있다면 AuthClient 생성 후 반환
    if (account != null) {
      final AuthClient? client = await _googleSignIn.authenticatedClient();
      if (client != null) return client;
    }

    // 3. 로그인되어 있지 않다면 에러를 던져 UI에서 공식 구글 버튼을 누르도록 유도
    throw Exception('로그인이 필요합니다. 웹에서는 구글 공식 로그인 버튼을 이용해 주세요.');
  }
}