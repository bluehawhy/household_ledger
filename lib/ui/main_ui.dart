import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/overview_ui.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

class MainUI extends StatefulWidget {
  const MainUI({super.key});

  @override
  State<MainUI> createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoading = true;
  final GoogleAuthManager _authManager = GoogleAuthManager();

  @override
  void initState() {
    super.initState();
    _checkSignInState();
  }

  /// 💡 저장된 세션 확인 (이전처럼 무겁게 getClient()를 검증하지 않음)
  Future<void> _checkSignInState() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedInFlag = prefs.getBool('is_logged_in') ?? false;

    if (!isLoggedInFlag) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Silent Sign-In으로 기존 로그인 계정 복원
      var account = _authManager.currentUser ?? await _authManager.signInSilently();

      // 2. 계정 정보가 존재한다면 바로 이동! (getClient() 호출 예외로 인한 세션 삭제 방지)
      if (account != null && mounted) {
        _navigateToOverview(account);
        return;
      }
      
      // 만약 정말로 계정을 가져올 수 없다면 로그인 플래그만 정리
      await prefs.setBool('is_logged_in', false);
    } catch (e) {
      AppLogger.i("자동 로그인 복원 중 오류 발생: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 수동 로그인 버튼 클릭 시
  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    try {
      // 수동 로그인 진행 (signIn 또는 getClient 호출)
      final client = await _authManager.getClient();
      final account = _authManager.currentUser;

      if (account != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        _navigateToOverview(account);
      }
    } catch (error) {
      AppLogger.i("로그인 에러: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToOverview(dynamic account) {
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