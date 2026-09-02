import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart';

Widget buildPlatformGoogleSignInButton({required VoidCallback onPressed}) {
  // Web에서는 Google Identity Services가 직접 렌더링한 버튼만
  // interactive sign-in을 시작할 수 있다. onPressed는 모바일 구현과
  // 동일한 호출 형태를 유지하기 위한 인자이며 여기서는 사용하지 않는다.
  return renderButton(
    configuration: GSIButtonConfiguration(
      type: GSIButtonType.standard,
      theme: GSIButtonTheme.outline,
      size: GSIButtonSize.large,
      text: GSIButtonText.signinWith,
      shape: GSIButtonShape.rectangular,
      minimumWidth: 240,
    ),
  );
}
