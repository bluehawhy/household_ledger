import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/auth/app_account.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/main_ui.dart';

class MockAuthManager extends Mock implements GoogleAuthManager {}

void main() {
  testWidgets(
    'landing login remains usable on a small screen after cancellation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'is_logged_in': false});
      final auth = MockAuthManager();
      when(() => auth.currentUser).thenReturn(null);
      when(
        () => auth.onCurrentUserChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(() => auth.signIn()).thenAnswer((_) async => null);
      await tester.pumpWidget(MaterialApp(home: MainUI(authManager: auth)));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final login = find.widgetWithText(FilledButton, 'Google 계정으로 로그인');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pumpAndSettle();
      verify(() => auth.signIn()).called(1);
      expect(find.text('Google 로그인에 실패했습니다.\n다시 시도해 주세요.'), findsOneWidget);
      expect(login, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh restores remembered account directly to Sheets connection, with logout available',
    (tester) async {
      SharedPreferences.setMockInitialValues({'is_logged_in': true});
      final auth = MockAuthManager();
      const account = AppAccount(id: 'alice', email: 'alice@example.com');
      AppAccount? current;
      when(() => auth.currentUser).thenAnswer((_) => current);
      when(
        () => auth.onCurrentUserChanged,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => auth.signInSilently(),
      ).thenAnswer((_) async => current = account);
      when(() => auth.canAccessScopes()).thenAnswer((_) async => false);
      when(() => auth.restoreAuthorizedClient()).thenAnswer((_) async => null);
      when(() => auth.signOut()).thenAnswer((_) async {
        current = null;
      });
      await tester.pumpWidget(MaterialApp(home: MainUI(authManager: auth)));
      await tester.pumpAndSettle();
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('Google Drive / Sheets 권한 연결'), findsOneWidget);
      verifyNever(() => auth.signIn());
      verifyNever(() => auth.authorizeScopes());
      await tester.tap(find.text('로그아웃 / 다른 계정으로 로그인'));
      await tester.pumpAndSettle();
      expect(find.text('alice@example.com'), findsNothing);
      expect(find.text('Google Drive / Sheets 권한 연결'), findsNothing);
      verify(() => auth.signOut()).called(1);
    },
  );
}
