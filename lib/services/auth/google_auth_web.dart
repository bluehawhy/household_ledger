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

  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      print('❌ [Web Auth Error] 자동 로그인 복원 실패: $e');
      return null;
    }
  }

  Future<bool> canAccessScopes() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;
    return await _googleSignIn.canAccessScopes(scopes);
  }

  Future<bool> requestAuthorization() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      return await _googleSignIn.requestScopes(scopes);
    } catch (e) {
      print('❌ [Web Auth Error] Google API 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await signInSilently();

    if (account == null) {
      throw Exception('Google 로그인 세션이 없습니다.');
    }

    // 기존에 승인된 scope가 있으면 access token을 다시 가져온다.
    // 새로고침 후 canAccessScopes()가 일시적으로 false를 반환하는 경우에도
    // 실제 OAuth authorization 상태를 먼저 확인할 수 있도록 authenticatedClient()
    // 를 시도한다.
    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        return client;
      }
    } catch (e) {
      print('⚠️ [Web Auth] 기존 AuthClient 복원 실패: $e');
    }

    // 기존 authorization을 복원하지 못한 경우에만 현재 scope 상태를 확인한다.
    final bool authorized = await _googleSignIn.canAccessScopes(scopes);
    if (!authorized) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    final client = await _googleSignIn.authenticatedClient();
    if (client != null) {
      return client;
    }

    throw Exception('Google API 인증 클라이언트를 생성하지 못했습니다.');
  }
}
