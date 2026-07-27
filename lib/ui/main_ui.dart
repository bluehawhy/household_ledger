import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:household_ledger/ui/overview_ui.dart';

class MainUI extends StatefulWidget {
  @override
  _MainUIState createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '498727984793-5ottnv6mjdn0kppn5gm930f4od080qf2.apps.googleusercontent.com',
    scopes: [
      'email',
      'https://www.googleapis.com/auth/spreadsheets', // 구글 시트 권한
      'https://www.googleapis.com/auth/drive.file',   // 드라이브 파일 생성 권한
    ],
  );

  @override
  void initState() {
    super.initState();
    // 🚀 앱이 켜지면 먼저 기존 로그인 세션이 있는지 자동으로 확인합니다.
    _checkSilentSignIn();
  }

  /// 기존에 로그인한 이력이 있다면 팝업 없이 바로 Overview로 이동
  Future<void> _checkSilentSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signInSilently();
      if (account != null && mounted) {
        _navigateToOverview(account);
        return;
      }
    } catch (e) {
      print("자동 로그인 확인 실패/이력 없음: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 수동 로그인 버튼 클릭 시
  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account != null && mounted) {
        _navigateToOverview(account);
      }
    } catch (error) {
      print("로그인 에러: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Overview 화면으로 이동하는 공통 함수
  void _navigateToOverview(GoogleSignInAccount account) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => OverviewPage(googleUser: account),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('우리가계부')),
      body: Center(
        child: _isLoading
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('로그인 확인 중...'),
                ],
              )
            : ElevatedButton.icon(
                icon: Icon(Icons.login),
                label: Text('Google 계정으로 로그인'),
                onPressed: _handleSignIn,
              ),
      ),
    );
  }
}