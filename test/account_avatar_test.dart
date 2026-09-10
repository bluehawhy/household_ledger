import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/ui/account_avatar.dart';

void main() {
  testWidgets('사진 주소가 없거나 비어 있으면 기본 아이콘을 표시한다', (tester) async {
    for (final url in <String?>[null, '', '  ']) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SizedBox(width: 72, height: 72, child: AccountAvatar(photoUrl: url)),
      )));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    }
  });

  testWidgets('사진 로딩 실패 시에도 기본 아이콘을 표시한다', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SizedBox(width: 72, height: 72,
        child: AccountAvatar(photoUrl: 'https://example.com/photo.png')),
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
