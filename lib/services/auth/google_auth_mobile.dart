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
    // 💡 iOS / Android 플랫폼별 GoogleSignIn 인스턴스 초기화
    _googleSignIn = GoogleSignIn(
      scopes: scopes,
      // iOS 환경일 경우 필요시 clientId 지정 (GoogleService-Info.plist 설정이 완료되었다면 null로 유지 가능)
      clientId: Platform.isIOS
          ? 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com' // iOS 전용 Client ID 입력
          : null, // Android는 google-services.json 기반으로 동작하므로 null
    );
  }

  // 💡 추상 클래스(GoogleAuthService) 인터페이스 구현
  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    try {
      // 1. 기존 로그인 세션이 있는지 확인 (자동 로그인 시도)
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();

      // 2. 조용히 가져오는 데 실패했다면 팝업 창을 띄워 사용자 인증 진행
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception("구글 로그인 실패 또는 사용자가 취소했습니다.");
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
        null, // RefreshToken은 GoogleSignIn 패키지가 내부 기기 세션으로 관리합니다.
        scopes,
        idToken: googleAuth.idToken,
      );

      return authenticatedClient(http.Client(), credentials);
    } catch (e) {
      print("❌ [Mobile Auth Error] Google Sign-In 실패: $e");
      rethrow;
    }
  }

  // 💡 자동 로그인 세션 유지 여부 확인
  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  // 💡 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthMobileService(scopes);