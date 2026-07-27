// google_auth_mobile.dart

import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'google_auth_stub.dart';

class GoogleAuthServiceAndroid extends GoogleAuthService {
  late final GoogleSignIn _googleSignIn;

  GoogleAuthServiceAndroid(super.scopes) {
    _googleSignIn = GoogleSignIn(
      scopes: scopes,
      clientId: Platform.isIOS
          ? 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com'
          : null,
    );
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    try {
      // 1. 먼저 기존 로그인 세션이 있는지 확인 (자동 로그인 시도)
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();

      // 2. 조용히 가져오는 데 실패했다면 그때 사용자 팝업 창을 띄움
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception("구글 로그인 실패 또는 취소되었습니다.");
      }

      // 3. 최신 인증 정보(AccessToken, idToken) 획득
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? accessTokenStr = googleAuth.accessToken;

      if (accessTokenStr == null) {
        throw Exception("AccessToken을 가져오지 못했습니다.");
      }

      final accessToken = AccessToken(
        'Bearer',
        accessTokenStr,
        // UTC 시간 기준으로 1시간 만료 설정
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      final credentials = AccessCredentials(
        accessToken,
        null, // RefreshToken은 GoogleSignIn 패키지가 내부적으로 기기 세션으로 관리합니다.
        scopes,
        idToken: googleAuth.idToken,
      );

      return authenticatedClient(http.Client(), credentials);
    } catch (e) {
      print("Google Sign-In Error: $e");
      rethrow;
    }
  }

  // 💡 앱이 켜질 때 자동 로그인 세션이 살아있는지 체크하는 메서드 (필요시 사용)
  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  // 💡 로그아웃 메서드
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthServiceAndroid(scopes);