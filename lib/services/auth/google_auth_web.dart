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

  /// 웹 새로고침 후 Google 로그인 상태를 자동 복원한다.
  ///
  /// 웹에서는 Authentication과 OAuth Authorization이 분리되어 있으므로
  /// signInSilently()는 계정 로그인 상태만 복원한다.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (e) {
      print('❌ [Web Auth Error] 자동 로그인 복원 실패: $e');
      return null;
    }
  }

  /// 현재 로그인 계정이 Drive/Sheets scope에 접근할 수 있는지 확인한다.
  Future<bool> canAccessScopes() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      return false;
    }

    return await _googleSignIn.canAccessScopes(scopes);
  }

  /// 사용자 클릭으로 Drive/Sheets 권한을 요청한다.
  ///
  /// 웹에서는 추가 OAuth scope 요청이 사용자 interaction에서 시작되어야 한다.
  Future<bool> requestAuthorization() async {
    final account = _googleSignIn.currentUser;
    if (account == null) {
      return false;
    }

    try {
      return await _googleSignIn.requestScopes(scopes);
    } catch (e) {
      print('❌ [Web Auth Error] Google API 권한 요청 실패: $e');
      return false;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    // Authentication 계정이 없으면 먼저 기존 Google 세션을 복원한다.
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await signInSilently();

    if (account == null) {
      throw Exception('Google 로그인 세션이 없습니다.');
    }

    // 웹에서는 signIn/signInSilently가 Drive/Sheets OAuth scope를
    // 자동으로 승인하지 않는다. 이미 승인된 scope인지 먼저 확인한다.
    final bool authorized = await _googleSignIn.canAccessScopes(scopes);
    if (!authorized) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    // 필요한 scope가 승인된 경우에만 googleapis AuthClient를 생성한다.
    final client = await _googleSignIn.authenticatedClient();
    if (client != null) {
      return client;
    }

    throw Exception('Google API 인증 클라이언트를 생성하지 못했습니다.');
  }
}
