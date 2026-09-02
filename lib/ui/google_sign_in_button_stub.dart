import 'package:flutter/material.dart';

Widget buildPlatformGoogleSignInButton({required VoidCallback onPressed}) {
  return ElevatedButton.icon(
    icon: const Icon(Icons.login),
    label: const Text('Google 계정으로 로그인'),
    onPressed: onPressed,
  );
}
