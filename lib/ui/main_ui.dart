import 'dart:async';

import 'package:flutter/material.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/google_sign_in_button.dart';
import 'package:household_ledger/ui/overview_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

class MainUI extends StatefulWidget {
  final bool skipSessionRestore;
  final GoogleAuthManager? authManager;

  const MainUI({
    super.key,
    this.skipSessionRestore = false,
    this.authManager,
  });

  @override
  State<MainUI> createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoading = true;
  bool _authorizationRequired = false;
  bool _processingAccount = false;
  bool _authFlowInProgress = false;
  bool _sessionRestoreDisabled = false;
  String? _errorMessage;

  late final GoogleAuthManager _authManager;
  StreamSubscription<dynamic>? _accountSubscription;

  @override
  void initState() {
    super.initState();
    _authManager = widget.authManager ?? GoogleAuthManager();
    AppLogger.i('[AUTH] MainUI initState()');
    _sessionRestoreDisabled = widget.skipSessionRestore;

    _accountSubscription = _authManager.onCurrentUserChanged.listen(
      _handleAccountChanged,
      onError: (error, stackTrace) {
        AppLogger.i('[AUTH] Google 계정 이벤트 오류: $error');
      },
    );

    _checkSignInState();
  }

  Future<void> _handleAccountChanged(dynamic account) async {
    if (account == null ||
        !mounted ||
        _processingAccount ||
        _authFlowInProgress) {
      return;
    }

    AppLogger.i('[AUTH] Google 계정 변경 이벤트 수신');
    // Web의 GSI 버튼은 _handleSignIn을 거치지 않고 이 이벤트만 전달한다.
    _sessionRestoreDisabled = false;
    _processingAccount = true;
    _authFlowInProgress = true;
    try {
      await _handleAuthenticatedAccount(account);
    } finally {
      _processingAccount = false;
      _authFlowInProgress = false;
    }
  }

  Future<void> _checkSignInState() async {
    if (_sessionRestoreDisabled) {
      AppLogger.i('[AUTH] 명시적 로그아웃 상태 → 자동 로그인 복원 건너뜀');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (_authFlowInProgress) {
      AppLogger.i('[AUTH] 다른 인증 흐름이 진행 중 → 초기 로그인 상태 확인 생략');
      return;
    }

    _authFlowInProgress = true;
    AppLogger.i('[AUTH] _checkSignInState() 시작');
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool('is_logged_in') == false) {
        AppLogger.i('[AUTH] 저장된 로그아웃 상태 → 자동 로그인 복원 건너뜀');
        _sessionRestoreDisabled = true;
        return;
      }

      var account = _authManager.currentUser;
      AppLogger.i(
        '[AUTH] currentUser 결과: ${account == null ? 'null (계정 없음)' : '계정 있음'}',
      );

      if (account == null) {
        AppLogger.i('[AUTH] currentUser 없음 → signInSilently() 세션 복원 시도');
        account = await _authManager.signInSilently();
        AppLogger.i(
          '[AUTH] signInSilently() 결과: ${account == null ? '기존 세션 없음' : '계정 복원 성공'}',
        );
      }

      if (account != null && mounted) {
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
      _authFlowInProgress = false;
      if (mounted) {
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
      var authorized = await _authManager.canAccessScopes();
      AppLogger.i('[AUTH] Google API 권한 상태: $authorized');

      if (!authorized) {
        AppLogger.i('[AUTH] 기존 Google API 인증 클라이언트 복원 시도');
        final restoredClient = await _authManager.restoreAuthorizedClient();
        authorized = restoredClient != null;
        AppLogger.i('[AUTH] Google API 인증 클라이언트 복원 결과: $authorized');
      }

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
    if (_isLoading || _authFlowInProgress) return;

    _authFlowInProgress = true;
    _sessionRestoreDisabled = false;
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
    } finally {
      _authFlowInProgress = false;
    }
  }

  Future<void> _handleAuthorizeScopes() async {
    if (_isLoading || _authFlowInProgress) return;

    _authFlowInProgress = true;
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
    } finally {
      _authFlowInProgress = false;
    }
  }

  Future<void> _saveLoggedInState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', value);
    AppLogger.i('[AUTH] SharedPreferences is_logged_in=$value 저장 완료');
  }

  Future<void> _changeLoginAccount() async {
    if (_authFlowInProgress) return;
    _authFlowInProgress = true;
    setState(() => _isLoading = true);
    try {
      await _authManager.signOut();
      await _saveLoggedInState(false);
      if (!mounted) return;
      setState(() {
        _sessionRestoreDisabled = true;
        _authorizationRequired = false;
        _errorMessage = null;
      });
    } finally {
      _authFlowInProgress = false;
      if (mounted) setState(() => _isLoading = false);
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
                          _authManager.currentUser?.email ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _changeLoginAccount,
                          child: const Text('로그아웃 / 다른 계정으로 로그인'),
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
