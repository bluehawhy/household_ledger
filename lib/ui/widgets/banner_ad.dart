export 'banner_ad_stub.dart'
    if (dart.library.io) 'banner_ad_mobile.dart'
    if (dart.library.html) 'banner_ad_web.dart';
