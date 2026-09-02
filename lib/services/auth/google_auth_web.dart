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

  /// 6.x 웹에서는 Google Identity Services가 렌더링한 버튼으로
  /// interactive sign-in을 시작한다.
  Future<GoogleSignInAccount?> signIn() async {
    return await _googleSignIn.signIn();
  }

  /// 웹의 인증(Authentication) 세션만 복원한다.
  /// Drive/Sheets OAuth 권한(Authorization)은 별도로 확인한다.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      AppLogger.i('❌ [Web Auth Error] 자동 로그인 복원 실패: $e');
      return null;
    }
  }

  /// 현재 인증된 계정이 요청된 Drive/Sheets scope를 사용할 수 있는지 확인한다.
  Future<bool> canAccessScopes() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;
    return await _googleSignIn.canAccessScopes(scopes);
  }

  /// Drive/Sheets OAuth 권한을 사용자 동작으로 요청한다.
  Future<bool> requestAuthorization() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return false;

    try {
      return await _googleSignIn.requestScopes(scopes);
    } catch (e) {
      AppLogger.i('❌ [Web Auth Error] Google API 권한 요청 실패: $e');
      return false;
    }
  }

  /// 이미 인증(Authentication) + 권한(Authorization)이 완료된 상태에서
  /// googleapis용 AuthClient를 생성한다.
  ///
  /// 이 메서드에서는 로그인/권한 요청을 수행하지 않는다.
  /// 호출 전에 canAccessScopes() 또는 requestAuthorization()으로
  /// API 권한 상태를 확인해야 한다.
  @override
  Future<AuthClient> getAuthenticatedClient() async {
    final account = _googleSignIn.currentUser;

    if (account == null) {
      throw Exception('Google 로그인 세션이 없습니다.');
    }

    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        AppLogger.i('[AUTH] Google API 인증 클라이언트 생성 성공');
        return client;
      }
    } catch (e) {
      AppLogger.i('[AUTH] Google API 인증 클라이언트 생성 실패: $e');
    }

    throw Exception('Google API 인증 클라이언트를 생성하지 못했습니다.');
  }
}
