import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Android/iOS용 AdMob 배너입니다.
///
/// 빌드할 때 다음 값을 전달하면 실제 광고를 표시합니다.
/// --dart-define=ADMOB_BANNER_AD_UNIT_ID_ANDROID=ca-app-pub-...
/// --dart-define=ADMOB_BANNER_AD_UNIT_ID_IOS=ca-app-pub-...
class AppBannerAd extends StatefulWidget {
  const AppBannerAd({super.key});

  @override
  State<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<AppBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  String? get _adUnitId {
    // Debug/Profile에서는 Google 테스트 광고만 보여 정책 위반을 막습니다.
    if (!kReleaseMode) return BannerAd.testAdUnitId;

    if (Platform.isAndroid) {
      const id = String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID_ANDROID');
      return id.isEmpty ? null : id;
    }
    if (Platform.isIOS) {
      const id = String.fromEnvironment('ADMOB_BANNER_AD_UNIT_ID_IOS');
      return id.isEmpty ? null : id;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final adUnitId = _adUnitId;
    if (adUnitId == null) return;
    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (!_isLoaded || ad == null) return const _AdPlaceholder();
    return SizedBox(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      child: Center(child: AdWidget(ad: ad)),
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
