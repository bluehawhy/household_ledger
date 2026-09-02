import 'dart:async';

import 'package:flutter/material.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/google_sign_in_button.dart';
import 'package:household_ledger/ui/overview_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

class MainUI extends StatefulWidget {
  const MainUI({super.key});

  @override
  State<MainUI> createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoading = true;
  bool _authorizationRequired = false;
  bool _processingAccount = false;
  String? _errorMessage;

  final GoogleAuthManager _authManager = GoogleAuthManager();
  StreamSubscription<dynamic>? _accountSubscription;

  @override
  void initState() {
    super.initState();
    AppLogger.i('[AUTH] MainUI initState()');

    // 로그인 결과는 계정 변경 이벤트로도 처리한다.
    _accountSubscription = _authManager.onCurrentUserChanged.listen(
      _handleAccountChanged,
      onError: (error, stackTrace) {
        AppLogger.i('[AUTH] Google 계정 이벤트 오류: $error');
      },
    );

    _checkSignInState();
  }

  Future<void> _handleAccountChanged(dynamic account) async {
    if (account == null || !mounted || _processingAccount) return;

    AppLogger.i('[AUTH] Google 계정 변경 이벤트 수신');
    _processingAccount = true;
    try {
      await _handleAuthenticatedAccount(account);
    } finally {
      _processingAccount = false;
    }
  }

  /// 앱 시작 시 기존 Google 로그인 세션을 먼저 복원한다.
  ///
  /// 이미 로그인된 계정이 있으면 로그인 화면을 잠깐 보여주는 대신
  /// 세션 복원 → 권한 확인 → OverviewPage 이동까지 완료한 뒤 화면을 전환한다.
  /// 기존 세션이 없을 때만 로그인 버튼을 표시한다.
  Future<void> _checkSignInState() async {
    AppLogger.i('[AUTH] _checkSignInState() 시작');

    try {
      AppLogger.i('[AUTH] currentUser 확인 시작');
      var account = _authManager.currentUser;
      AppLogger.i(
        '[AUTH] currentUser 결과: ${account == null ? 'null (계정 없음)' : '계정 있음'}',
      );

      // currentUser가 비어 있어도 새로고침 후 기존 Google 세션이 남아 있을 수 있다.
      // 로그인 화면을 먼저 보여주지 않고 silent restore를 완료한 뒤 판단한다.
      if (account == null) {
        AppLogger.i('[AUTH] currentUser 없음 → signInSilently() 세션 복원 시도');
        account = await _authManager.signInSilently();
        AppLogger.i(
          '[AUTH] signInSilently() 결과: ${account == null ? '기존 세션 없음' : '계정 복원 성공'}',
        );
      }

      if (account != null && mounted) {
        AppLogger.i('[AUTH] 로그인 계정 확인 성공 → OverviewPage 이동 준비');
        await _handleAuthenticatedAccount(account);
      } else {
        AppLogger.i('[AUTH] 복원할 Google 세션 없음 → 로그인 화면 표시');
      }
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] 로그인/권한 확인 중 오류 발생: $e');
      AppLogger.i('[AUTH] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _authorizationRequired = false;
          _errorMessage = 'Google 로그인 상태를 확인하지 못했습니다.\n다시 시도해 주세요.';
        });
      }
    } finally {
      if (mounted) {
        AppLogger.i('[AUTH] _checkSignInState() 종료 → loading=false');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAuthenticatedAccount(dynamic account) async {
    if (!mounted) return;

    AppLogger.i('[AUTH] 로그인 계정 확인 성공');
    AppLogger.i('[AUTH] 계정 이메일: ${account.email}');
    await _saveLoggedInState(true);

    await _checkApiAuthorization(account);
  }

  Future<void> _checkApiAuthorization(dynamic account) async {
    if (!mounted) return;

    try {
      final authorized = await _authManager.canAccessScopes();
      AppLogger.i('[AUTH] Google API 권한 상태: $authorized');

      if (!authorized) {
        AppLogger.i('[AUTH] Google API 권한 필요 → MainUI에서 권한 연결 대기');
        if (mounted) {
          setState(() {
            _authorizationRequired = true;
            _errorMessage = 'Google Drive와 Sheets 접근 권한이 필요합니다.';
            _isLoading = false;
          });
        }
        return;
      }

      AppLogger.i('[AUTH] 로그인 및 Google API 권한 확인 성공 → OverviewPage 이동');
      await _saveLoggedInState(true);

      if (!mounted) return;
      _navigateToOverview(account);
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] Google API 권한 확인 오류: $e');
      AppLogger.i('[AUTH] Google API 권한 확인 StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _authorizationRequired = false;
          _errorMessage = 'Google API 권한 상태를 확인하지 못했습니다.\n다시 시도해 주세요.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignIn() async {
    if (_isLoading) return;

    AppLogger.i('[AUTH] Google 로그인 시작');
    setState(() {
      _isLoading = true;
      _authorizationRequired = false;
      _errorMessage = null;
    });

    try {
      var account = _authManager.currentUser;
      if (account == null) {
        AppLogger.i('[AUTH] currentUser 없음 → interactive signIn() 호출');
        account = await _authManager.signIn();
      }

      if (account == null) {
        throw Exception('Google 로그인에 실패했거나 사용자가 취소했습니다.');
      }

      AppLogger.i('[AUTH] Google 로그인 성공 → API 권한 확인');
      await _handleAuthenticatedAccount(account);
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] Google 로그인 에러: $e');
      AppLogger.i('[AUTH] Google 로그인 StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _authorizationRequired = false;
          _errorMessage = 'Google 로그인에 실패했습니다.\n다시 시도해 주세요.';
          _isLoading = false;
        });
      }
    }
  }

  /// Drive/Sheets 권한 요청은 반드시 사용자 클릭으로 시작한다.
  Future<void> _handleAuthorizeScopes() async {
    if (_isLoading) return;

    AppLogger.i('[AUTH] Google API 권한 요청 시작');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authorized = await _authManager.authorizeScopes();
      AppLogger.i('[AUTH] Google API 권한 요청 결과: $authorized');

      if (!authorized) {
        throw Exception('Google API 권한 승인이 취소되었습니다.');
      }

      await _authManager.getClient();
      AppLogger.i('[AUTH] Google API 권한 승인 및 인증 클라이언트 생성 성공');

      final account = _authManager.currentUser;
      if (account == null) {
        throw Exception('Google 로그인 계정을 확인할 수 없습니다.');
      }

      await _saveLoggedInState(true);
      if (!mounted) return;
      _navigateToOverview(account);
    } catch (e, stackTrace) {
      AppLogger.i('[AUTH] Google API 권한 요청 에러: $e');
      AppLogger.i('[AUTH] Google API 권한 요청 StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _authorizationRequired = true;
          _errorMessage = 'Google Drive와 Sheets 권한 연결에 실패했습니다.\n다시 시도해 주세요.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveLoggedInState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', value);
    AppLogger.i('[AUTH] SharedPreferences is_logged_in=$value 저장 완료');
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
  void dispose() {
    _accountSubscription?.cancel();
    super.dispose();
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
                  Text('Google 로그인 상태 확인 중...'),
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
                          onPressed: _handleAuthorizeScopes,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: const Text('Google Drive / Sheets 권한 연결'),
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
                    : buildGoogleSignInButton(onPressed: _handleSignIn),
      ),
    );
  }
}
