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

  /// 새로고침 후 기존 Google API 인증 상태를 최대한 자동으로 복원한다.
  ///
  /// 1. 현재 Google 계정의 API scope 승인 상태를 확인한다.
  /// 2. 승인 상태가 확인되면 기존 OAuth client/token 획득을 시도한다.
  /// 3. Web의 새 browsing session에서는 canAccessScopes()가 false일 수 있으므로,
  ///    false여도 authenticatedClient()를 한 번 더 시도한다.
  /// 4. 자동 획득이 실패하면 호출자가 사용자 동작으로 requestScopes()를 수행한다.
  ///
  /// requestScopes()는 브라우저 사용자 제스처가 필요할 수 있으므로 여기서는 호출하지 않는다.
  Future<AuthClient?> restoreAuthorizedClient() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      AppLogger.i('[AUTH] Web API 자동 복원: Google 계정 없음');
      return null;
    }

    try {
      final authorized = await canAccessScopes();
      AppLogger.i('[AUTH] Web API 기존 scope 승인 상태 확인: $authorized');

      if (authorized) {
        final client = await _googleSignIn.authenticatedClient();
        if (client != null) {
          AppLogger.i('[AUTH] Web Google API 인증 클라이언트 자동 복원 성공');
          return client;
        }
      }

      // 새 browsing session에서는 canAccessScopes()가 false여도
      // Google이 기존 승인 상태를 바탕으로 OAuth client/token을 제공할 수 있다.
      AppLogger.i('[AUTH] scope 상태와 관계없이 기존 OAuth client/token 자동 획득 재시도');
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        AppLogger.i('[AUTH] Web Google API 인증 클라이언트 자동 복원 성공');
        return client;
      }
    } catch (e) {
      AppLogger.i('[AUTH] Web Google API 인증 클라이언트 자동 복원 실패: $e');
    }

    return null;
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

    final authorized = await canAccessScopes();
    if (!authorized) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    final client = await _googleSignIn.authenticatedClient();
    if (client != null) {
      AppLogger.i('[AUTH] Google API 인증 클라이언트 생성 성공');
      return client;
    }

    throw Exception('Google API 인증 클라이언트를 생성하지 못했습니다.');
  }
}
