import 'package:flutter/material.dart';

import 'google_sign_in_button_stub.dart'
    if (dart.library.html) 'google_sign_in_button_web.dart'
    if (dart.library.io) 'google_sign_in_button_stub.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed}) =>
    buildPlatformGoogleSignInButton(onPressed: onPressed);
