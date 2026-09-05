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

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockPlatform extends Mock implements GoogleSignInPlatform {}

class MockGoogleAccount extends Mock implements GoogleSignInAccount {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scopes = ['https://www.googleapis.com/auth/spreadsheets'];
  const alice = AppAccount(
    id: 'alice-id',
    email: 'alice@example.com',
    displayName: 'Alice',
  );
  late MockGoogleSignIn sdk;
  late MockPlatform platform;
  late StreamController<GoogleSignInAccount?> sdkEvents;
  late GoogleAuthWebService service;
  late WebAccountStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sdk = MockGoogleSignIn();
    platform = MockPlatform();
    sdkEvents = StreamController<GoogleSignInAccount?>.broadcast();
    when(() => sdk.currentUser).thenReturn(null);
    when(() => sdk.onCurrentUserChanged).thenAnswer((_) => sdkEvents.stream);
    when(() => sdk.signInSilently()).thenAnswer((_) async => null);
    when(() => sdk.signOut()).thenAnswer((_) async => null);
    store = WebAccountStore();
    service = GoogleAuthWebService(
      scopes,
      googleSignIn: sdk,
      platform: platform,
      store: store,
      tokenStore: WebTokenStore(storage: {}, clientId: 'test-client'),
      httpClient: () => MockClient((request) async {
        if (request.url.path == '/tokeninfo') {
          return http.Response(
            jsonEncode({
              'sub': 'bob-id',
              'aud': 'test-client',
              'scope': scopes.join(' '),
              'expires_in': '3600',
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer fresh-google-token');
        return http.Response(
          jsonEncode({
            'sub': 'bob-id',
            'email': 'bob@example.com',
            'email_verified': true,
            'name': 'Bob',
          }),
          200,
        );
      }),
    );
  });

  tearDown(() async {
    await service.dispose();
    await sdkEvents.close();
  });

  test(
    'Google login saves only profile fields before notifying the UI',
    () async {
      final googleUser = MockGoogleAccount();
      when(() => googleUser.id).thenReturn(alice.id);
      when(() => googleUser.email).thenReturn(alice.email);
      when(() => googleUser.displayName).thenReturn(alice.displayName);
      when(() => googleUser.photoUrl).thenReturn(null);
      final changed = service.onCurrentUserChanged.first;
      sdkEvents.add(googleUser);
      expect((await changed)?.id, alice.id);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(WebAccountStore.key)!);
      expect(
        saved.keys,
        unorderedEquals(['id', 'email', 'displayName', 'photoUrl']),
      );
      expect(prefs.getBool('is_logged_in'), true);
      expect((await store.read())?.email, alice.email);
    },
  );

  test(
    'fresh service restores the account without a Google login prompt or API authorization',
    () async {
      await store.save(alice);
      expect(
        service.currentUser,
        isNull,
      ); // Memory was lost, like a page refresh.
      final restored = await service.signInSilently();
      expect(restored?.email, alice.email);
      expect(service.currentUser?.id, alice.id);
      verifyNever(() => sdk.signInSilently());
      verifyNever(() => sdk.signIn());
      expect(await service.canAccessScopes(), false);
      expect(await service.restoreAuthorizedClient(), isNull);
      await expectLater(service.getAuthenticatedClient(), throwsStateError);
    },
  );

  test(
    'remembered profile cannot override the account actually authorized by Google',
    () async {
      await store.save(alice);
      await service.signInSilently();
      when(() => sdk.requestScopes(any())).thenAnswer((_) async => true);
      when(() => platform.getTokens(email: any(named: 'email'))).thenAnswer(
        (_) async => GoogleSignInTokenData(accessToken: 'fresh-google-token'),
      );
      when(
        () => sdk.canAccessScopes(scopes, accessToken: 'fresh-google-token'),
      ).thenAnswer((_) async => true);
      expect(await service.requestAuthorization(), true);
      expect(service.currentUser?.id, 'bob-id');
      expect((await store.read())?.email, 'bob@example.com');
      expect(await service.canAccessScopes(), true);
      final client = await service.getAuthenticatedClient();
      expect(client.credentials.accessToken.data, 'fresh-google-token');
      client.close();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(WebAccountStore.key),
        isNot(contains('fresh-google-token')),
      );
    },
  );

  test(
    'canceling Sheets authorization preserves the remembered login',
    () async {
      await store.save(alice);
      await service.signInSilently();
      when(() => sdk.requestScopes(any())).thenAnswer((_) async => false);
      expect(await service.requestAuthorization(), false);
      expect(service.currentUser?.id, alice.id);
      expect((await store.read())?.id, alice.id);
      expect(await service.canAccessScopes(), false);
    },
  );

  test(
    'logout forgets the account and does not revoke Google consent',
    () async {
      await store.save(alice);
      await service.signInSilently();
      await service.signOut();
      expect(service.currentUser, isNull);
      expect(await store.read(), isNull);
      expect(await service.signInSilently(), isNull);
      verify(() => sdk.signOut()).called(1);
      verifyNever(() => sdk.disconnect());
      verifyNever(() => sdk.signInSilently());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), false);
      expect(prefs.containsKey(WebAccountStore.key), false);
    },
  );

  test(
    'late authorization response cannot restore an account after logout',
    () async {
      await store.save(alice);
      await service.signInSilently();
      final authorization = Completer<bool>();
      when(
        () => sdk.requestScopes(any()),
      ).thenAnswer((_) => authorization.future);
      final pending = service.requestAuthorization();
      await service.signOut();
      authorization.complete(true);
      expect(await pending, false);
      expect(service.currentUser, isNull);
      expect(await store.read(), isNull);
    },
  );

  test(
    'restoring another account discards the previous API credential',
    () async {
      await store.save(alice);
      await service.signInSilently();
      when(() => sdk.requestScopes(any())).thenAnswer((_) async => true);
      when(() => platform.getTokens(email: any(named: 'email'))).thenAnswer(
        (_) async => GoogleSignInTokenData(accessToken: 'fresh-google-token'),
      );
      when(
        () => sdk.canAccessScopes(scopes, accessToken: 'fresh-google-token'),
      ).thenAnswer((_) async => true);
      expect(await service.requestAuthorization(), true);
      expect(service.currentUser?.id, 'bob-id');
      expect(await service.canAccessScopes(), true);
      await store.save(alice);
      expect((await service.signInSilently())?.id, alice.id);
      expect(await service.canAccessScopes(), false);
      await expectLater(service.getAuthenticatedClient(), throwsStateError);
    },
  );

  test(
    'invalid storage falls back to Google restoration without trusting it',
    () async {
      SharedPreferences.setMockInitialValues({
        WebAccountStore.key: '{broken',
        'is_logged_in': true,
      });
      expect(await service.signInSilently(), isNull);
      verify(() => sdk.signInSilently()).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(WebAccountStore.key), false);
    },
  );
}
