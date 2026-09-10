import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 모바일에서만 AdMob SDK를 초기화합니다.
Future<void> initializeMobileAds() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await MobileAds.instance.initialize();
  }
}
