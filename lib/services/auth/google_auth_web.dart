// google_auth_web.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:household_ledger/services/utils/app_logger.dart';
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

  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged;

  Future<GoogleSignInAccount?> signIn() async {
    return await _googleSignIn.signIn();
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      AppLogger.i('❌ [Web Auth Error] 자동 로그인 복원 실패: $e');
      return null;
    }
  }

  Future<bool> canAccessScopes() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      final result = await _googleSignIn.canAccessScopes(scopes);
      AppLogger.i('[AUTH] Web API scope 권한 상태: $result');
      return result;
    } catch (e) {
      AppLogger.i('[AUTH] Web API scope 권한 확인 실패: $e');
      return false;
    }
  }

  Future<bool> requestAuthorization() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      final result = await _googleSignIn.requestScopes(scopes);
      AppLogger.i('[AUTH] Web API scope 권한 요청 결과: $result');
      return result;
    } catch (e) {
      AppLogger.i('❌ [Web Auth Error] Google API 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      throw Exception('Google 로그인 세션이 없습니다.');
    }

    if (!await canAccessScopes()) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        AppLogger.i('[AUTH] Google API 인증 클라이언트 생성 성공');
        return client;
      }
    } catch (e) {
      AppLogger.i('[AUTH] Google API 인증 클라이언트 생성 실패: $e');
      rethrow;
    }

    throw Exception('Google API 인증 클라이언트를 생성하지 못했습니다.');
  }
}
