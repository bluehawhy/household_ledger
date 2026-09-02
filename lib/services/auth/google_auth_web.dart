// google_auth_web.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
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

    // 이미 승인된 scope라면 사용자 interaction 없이 기존 authorization을 복원한다.
    final authorization = await account.authorizationClient.authorizationForScopes(scopes);

    if (authorization == null || authorization.accessToken.isEmpty) {
      throw Exception('Google API 권한 승인이 필요합니다.');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer ${authorization.accessToken}',
    };

    return AuthClient(
      _GoogleAuthHttpClient(headers),
      credentials: AccessCredentials(
        AccessToken(
          'Bearer',
          authorization.accessToken,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null,
        scopes,
      ),
    );
  }
}

class _GoogleAuthHttpClient extends AuthClient {
  final Map<String, String> _headers;

  _GoogleAuthHttpClient(this._headers);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    request.headers.addAll(_headers);
    return request.send();
  }

  @override
  void close() {}
}
