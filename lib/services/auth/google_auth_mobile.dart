import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'google_auth_stub.dart';

class GoogleAuthServiceAndroid extends GoogleAuthService {
  late final GoogleSignIn _googleSignIn;

  GoogleAuthServiceAndroid(super.scopes) {
    _googleSignIn = GoogleSignIn(scopes: scopes);
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
    googleUser ??= await _googleSignIn.signIn();

    if (googleUser == null) {
      throw Exception("구글 로그인 실패 또는 취소되었습니다.");
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final String? accessTokenStr = googleAuth.accessToken;

    if (accessTokenStr == null) {
      throw Exception("AccessToken을 가져오지 못했습니다.");
    }

    final accessToken = AccessToken(
      'Bearer',
      accessTokenStr,
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    final credentials = AccessCredentials(
      accessToken,
      null,
      scopes,
      idToken: googleAuth.idToken,
    );

    return authenticatedClient(http.Client(), credentials);
  }
}

// 팩토리 함수 연동
GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthServiceAndroid(scopes);