import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  // 1. 데스크톱/우분투 서버용 Auth Manager
  final GoogleAuthManager _desktopAuthManager = GoogleAuthManager();

  // 2. 모바일(Android/iOS) 전용 GoogleSignIn 객체
  final GoogleSignIn _mobileGoogleSignIn = GoogleSignIn(
    scopes: const [
      'https://www.googleapis.com/auth/drive.file',
      'email',
    ],
  );

  /// 플랫폼 판별 헬퍼 (모바일 여부 확인)
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _checkSignInState();
  }

  /// 💡 시작 시 로그인 상태 체크 (플랫폼별 분기)
  Future<void> _checkSignInState() async {
    try {
      if (_isMobile) {
        // [모바일] GoogleSignIn.signInSilently()로 기존 로그인 확인
        final account = await _mobileGoogleSignIn.signInSilently();
        if (account != null && mounted) {
          _navigateToOverview(account);
          return;
        }
      } else {
        // [데스크톱/우분투] .data/credentials.json 파일 읽기 시도
        await _desktopAuthManager.getClient();
        final account = _desktopAuthManager.currentUser;

        if (account != null && mounted) {
          _navigateToOverview(account);
          return;
        }
      }
    } catch (e) {
      print("ℹ 기존 로그인 정보가 없거나 만료됨: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 💡 수동 로그인 버튼 클릭 시 (플랫폼별 분기)
  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    try {
      if (_isMobile) {
        // [모바일] Native Google Sign-In 팝업 호출
        final account = await _mobileGoogleSignIn.signIn();
        if (account != null && mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);
          _navigateToOverview(account);
        }
      } else {
        // [데스크톱/우분투] clientViaUserConsent 호출 및 .data/credentials.json 저장
        await _desktopAuthManager.getClient();
        final account = _desktopAuthManager.currentUser;

        if (account != null && mounted) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);
          _navigateToOverview(account);
        }
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
                  Text('인증 정보 확인 중...'),
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