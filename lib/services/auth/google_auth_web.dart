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

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static bool _initialized = false;

  GoogleAuthWebService(this.scopes);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize();
    _initialized = true;
  }

  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signInSilently() async {
    await _ensureInitialized();
    try {
      await _googleSignIn.attemptLightweightAuthentication();
      return _googleSignIn.currentUser;
    } catch (e) {
      print('❌ [Web Auth Error] 자동 로그인 복원 실패: $e');
      return null;
    }
  }

  Future<bool> requestAuthorization() async {
    await _ensureInitialized();
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      final authorization = await account.authorizationClient.authorizeScopes(scopes);
      return authorization.accessToken.isNotEmpty;
    } catch (e) {
      print('❌ [Web Auth Error] Google API 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    await _ensureInitialized();

    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await signInSilently();

    if (account == null) {
      throw Exception('Google 로그인 세션이 없습니다.');
    }

    // 새로고침 후에도 기존에 승인된 OAuth grant가 있으면
    // authorizationForScopes()가 사용자 interaction 없이 access token을 복원한다.
    final authorization =
        await account.authorizationClient.authorizationForScopes(scopes);

    if (authorization == null || authorization.accessToken.isEmpty) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    return authorization.authClient(scopes: scopes);
  }
}
