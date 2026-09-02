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

  /// 앱 시작/새로고침 시 기존 Google 로그인 세션을 복원한다.
  /// SharedPreferences의 로그인 플래그를 먼저 검사하지 않고
  /// GoogleSignIn의 실제 현재 계정/자동 로그인 상태를 기준으로 판단한다.
  Future<void> _checkSignInState() async {
    try {
      // GoogleSignIn의 현재 계정이 이미 메모리에 있다면 바로 사용한다.
      var account = _authManager.currentUser;

      // 현재 계정이 없다면 저장된 Google 세션으로 자동 복원을 시도한다.
      account ??= await _authManager.signInSilently();

      if (account != null) {
        // 복원 성공 시 로그인 플래그도 최신 상태로 맞춘다.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);

        if (!mounted) return;
        _navigateToOverview(account);
        return;
      }

      // 실제 Google 계정이 없을 때만 로그인 플래그를 정리한다.
      final prefs = await SharedPreferences.getInstance();
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
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
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
