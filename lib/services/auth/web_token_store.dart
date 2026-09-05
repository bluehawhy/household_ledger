import 'dart:convert';
import 'web_session_storage_stub.dart'
    if (dart.library.html) 'web_session_storage_web.dart'
    as browser;

class CachedWebToken {
  final String accountId;
  final String token;
  final DateTime expiresAt;

  const CachedWebToken(this.accountId, this.token, this.expiresAt);
}

/// Short-lived API credentials survive reloads in this tab only. Never stores
/// refresh tokens or ID tokens, and never extends the original expiry.
class WebTokenStore {
  static const key = 'web_google_access_token_v1';
  final Map<String, String> Function() _storage;
  final DateTime Function() _now;
  final String? clientId;

  WebTokenStore({
    Map<String, String>? storage,
    DateTime Function()? now,
    String? clientId,
  }) : _storage = storage == null ? browser.sessionStorage : (() => storage),
       _now = now ?? DateTime.now,
       clientId = clientId ?? browser.webClientId();

  CachedWebToken? read(String accountId) {
    try {
      final raw = _storage()[key];
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final expiry = DateTime.parse(data['expiresAt'] as String).toUtc();
      if (data['accountId'] != accountId ||
          data['clientId'] != clientId ||
          !expiry.isAfter(_now().toUtc()) ||
          (data['token'] as String).isEmpty) {
        clear();
        return null;
      }
      return CachedWebToken(accountId, data['token'] as String, expiry);
    } catch (_) {
      clear();
      return null;
    }
  }

  void save(CachedWebToken token) {
    try {
      _storage()[key] = jsonEncode({
        'accountId': token.accountId,
        'token': token.token,
        'expiresAt': token.expiresAt.toUtc().toIso8601String(),
        'clientId': clientId,
      });
    } catch (_) {
      // If storage is blocked, the current in-memory grant still works.
    }
  }

  void clear() {
    try {
      _storage().remove(key);
    } catch (_) {}
  }
}
