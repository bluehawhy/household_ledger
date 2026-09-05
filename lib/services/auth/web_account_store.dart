import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_account.dart';

/// Remembers the app's selected account, not a Google credential or API grant.
/// Storage is scoped to the browser origin. Clearing site data forgets it.
class WebAccountStore {
  static const key = 'web_google_account_v1';

  Future<bool> isLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool('is_logged_in') == false;
  }

  Future<AppAccount?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('is_logged_in') == false) return null;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final account = AppAccount.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (account.id.isEmpty || account.email.isEmpty) {
        throw const FormatException();
      }
      return account;
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> save(AppAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'id': account.id,
        'email': account.email,
        'displayName': account.displayName,
        'photoUrl': account.photoUrl,
      }),
    );
    await prefs.setBool('is_logged_in', true);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', false);
    await prefs.remove(key);
  }
}
