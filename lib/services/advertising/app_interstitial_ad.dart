import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Overview 앱 바 새로고침에 사용하는 AdMob 전면 광고 관리자입니다.
///
/// Debug/Profile에서는 Google 테스트 광고를 사용합니다.
/// Release 빌드에서는 아래 dart-define으로 실제 광고 단위 ID를 전달해야 합니다.
/// --dart-define=ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID=ca-app-pub-...
/// --dart-define=ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS=ca-app-pub-...
class AppInterstitialAd {
  AppInterstitialAd._();

  static InterstitialAd? _ad;
  static bool _isLoading = false;
  static DateTime? _lastShownAt;
  static const _cooldown = Duration(minutes: 1);

  static String? get _adUnitId {
    if (!kReleaseMode) return InterstitialAd.testAdUnitId;

    if (Platform.isAndroid) {
      const id =
          String.fromEnvironment('ADMOB_INTERSTITIAL_AD_UNIT_ID_ANDROID');
      return id.isEmpty ? null : id;
    }
    if (Platform.isIOS) {
      const id = String.fromEnvironment('ADMOB_INTERSTITIAL_AD_UNIT_ID_IOS');
      return id.isEmpty ? null : id;
    }
    return null;
  }

  static Future<void> initialize() async {
    _load();
  }

  static Future<void> showForOverviewRefresh() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final lastShownAt = _lastShownAt;
    if (lastShownAt != null &&
        DateTime.now().difference(lastShownAt) < _cooldown) {
      return;
    }

    final ad = _ad;
    if (ad == null) {
      _load();
      return;
    }

    _ad = null;
    _lastShownAt = DateTime.now();
    final dismissed = Completer<void>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
        _load();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
        _load();
      },
    );
    ad.show();
    await dismissed.future;
  }

  static void _load() {
    if (_isLoading || _ad != null) return;
    final adUnitId = _adUnitId;
    if (adUnitId == null) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
        },
      ),
    );
  }
}

Future<void> initializeInterstitialAd() => AppInterstitialAd.initialize();

Future<void> showOverviewRefreshInterstitial() =>
    AppInterstitialAd.showForOverviewRefresh();
