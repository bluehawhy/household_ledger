import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/overview_ui.dart';

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

  /// 💡 저장된 세션 확인 및 구글 서버 인증 유효성 실시간 검증
  Future<void> _checkSignInState() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedInFlag = prefs.getBool('is_logged_in') ?? false;

    try {
      if (!isLoggedInFlag) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. 기존 세션 Silent Sign-In 시도
      var account = _authManager.currentUser ?? await _authManager.signInSilently();

      if (account != null) {
        // 2. [핵심] 실제 구글 서버 인증 클라이언트 획득 시도 (비밀번호 변경/강제로그아웃 시 에러 발생)
        final client = await _authManager.getClient();
        
        if (mounted) {
          _navigateToOverview(account);
          return;
        }
      }

      // 세션이 유효하지 않으면 정리
      await _clearSession(prefs);
    } catch (e) {
      print("세션 만료 또는 무효화된 로그인 (수동 로그인 유도): $e");
      await _clearSession(prefs);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove('is_logged_in');
    try {
      await _authManager.signOut();
    } catch (_) {}
  }

  /// 수동 로그인 버튼 클릭 시
  Future<void> _handleSignIn() async {
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
      print("로그인 에러: $error");
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