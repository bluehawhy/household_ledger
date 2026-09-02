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
    AppLogger.i('[AUTH] MainUI initState()');
    _checkSignInState();
  }

  /// 앱 시작/새로고침 시 기존 Google 로그인 세션을 복원한다.
  /// SharedPreferences의 로그인 플래그를 먼저 검사하지 않고
  /// GoogleSignIn의 실제 현재 계정/자동 로그인 상태를 기준으로 판단한다.
  Future<void> _checkSignInState() async {
    AppLogger.i('[AUTH] _checkSignInState() 시작');

    try {
      // GoogleSignIn의 현재 계정이 이미 메모리에 있다면 바로 사용한다.
      AppLogger.i('[AUTH] currentUser 확인 시작');
      var account = _authManager.currentUser;
      AppLogger.i(
        '[AUTH] currentUser 결과: ${account == null ? 'null (계정 없음)' : '계정 있음'}',
      );

      // 현재 계정이 없다면 저장된 Google 세션으로 자동 복원을 시도한다.
      if (account == null) {
        AppLogger.i('[AUTH] currentUser가 null → signInSilently() 호출');
        account = await _authManager.signInSilently();
        AppLogger.i(
          '[AUTH] signInSilently() 결과: ${account == null ? 'null (복원 실패)' : '계정 복원 성공'}',
        );
      } else {
        AppLogger.i('[AUTH] 기존 currentUser 사용 → signInSilently() 생략');
      }

      if (account != null) {
        AppLogger.i('[AUTH] 로그인 계정 확인 성공 → OverviewPage 이동 준비');
        AppLogger.i('[AUTH] 계정 이메일: ${account.email}');

        // 복원 성공 시 로그인 플래그도 최신 상태로 맞춘다.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        AppLogger.i('[AUTH] SharedPreferences is_logged_in=true 저장 완료');

        if (!mounted) {
          AppLogger.i('[AUTH] mounted=false → 페이지 이동 취소');
          return;
        }

        AppLogger.i('[AUTH] OverviewPage로 이동');
        _navigateToOverview(account);
        return;
      }

      AppLogger.i('[AUTH] Google 계정 복원 실패 → 로그인 화면 유지');

      // 실제 Google 계정이 없을 때만 로그인 플래그를 정리한다.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      AppLogger.i('[AUTH] SharedPreferences is_logged_in=false 저장 완료');
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] 자동 로그인 복원 중 오류 발생: $e');
      AppLogger.i('[AUTH] StackTrace: $stackTrace');
    } finally {
      if (mounted) {
        AppLogger.i('[AUTH] _checkSignInState() 종료 → loading=false');
        setState(() => _isLoading = false);
      } else {
        AppLogger.i('[AUTH] _checkSignInState() 종료 → mounted=false');
      }
    }
  }

  /// 수동 로그인 버튼 클릭 시
  Future<void> _handleSignIn() async {
    if (_isLoading) return;

    AppLogger.i('[AUTH] 수동 로그인 시작');
    setState(() => _isLoading = true);
    try {
      AppLogger.i('[AUTH] getClient() 호출');
      final client = await _authManager.getClient();
      AppLogger.i('[AUTH] getClient() 성공');

      final account = _authManager.currentUser;
      AppLogger.i(
        '[AUTH] 수동 로그인 후 currentUser: ${account == null ? 'null' : '계정 있음'}',
      );

      if (account != null && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        AppLogger.i('[AUTH] 수동 로그인 성공 → is_logged_in=true');

        AppLogger.i('[AUTH] 수동 로그인 → OverviewPage 이동');
        _navigateToOverview(account);
      } else {
        AppLogger.i('[AUTH] 수동 로그인 후 계정 없음 또는 mounted=false');
      }
    } catch (error, stackTrace) {
      AppLogger.i('[AUTH] 로그인 에러: $error');
      AppLogger.i('[AUTH] 로그인 StackTrace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        AppLogger.i('[AUTH] 수동 로그인 종료 → loading=false');
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToOverview(dynamic account) {
    AppLogger.i('[AUTH] Navigator.pushReplacement → OverviewPage');
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
