import 'package:flutter/material.dart';
import 'ui/main_ui.dart';
import 'ui/theme/app_theme.dart';
import 'services/advertising/mobile_ads_initializer.dart'
    if (dart.library.html) 'services/advertising/mobile_ads_initializer_stub.dart';
import 'services/advertising/app_interstitial_ad.dart'
    if (dart.library.html) 'services/advertising/app_interstitial_ad_stub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeMobileAds();
  await initializeInterstitialAd();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가계부 어플',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MainUI(), // 👈 여기서 'const' 를 제거했습니다.
    );
  }
}
