import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:household_ledger/services/utils/app_logger.dart';
import 'app_account.dart';
import 'google_auth_stub.dart';
import 'web_account_store.dart';
import 'web_token_store.dart';

class _InvalidWebToken implements Exception {}

GoogleAuthWebService? _sharedService;
GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    _sharedService ??= GoogleAuthWebService(scopes);

class GoogleAuthWebService implements GoogleAuthService {
  @override
  final List<String> scopes;
  final GoogleSignIn _googleSignIn;
  final GoogleSignInPlatform _platform;
  final WebAccountStore _store;
  final WebTokenStore _tokenStore;
  final DateTime Function() _now;
  final http.Client Function() _httpClient;
  final _changes = StreamController<AppAccount?>.broadcast();
  late final StreamSubscription<GoogleSignInAccount?> _subscription;
  AppAccount? _account;
  AccessCredentials? _credentials;
  Future<void> _writes = Future.value();
  int _generation = 0;
  bool _signingOut = false;
  bool _restoreAttempted = false;
  Future<bool>? _restoring;

  GoogleAuthWebService(
    this.scopes, {
    GoogleSignIn? googleSignIn,
    GoogleSignInPlatform? platform,
    WebAccountStore? store,
    WebTokenStore? tokenStore,
    DateTime Function()? now,
    http.Client Function()? httpClient,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: scopes),
       _platform = platform ?? GoogleSignInPlatform.instance,
       _store = store ?? WebAccountStore(),
       _tokenStore = tokenStore ?? WebTokenStore(now: now),
       _now = now ?? DateTime.now,
       _httpClient = httpClient ?? http.Client.new {
    _account = AppAccount.fromUser(_googleSignIn.currentUser);
    _subscription = _googleSignIn.onCurrentUserChanged.listen((user) {
      if (user == null || _signingOut) return;
      unawaited(_remember(AppAccount.fromUser(user)!, _generation));
    });
  }

  @override
  AppAccount? get currentUser => _account;
  Stream<AppAccount?> get onCurrentUserChanged => _changes.stream;

  Future<void> _remember(AppAccount account, int generation) async {
    if (generation != _generation || _signingOut) return;
    if (_account?.id != account.id) {
      _credentials = null;
      _tokenStore.clear();
      _restoreAttempted = false;
    }
    _account = account;
    // Serialize persistence against logout, including events arriving mid-write.
    _writes = _writes.then((_) => _store.save(account)).catchError((
      Object error,
    ) {
      AppLogger.i('[AUTH] 계정 기억 저장 실패: ${error.runtimeType}');
    });
    await _writes;
    if (generation == _generation && !_signingOut) _changes.add(account);
  }

  Future<AppAccount?> signIn() async {
    final generation = _generation;
    final user = await _googleSignIn.signIn();
    if (user != null) await _remember(AppAccount.fromUser(user)!, generation);
    return _account;
  }

  Future<AppAccount?> signInSilently() async {
    final generation = _generation;
    // Restore app identity first; the separate API grant is validated on demand.
    await _writes;
    AppAccount? remembered;
    try {
      if (await _store.isLoggedOut()) {
        _tokenStore.clear();
        return null;
      }
      remembered = await _store.read();
    } catch (error) {
      AppLogger.i('[AUTH] 저장된 계정 읽기 실패: ${error.runtimeType}');
    }
    if (generation != _generation || _signingOut) return null;
    if (remembered != null) {
      if (_account?.id != remembered.id) {
        _credentials = null;
        _restoreAttempted = false;
      }
      _account = remembered;
      return remembered;
    }
    try {
      final user = await _googleSignIn.signInSilently();
      if (user != null) await _remember(AppAccount.fromUser(user)!, generation);
    } catch (error) {
      AppLogger.i('[AUTH] Google 자동 로그인 복원 실패: ${error.runtimeType}');
    }
    return _account;
  }

  Future<void> signOut() async {
    _generation++;
    _signingOut = true;
    _account = null;
    _credentials = null;
    _tokenStore.clear();
    _restoreAttempted = false;
    try {
      _writes = _writes.then((_) => _store.clear());
      await _writes;
      // Signing out must not revoke the user's existing Drive/Sheets consent.
      await _googleSignIn.signOut();
    } finally {
      _changes.add(null);
      _signingOut = false;
    }
  }

  Future<bool> canAccessScopes() async {
    if (_account == null || _signingOut) return false;
    if (_credentials != null) {
      if (_credentials!.accessToken.expiry.isAfter(_now().toUtc())) return true;
      _credentials = null;
      _tokenStore.clear();
    }
    if (_restoreAttempted) return false;
    // GIS's canAccessScopes compares against its own in-memory token response,
    // which is empty after reload. Validate the cached token with Google instead.
    if (_restoring != null) return _restoring!;
    final pending = _restoreToken();
    _restoring = pending;
    try {
      return await pending;
    } finally {
      if (identical(_restoring, pending)) _restoring = null;
    }
  }

  Future<({String accountId, DateTime expiry})> _inspectToken(
    String token,
  ) async {
    final startedAt = _now().toUtc();
    final client = _httpClient();
    try {
      final response = await client
          .get(
            Uri.https('oauth2.googleapis.com', '/tokeninfo', {
              'access_token': token,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 400 || response.statusCode == 401) {
        throw _InvalidWebToken();
      }
      if (response.statusCode != 200) {
        throw StateError('Google 권한 확인에 일시적으로 실패했습니다. 다시 시도해 주세요.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final seconds = int.tryParse('${data['expires_in']}') ?? 0;
      final granted = (data['scope'] as String? ?? '').split(' ').toSet();
      if (seconds <= 30 ||
          data['sub'] is! String ||
          _tokenStore.clientId == null ||
          data['aud'] != _tokenStore.clientId ||
          !granted.containsAll(scopes)) {
        throw _InvalidWebToken();
      }
      // Account for request latency and clock changes; never infer a fresh hour
      // from a page reload. Google's remaining lifetime is authoritative.
      final lifetime = seconds > 3600 ? 3600 : seconds;
      return (
        accountId: data['sub'] as String,
        expiry: startedAt.add(Duration(seconds: lifetime - 30)),
      );
    } on _InvalidWebToken {
      rethrow;
    } catch (_) {
      // ClientException may include a URL containing the token. Never pass it
      // through to the UI/logger.
      throw StateError('Google 권한 확인에 일시적으로 실패했습니다. 다시 시도해 주세요.');
    } finally {
      client.close();
    }
  }

  Future<bool> _restoreToken() async {
    final generation = _generation;
    final accountId = _account!.id;
    final cached = _tokenStore.read(accountId);
    if (cached == null) {
      _restoreAttempted = true;
      return false;
    }
    try {
      final verified = await _inspectToken(cached.token);
      if (generation != _generation || _account?.id != accountId) return false;
      if (verified.accountId != accountId) throw _InvalidWebToken();
      final expiry = verified.expiry.isBefore(cached.expiresAt)
          ? verified.expiry
          : cached.expiresAt;
      _credentials = AccessCredentials(
        AccessToken('Bearer', cached.token, expiry),
        null,
        scopes,
      );
      _tokenStore.save(CachedWebToken(accountId, cached.token, expiry));
      _restoreAttempted = true;
      return true;
    } on _InvalidWebToken {
      if (generation == _generation && _account?.id == accountId) {
        _tokenStore.clear();
        _restoreAttempted = true;
      }
      return false;
    }
    // Network/5xx failures propagate to the retry screen, preserving the cache.
  }

  Future<AuthClient?> restoreAuthorizedClient() async =>
      await canAccessScopes() ? getAuthenticatedClient() : null;

  Future<bool> requestAuthorization() async {
    if (_account == null) return false;
    final generation = ++_generation;
    _restoring = null;
    _credentials = null;
    _tokenStore.clear();
    _restoreAttempted = true;
    try {
      // A remembered profile is not an SDK login. requestScopes works without
      // currentUser; getTokens reads only the fresh, in-memory GIS response.
      final granted = await _googleSignIn.requestScopes([
        ...scopes,
        'openid',
        'email',
        'profile',
      ]);
      if (!granted || generation != _generation) return false;
      final token = (await _platform.getTokens(
        email: _account!.email,
      )).accessToken;
      if (token == null) return false;
      final tokenInfo = await _inspectToken(token);
      final client = _httpClient();
      late AppAccount verified;
      try {
        final response = await client.get(
          Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode != 200) return false;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['email_verified'] != true ||
            data['sub'] is! String ||
            data['email'] is! String) {
          return false;
        }
        verified = AppAccount(
          id: data['sub'] as String,
          email: data['email'] as String,
          displayName: data['name'] as String?,
          photoUrl: data['picture'] as String?,
        );
      } finally {
        client.close();
      }
      if (generation != _generation) return false;
      if (tokenInfo.accountId != verified.id) return false;
      // The user may choose a different account in Google's authorization popup.
      // Use Google's verified identity, never the cached email, for the ledger.
      await _remember(verified, generation);
      if (generation != _generation) return false;
      _credentials = AccessCredentials(
        AccessToken('Bearer', token, tokenInfo.expiry),
        null,
        scopes,
      );
      _tokenStore.save(CachedWebToken(verified.id, token, tokenInfo.expiry));
      _restoreAttempted = true;
      return true;
    } catch (error) {
      AppLogger.i('[AUTH] Google API 권한 연결 실패: ${error.runtimeType}');
      return false;
    }
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    if (!await canAccessScopes()) {
      throw StateError('Google Drive와 Sheets 권한 연결이 필요합니다.');
    }
    return authenticatedClient(_httpClient(), _credentials!);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _writes;
    await _changes.close();
  }
}
