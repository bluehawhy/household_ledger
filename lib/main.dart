import 'package:flutter/material.dart';
import 'ui/main_ui.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
