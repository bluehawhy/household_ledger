// lib/ui/main_ui.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:household_ledger/services/auth/google_auth.dart'; // 💡 AuthManager 임포트
import 'package:household_ledger/ui/overview_ui.dart';

class MainUI extends StatefulWidget {
  const MainUI({super.key});

  @override
  State<MainUI> createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoading = false;
  
  // 💡 구글 인증 공통 매니저 사용
  final GoogleAuthManager _authManager = GoogleAuthManager();

  @override
  void initState() {
    super.initState();
    _checkSilentSignIn();
  }

  /// 기존 로그인 세션 및 OAuth AccessToken 유효성 검증
  Future<void> _checkSilentSignIn() async {
    setState(() => _isLoading = true);
    try {
      // 💡 1. 현재 이미 메모리에 살아있는 GoogleSignIn 계정이 있는지 먼저 확인
      final account = _authManager.currentUser;
      
      if (account != null) {
        // 이미 로그인 정보가 살아있다면 Overview로 이동
        if (mounted) _navigateToOverview(account);
        return;
      }
      
      // 웹 특성상 silent 로그인만으로는 Scope 토큰을 얻지 못하므로 
      // 강제로 getClient()를 불러 팝업을 띄우는 대신, 조용히 로그인 버튼을 보여줍니다.
      print("💡 웹 환경: 수동 로그인 버튼 클릭이 필요합니다.");
    } catch (e) {
      print("자동 로그인 세션 없음 (수동 로그인 유도): $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 수동 로그인 버튼 클릭 시 (사용자 액션 -> OAuth 팝업 열림)
  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // 버튼 클릭 시에는 정상적으로 OAuth 팝업 및 권한 요청 수행
      final client = await _authManager.getClient();
      final account = _authManager.currentUser;

      if (account != null && mounted) {
        _navigateToOverview(account);
      }
    } catch (error) {
      print("로그인 에러: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
      appBar: AppBar(title: const Text('우리가계부')),
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
                icon: const Icon(Icons.login),
                label: const Text('Google 계정으로 로그인'),
                onPressed: _handleSignIn,
              ),
      ),
    );
  }
}