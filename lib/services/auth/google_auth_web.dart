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

  /// 사용자가 로그인 버튼을 눌렀을 때만 interactive Google 로그인 popup을 연다.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      print('❌ [Web Auth Error] Google 로그인 실패: $e');
      rethrow;
    }
  }

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
