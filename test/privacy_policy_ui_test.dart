import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:household_ledger/ui/privacy_policy_ui.dart';

class _PolicyBundle extends CachingAssetBundle {
  _PolicyBundle(this.source, this.config);

  final String source;
  final String config;
  bool fail = false;

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (fail) throw StateError('Asset unavailable');
    return switch (key) {
      'assets/privacy/privacy_policy.html' => source,
      'assets/privacy/privacy_policy_config.json' => config,
      _ => throw StateError('Unexpected asset: $key'),
    };
  }
}

void main() {
  final source = File('assets/privacy/privacy_policy.html').readAsStringSync();
  final config = File('assets/privacy/privacy_policy_config.json').readAsStringSync();

  testWidgets(
    'HTML config and tables render and scroll to the end on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bundle = _PolicyBundle(
        source,
        jsonEncode({
          ...jsonDecode(config) as Map<String, dynamic>,
          'effectiveDate': '2026년 9월 8일',
          'operator': '운영자 <테스트>',
          'email': 'privacy@example.com',
        }),
      );
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: bundle,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const PrivacyPolicyUI(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html;
      expect(html, contains('운영자 &lt;테스트&gt;'));
      expect(html, contains('privacy@example.com'));
      expect(html, isNot(contains('입력 필요')));
      expect(html, contains('<table>'));
      expect(html, contains('https://myaccount.google.com/connections'));
      final scroll = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
      expect(scroll.controller!.position.maxScrollExtent, greaterThan(800));
      scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final footer = find.textContaining(
        '이 개인정보처리방침은 2026년 9월 8일부터 적용됩니다.',
        findRichText: true,
      );
      expect(footer, findsOneWidget);
      expect(
        tester.getRect(footer).overlaps(const Rect.fromLTWH(0, 0, 360, 800)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed asset load can be retried', (tester) async {
    final bundle = _PolicyBundle(source, config)..fail = true;
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: bundle,
        child: const MaterialApp(home: PrivacyPolicyUI()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('개인정보처리방침을 불러오지 못했습니다.'), findsOneWidget);
    bundle.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byType(HtmlWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
