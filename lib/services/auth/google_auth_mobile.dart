// google_auth_mobile.dart
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'google_auth_stub.dart';


class GoogleAuthMobileService extends GoogleAuthService {
  @override
  final List<String> scopes;
  late final GoogleSignIn _googleSignIn;

  GoogleAuthMobileService(this.scopes) : super(scopes) {
    _googleSignIn = GoogleSignIn(
      scopes: scopes,
      clientId: Platform.isIOS
          ? 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com'
          : null,
    );
  }

  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  // 💡 모바일 전용 Silent Sign-In 메서드 (공통 인터페이스엔 명시 X)
  Future<GoogleSignInAccount?> signInSilently() async {
    return await _googleSignIn.signInSilently();
  }

  // 💡 모바일 전용 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    try {
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception("구글 로그인 실패 또는 사용자가 취소했습니다.");
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
    } catch (e) {
      print("❌ [Mobile Auth Error] Google Sign-In 실패: $e");
      rethrow;
    }
  }

  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthMobileService(scopes);