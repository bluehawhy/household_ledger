import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Flutter Web용 Google AdSense 배너입니다.
///
/// 빌드할 때 다음 값을 전달하면 실제 광고를 표시합니다.
/// --dart-define=ADSENSE_CLIENT_ID=ca-pub-...
/// --dart-define=ADSENSE_BANNER_SLOT=...
class AppBannerAd extends StatefulWidget {
  const AppBannerAd({super.key});

  @override
  State<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<AppBannerAd> {
  static bool _isViewRegistered = false;
  static const _viewType = 'household-ledger-adsense-banner';
  static const _clientId = String.fromEnvironment('ADSENSE_CLIENT_ID');
  static const _slotId = String.fromEnvironment('ADSENSE_BANNER_SLOT');

  @override
  void initState() {
    super.initState();
    if (_clientId.isNotEmpty && _slotId.isNotEmpty && !_isViewRegistered) {
      _isViewRegistered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (viewId) {
        final container = html.DivElement()
          ..style.width = '100%'
          ..style.height = '50px';
        final ad = html.Element.tag('ins')
          ..className = 'adsbygoogle'
          ..style.display = 'block'
          ..setAttribute('data-ad-client', _clientId)
          ..setAttribute('data-ad-slot', _slotId)
          ..setAttribute('data-ad-format', 'auto')
          ..setAttribute('data-full-width-responsive', 'true');
        container.children.add(ad);
        final scriptUrl =
            'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$_clientId';
        if (html.document.querySelector('script[src="$scriptUrl"]') == null) {
          html.document.head?.append(html.ScriptElement()
            ..async = true
            ..src = scriptUrl
            ..crossOrigin = 'anonymous');
        }
        Future.microtask(() {
          try {
            js.context.callMethod('eval', [
              '(adsbygoogle = window.adsbygoogle || []).push({});',
            ]);
          } catch (_) {
            // 광고 차단기·심사 대기 중에는 빈 배너 영역을 유지합니다.
          }
        });
        return container;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_clientId.isEmpty || _slotId.isEmpty) return const _AdPlaceholder();
    return const SizedBox(
      width: double.infinity,
      height: 50,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

class _AdPlaceholder extends StatelessWidget {
  const _AdPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '광고 배너입니다. 아직 준비중',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}
