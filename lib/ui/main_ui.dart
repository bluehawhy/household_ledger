import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:household_ledger/ui/overview_ui.dart';

class MainUI extends StatefulWidget {
  @override
  _MainUIState createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '498727984793-660afhaj69e1kbo9mdj91v7mo8tpofom.apps.googleusercontent.com',
    scopes: [
      'email',
      'https://www.googleapis.com/auth/spreadsheets', // 구글 시트 권한
      'https://www.googleapis.com/auth/drive.file',   // 드라이브 파일 생성 권한
    ],
  );

  Future<void> _handleSignIn() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null) {
        // 로그인 성공 시 Overview 화면으로 이동하면서 계정 전달
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => OverviewPage(googleUser: account),
          ),
        );
      }
    } catch (error) {
      print("로그인 에러: $error");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('우리가계부')),
      body: Center(
        child: ElevatedButton.icon(
          icon: Icon(Icons.login),
          label: Text('Google 계정으로 로그인'),
          onPressed: _handleSignIn,
        ),
      ),
    );
  }
}