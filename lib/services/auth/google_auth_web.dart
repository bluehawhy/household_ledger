// google_auth_web.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'google_auth_stub.dart';

GoogleAuthService getGoogleAuthService(List<String> scopes) {
  return GoogleAuthWebService(scopes);
}

class GoogleAuthWebService implements GoogleAuthService {
  @override
  final List<String> scopes;

  static GoogleSignIn? _sharedGoogleSignIn;

  GoogleAuthWebService(this.scopes) {
    _sharedGoogleSignIn ??= GoogleSignIn(scopes: scopes);
  }

  GoogleSignIn get _googleSignIn => _sharedGoogleSignIn!;

  // GoogleSignIn의 현재 계정 반환
  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// 웹 새로고침 후 Google 로그인 상태를 자동 복원한다.
  ///
  /// google_sign_in 웹 구현은 Google Identity Services(GIS)를 사용하며,
  /// signInSilently()는 사용자에게 별도의 로그인 팝업을 띄우지 않고
  /// 기존 Google 인증 상태를 확인/복원하는 용도로 사용할 수 있다.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      return account;
    } catch (e) {
      print("❌ [Web Auth Error] 자동 로그인 복원 실패: $e");
      return null;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    // 1. 이미 메모리에 계정 및 세션이 살아있고 Client 생성이 가능한지 확인
    if (_googleSignIn.currentUser != null) {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        return client;
      }
    }

    // 2. 기존 세션으로 client 생성이 안 된다면 사용자 로그인 팝업 호출
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account != null) {
        final client = await _googleSignIn.authenticatedClient();
        if (client != null) {
          return client;
        }
      }
    } catch (e) {
      print("❌ [Web Auth Error] 구글 팝업 인증 실패: $e");
    }

    throw Exception('로그인 세션이 만료되었거나 권한 승인이 필요합니다.');
  }
}
