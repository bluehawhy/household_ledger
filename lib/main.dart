import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// 구글 로그인 관련 패키지
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: GoogleAuthOnlyTestScreen(),
  ));
}

class GoogleAuthOnlyTestScreen extends StatefulWidget {
  const GoogleAuthOnlyTestScreen({super.key});

  @override
  State<GoogleAuthOnlyTestScreen> createState() => _GoogleAuthOnlyTestScreenState();
}

class _GoogleAuthOnlyTestScreenState extends State<GoogleAuthOnlyTestScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/spreadsheets',
    ],
  );

  StreamSubscription<GoogleSignInAccount?>? _sub;
  String _statusMessage = "버튼을 눌러 구글 인증을 테스트하세요.";

  @override
  void initState() {
    super.initState();

    // 💡 핵심: 웹 renderButton 클릭 시 또는 로그인 완료 시 스트림 수신
    _sub = _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) async {
      if (account != null) {
        setState(() {
          _statusMessage = "✅ 로그인 성공!\n계정: ${account.email}\n\nGoogle API 클라이언트 생성 중...";
        });

        // AuthClient(Google API 호환) 생성
        final httpClient = await _googleSignIn.authenticatedClient();
        if (httpClient != null) {
          setState(() {
            _statusMessage = "🎉 Google API AuthClient 발급 완료!\n이메일: ${account.email}";
          });
        }
      }
    }, onError: (error) {
      setState(() {
        _statusMessage = "💥 로그인 스트림 에러: $error";
      });
    });

    // 앱 시작 시 기존 로그인 세션 복구 시도
    _googleSignIn.signInSilently();
  }

  @override
  void dispose() {
    _sub?.cancel(); // 스트림 구독 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Auth 웹 테스트"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsWeb) ...[
              // 🌐 웹: 구글 공식 버튼 렌더링
              Center(
                child: web.renderButton(
                  configuration: web.GSIButtonConfiguration(
                    type: web.GSIButtonType.standard,
                    theme: web.GSIButtonTheme.outline,
                    size: web.GSIButtonSize.large,
                  ),
                ),
              ),
            ] else ...[
              // 📱 모바일 / 데스크톱
              ElevatedButton.icon(
                onPressed: () => _googleSignIn.signIn(),
                icon: const Icon(Icons.security),
                label: const Text("구글 로그인"),
              ),
            ],
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.5,
                      color: _statusMessage.startsWith("💥")
                          ? Colors.red[800]
                          : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}