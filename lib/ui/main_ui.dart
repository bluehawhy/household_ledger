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
  bool _authorizationRequired = false;
  String? _errorMessage;
  dynamic _account;

  final GoogleAuthManager _authManager = GoogleAuthManager();

  @override
  void initState() {
    super.initState();
    AppLogger.i('[AUTH] MainUI initState()');
    _checkSignInState();
  }

  /// 앱 시작/새로고침 시 기존 Google 로그인 세션을 복원하고
  /// Drive/Sheets API 사용 권한까지 확인한다.
  Future<void> _checkSignInState() async {
    AppLogger.i('[AUTH] _checkSignInState() 시작');

    try {
      AppLogger.i('[AUTH] currentUser 확인 시작');
      var account = _authManager.currentUser;
      AppLogger.i(
        '[AUTH] currentUser 결과: ${account == null ? 'null (계정 없음)' : '계정 있음'}',
      );

      if (account == null) {
        AppLogger.i('[AUTH] currentUser가 null → signInSilently() 호출');
        account = await _authManager.signInSilently();
        AppLogger.i(
          '[AUTH] signInSilently() 결과: ${account == null ? 'null (복원 실패)' : '계정 복원 성공'}',
        );
      } else {
        AppLogger.i('[AUTH] 기존 currentUser 사용 → signInSilently() 생략');
      }

      if (account == null) {
        AppLogger.i('[AUTH] Google 계정 복원 실패 → 로그인 화면 유지');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', false);
        AppLogger.i('[AUTH] SharedPreferences is_logged_in=false 저장 완료');
        return;
      }

      _account = account;
      AppLogger.i('[AUTH] 로그인 계정 확인 성공');
      AppLogger.i('[AUTH] 계정 이메일: ${account.email}');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      AppLogger.i('[AUTH] SharedPreferences is_logged_in=true 저장 완료');

      // 로그인 세션뿐 아니라 Drive/Sheets API 인증까지 MainUI에서 확인한다.
      try {
        AppLogger.i('[AUTH] 로그인 복원 후 Google API 인증 확인 시작');
        await _authManager.getClient();
        AppLogger.i('[AUTH] Google API 인증 확인 성공');

        if (!mounted) return;
        _navigateToOverview(account);
        return;
      } catch (e) {
        if (_isAuthorizationError(e)) {
          AppLogger.i('[AUTH] 로그인은 복원되었지만 Google API 권한이 필요함');
          _authorizationRequired = true;
          _errorMessage = 'Google Drive와 Sheets 접근 권한이 필요합니다.';
        } else {
          rethrow;
        }
      }
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] 자동 로그인/권한 확인 중 오류 발생: $e');
      AppLogger.i('[AUTH] StackTrace: $stackTrace');
      _errorMessage = 'Google 로그인 상태를 확인하지 못했습니다.\n다시 시도해 주세요.';
    } finally {
      if (mounted) {
        AppLogger.i('[AUTH] _checkSignInState() 종료 → loading=false');
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isAuthorizationError(Object error) {
    final message = error.toString();
    return message.contains('Google API 권한') ||
        message.contains('Google API 인증') ||
        message.contains('로그인 세션');
  }

  /// 로그인 또는 로그인 후 Drive/Sheets 권한까지 한 번에 처리한다.
  Future<void> _handleSignIn() async {
    if (_isLoading) return;

    AppLogger.i('[AUTH] Google 로그인/권한 처리 시작');
    setState(() {
      _isLoading = true;
      _authorizationRequired = false;
      _errorMessage = null;
    });

    try {
      AppLogger.i('[AUTH] getClient() 호출');
      await _authManager.getClient();
      AppLogger.i('[AUTH] getClient() 성공');
    } catch (e) {
      AppLogger.i('[AUTH] getClient() 결과: $e');

      if (!_isAuthorizationError(e)) {
        rethrow;
      }

      // 웹에서는 추가 OAuth scope 요청이 사용자 클릭에서 시작되어야 한다.
      AppLogger.i('[AUTH] Google API 권한 요청 시작');
      final authorized = await _authManager.authorizeScopes();
      AppLogger.i('[AUTH] Google API 권한 요청 결과: $authorized');

      if (!authorized) {
        throw Exception('Google API 권한 승인이 취소되었습니다.');
      }

      // 권한 승인 후 실제 API 클라이언트 생성까지 다시 확인한다.
      await _authManager.getClient();
      AppLogger.i('[AUTH] 권한 승인 후 Google API 인증 성공');
    }

    final account = _authManager.currentUser;
    AppLogger.i(
      '[AUTH] 로그인 후 currentUser: ${account == null ? 'null' : '계정 있음'}',
    );

    if (account == null) {
      throw Exception('Google 로그인 계정을 확인할 수 없습니다.');
    }

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    AppLogger.i('[AUTH] 로그인/권한 처리 성공 → is_logged_in=true');

    _navigateToOverview(account);

    if (mounted) {
      setState(() {
        _authorizationRequired = false;
        _errorMessage = null;
        _isLoading = false;
      });
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
                  Text('Google 로그인 및 권한 확인 중...'),
                ],
              )
            : _authorizationRequired
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Colors.orange,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage ?? 'Google Drive와 Sheets 접근 권한이 필요합니다.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _handleSignIn,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Google 권한 연결'),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(_errorMessage!, textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: _checkSignInState,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
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
