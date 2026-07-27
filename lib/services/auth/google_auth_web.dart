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

  // 💡 추가: _googleSignIn의 currentUser 반환
  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    // 1. 이미 메모리에 계정 및 세션이 살아있고 Client 생성이 가능한지 확인
    if (_googleSignIn.currentUser != null) {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        return client;
      }
    }

    // 2. 만약 기존 세션으로 client 생성이 안 된다면 (또는 최초 로그인 시)
    // FedCM 자동 인증에 의존하지 않고, 사용자가 직접 권한을 승인할 수 있도록 signIn() 호출
    try {
      // 이미 진행 중인 silent 세션 정리 후 수동 로그인 팝업 호출
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