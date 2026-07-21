import 'package:flutter/material.dart';
// import 'google_apps_spreadsheet.dart';
import 'main_ui.dart';

void main() async {
  // 플러터 위젯 실행 대신 CLI 테스트 앱 실행
  // runApp(const HouseholdLedgerApp());

  final testApp = TestApp();
  await testApp.runTest();
}

class TestApp {
  Future<void> runTest() async {
    print("----------------------------------");
    print("헬로월드 ! 콘솔 테스트를 시작합니다.");
    print("----------------------------------");

    // google_apps_spreadsheet 서비스 내부 테스트 실행
    print("구글 로그인 및 가계부 시트 조회/생성 테스트 시작...");
    
    // bool success = await _googleService.signInAndInitSpreadsheet();
    }
}


class HouseholdLedgerApp extends StatelessWidget {
  const HouseholdLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '가계부',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainUI(),
    );
  }
}