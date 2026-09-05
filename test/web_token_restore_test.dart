import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/auth/app_account.dart';
import 'package:household_ledger/services/auth/google_auth_web.dart';
import 'package:household_ledger/services/auth/web_account_store.dart';
import 'package:household_ledger/services/auth/web_token_store.dart';

class TokenSdk extends Mock implements GoogleSignIn {}

class TokenPlatform extends Mock implements GoogleSignInPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scopes = ['https://www.googleapis.com/auth/spreadsheets'];
  const account = AppAccount(id: 'alice', email: 'alice@example.com');
  late TokenSdk sdk;
  late TokenPlatform platform;
  late Map<String, String> storage;
  late WebAccountStore accountStore;
  late WebTokenStore tokens;
  late DateTime now;
  late DateTime googleExpiry;
  late int status;
  late int inspections;
  late String googleAccount;
  late String googleAudience;
  late String googleScopes;
  final services = <GoogleAuthWebService>[];

  GoogleAuthWebService newPage() {
    final service = GoogleAuthWebService(
      scopes,
      googleSignIn: sdk,
      platform: platform,
      store: accountStore,
      tokenStore: tokens,
      now: () => now,
      httpClient: () => MockClient((request) async {
        if (request.url.path == '/tokeninfo') {
          inspections++;
          expect(request.url.queryParameters['access_token'], 'access-token');
          return http.Response(
            jsonEncode({
              'sub': googleAccount,
              'aud': googleAudience,
              'scope': googleScopes,
              'expires_in': '${googleExpiry.difference(now).inSeconds}',
            }),
            status,
          );
        }
        expect(request.headers['Authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'sub': 'alice',
            'email': account.email,
            'email_verified': true,
          }),
          200,
        );
      }),
    );
    services.add(service);
    return service;
  }

  Future<void> grant() async {
    final first = newPage();
    await first.signInSilently();
    expect(await first.requestAuthorization(), true);
    expect(tokens.read('alice'), isNotNull);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 9, 5);
    googleExpiry = now.add(const Duration(hours: 1));
    status = 200;
    inspections = 0;
    googleAccount = 'alice';
    googleAudience = 'test-client';
    googleScopes = scopes.join(' ');
    storage = {};
    tokens = WebTokenStore(
      storage: storage,
      clientId: 'test-client',
      now: () => now,
    );
    accountStore = WebAccountStore();
    await accountStore.save(account);
    sdk = TokenSdk();
    platform = TokenPlatform();
    when(() => sdk.currentUser).thenReturn(null);
    when(
      () => sdk.onCurrentUserChanged,
    ).thenAnswer((_) => const Stream.empty());
    when(() => sdk.signOut()).thenAnswer((_) async => null);
    when(() => sdk.requestScopes(any())).thenAnswer((_) async => true);
    when(() => platform.getTokens(email: any(named: 'email'))).thenAnswer(
      (_) async => GoogleSignInTokenData(accessToken: 'access-token'),
    );
  });

  tearDown(() async {
    for (final service in services) {
      await service.dispose();
    }
    services.clear();
  });

  test(
    'reload reuses grant without GIS memory and never extends original expiry',
    () async {
      await grant();
      final originalExpiry = tokens.read('alice')!.expiresAt;
      now = now.add(const Duration(minutes: 10));
      final reloaded = newPage();
      await reloaded.signInSilently();
      expect(await reloaded.canAccessScopes(), true);
      final client = await reloaded.getAuthenticatedClient();
      expect(client.credentials.accessToken.data, 'access-token');
      expect(client.credentials.accessToken.expiry, originalExpiry);
      client.close();
      expect(tokens.read('alice')!.expiresAt, originalExpiry);
      verify(
        () => sdk.requestScopes(any()),
      ).called(1); // Only the original grant.
      verifyNever(
        () =>
            sdk.canAccessScopes(any(), accessToken: any(named: 'accessToken')),
      );
    },
  );

  test(
    'concurrent restoration inspects once and subsequent requests use memory',
    () async {
      await grant();
      final page = newPage();
      await page.signInSilently();
      final before = inspections;
      expect(
        await Future.wait([page.canAccessScopes(), page.canAccessScopes()]),
        [true, true],
      );
      expect(await page.canAccessScopes(), true);
      expect(inspections, before + 1);
    },
  );

  test(
    'expired token is removed without a Google prompt or network request',
    () async {
      await grant();
      now = now.add(const Duration(hours: 1));
      final page = newPage();
      await page.signInSilently();
      final before = inspections;
      expect(await page.canAccessScopes(), false);
      expect(inspections, before);
      expect(storage, isEmpty);
      expect(page.currentUser?.id, 'alice');
    },
  );

  test('revoked token is forgotten but remembered login stays', () async {
    await grant();
    status = 400;
    final page = newPage();
    await page.signInSilently();
    expect(await page.canAccessScopes(), false);
    expect(storage, isEmpty);
    expect((await accountStore.read())?.id, 'alice');
  });

  test(
    'transient Google error preserves cache and can be retried without consent',
    () async {
      await grant();
      status = 503;
      final page = newPage();
      await page.signInSilently();
      await expectLater(page.canAccessScopes(), throwsStateError);
      expect(tokens.read('alice'), isNotNull);
      status = 200;
      expect(await page.canAccessScopes(), true);
      verify(() => sdk.requestScopes(any())).called(1);
    },
  );

  for (final invalid in ['account', 'audience', 'scope']) {
    test('rejects cached token with a different $invalid', () async {
      await grant();
      if (invalid == 'account') googleAccount = 'bob';
      if (invalid == 'audience') googleAudience = 'another-client';
      if (invalid == 'scope') googleScopes = 'openid';
      final page = newPage();
      await page.signInSilently();
      expect(await page.canAccessScopes(), false);
      expect(storage, isEmpty);
    });
  }

  test(
    'logout clears session token and new tabs do not share the token store',
    () async {
      await grant();
      expect(
        WebTokenStore(
          storage: {},
          clientId: 'test-client',
          now: () => now,
        ).read('alice'),
        isNull,
      );
      final page = newPage();
      await page.signInSilently();
      await page.signOut();
      expect(storage, isEmpty);
      expect(await page.canAccessScopes(), false);
    },
  );
}
