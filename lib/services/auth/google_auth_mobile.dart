import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'google_auth_stub.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// Google 네이티브 로그인 세션에서 요청 시점마다 액세스 토큰을 가져오는
/// 모바일 전용 AuthClient.
///
/// 모바일 Google Sign-In SDK가 로그인 세션을 기기에 안전하게 유지하므로
/// access token/refresh token을 앱 저장소에 직접 보관하지 않는다.
class _MobileGoogleAuthClient extends http.BaseClient implements AuthClient {
  final GoogleSignInAccount _account;
  final List<String> _scopes;
  final http.Client _innerClient;

  AccessCredentials _credentials;
  Future<void>? _refreshing;

  _MobileGoogleAuthClient._(
    this._account,
    this._scopes,
    this._innerClient,
    this._credentials,
  );

  static Future<_MobileGoogleAuthClient> create({
    required GoogleSignInAccount account,
    required List<String> scopes,
  }) async {
    final authentication = await account.authentication;
    final credentials = _toCredentials(authentication, scopes);

    return _MobileGoogleAuthClient._(
      account,
      scopes,
      http.Client(),
      credentials,
    );
  }

  static AccessCredentials _toCredentials(
    GoogleSignInAuthentication authentication,
    List<String> scopes,
  ) {
    final token = authentication.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('AccessToken을 가져오지 못했습니다.');
    }

    return AccessCredentials(
      AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      scopes,
      idToken: authentication.idToken,
    );
  }

  @override
  AccessCredentials get credentials => _credentials;

  Future<void> _refreshCredentials() async {
    final activeRefresh = _refreshing;
    if (activeRefresh != null) {
      return activeRefresh;
    }

    final refresh = _loadLatestCredentials();
    _refreshing = refresh;

    try {
      await refresh;
    } finally {
      if (identical(_refreshing, refresh)) {
        _refreshing = null;
      }
    }
  }

  Future<void> _loadLatestCredentials() async {
    // Android/iOS Google Sign-In SDK가 저장된 로그인 세션을 이용해
    // 만료된 access token을 사용자 팝업 없이 갱신한다.
    final authentication = await _account.authentication;
    _credentials = _toCredentials(authentication, _scopes);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _refreshCredentials();
    request.headers['Authorization'] =
        'Bearer ${_credentials.accessToken.data}';
    return _innerClient.send(request);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}

class GoogleAuthMobileService extends GoogleAuthService {
  @override
  final List<String> scopes;
  late final GoogleSignIn _googleSignIn;

  GoogleAuthMobileService(this.scopes) : super(scopes) {
    _googleSignIn = GoogleSignIn(scopes: scopes);
  }

  @override
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _googleSignIn.onCurrentUserChanged;

  Future<GoogleSignInAccount?> signIn() async {
    return await _googleSignIn.signIn();
  }

  Future<GoogleSignInAccount?> signInSilently() async {
    return await _googleSignIn.signInSilently();
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    try {
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;

      // 최초 로그인 이후에는 네이티브 SDK가 저장한 세션을 복원한다.
      // 세션이 만료되거나 사용자가 권한을 철회한 경우에만 로그인을 요청한다.
      googleUser ??= await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        throw StateError('구글 로그인 실패 또는 사용자가 취소했습니다.');
      }

      return await _MobileGoogleAuthClient.create(
        account: googleUser,
        scopes: scopes,
      );
    } catch (e) {
      AppLogger.i('❌ [Mobile Auth Error] Google Sign-In 실패: $e');
      rethrow;
    }
  }

  Future<AuthClient?> restoreAuthorizedClient() async {
    final user = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently();

    if (user == null) return null;

    return _MobileGoogleAuthClient.create(
      account: user,
      scopes: scopes,
    );
  }

  Future<bool> canAccessScopes() async {
    return _googleSignIn.currentUser != null ||
        await _googleSignIn.signInSilently() != null;
  }

  Future<bool> requestAuthorization() async {
    final user = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently();
    return user != null;
  }

  Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthMobileService(scopes);
