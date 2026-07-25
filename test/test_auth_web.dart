import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// 구글 로그인 관련 패키지
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

const String _webClientId =
    '498727984793-5ottnv6mjdn0kppn5gm930f4od080qf2.apps.googleusercontent.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: GoogleWebAuthTestScreen(),
  ));
}

class GoogleWebAuthTestScreen extends StatefulWidget {
  const GoogleWebAuthTestScreen({super.key});

  @override
  State<GoogleWebAuthTestScreen> createState() =>
      _GoogleWebAuthTestScreenState();
}

class _GoogleWebAuthTestScreenState extends State<GoogleWebAuthTestScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/spreadsheets',
    ],
  );

  StreamSubscription<GoogleSignInAccount?>? _subscription;
  String _logMessage =
      "🧪 [test/ 폴더 내 테스트] Google Auth 테스트 준비 완료.\n아래 로그인 버튼을 눌러주세요.";
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();

    // ⚠️ 중요: signInSilently()를 여기서 호출하지 않습니다.
    // web.renderButton()이 렌더링되면서 자체적으로 FedCM/One Tap 흐름을 통해
    // 기존 세션을 감지합니다. signInSilently()를 동시에 호출하면
    // 두 개의 credential 요청이 충돌하면서
    // "flow_restarted" / "AbortError: signal is aborted without reason"
    // 에러가 발생합니다.


    _subscription = _googleSignIn.onCurrentUserChanged.listen(
      (GoogleSignInAccount? account) async {
        if (account != null) {
          _addLog("✅ Google 로그인 성공!\n- 이메일: ${account.email}");

          try {
            _addLog("🔄 Google API AuthClient 발급 시도 중...");
            final httpClient = await _googleSignIn.authenticatedClient();

            if (httpClient != null) {
              setState(() {
                _isSuccess = true;
              });
              _addLog("🎉 성공! googleapis AuthClient가 발급되었습니다.");
            } else {
              _addLog("⚠️ AuthClient를 생성하지 못했습니다.");
            }
          } catch (e) {
            _addLog("💥 AuthClient 발급 중 오류 발생: $e");
          }
        } else {
          _addLog("ℹ️ 현재 로그인된 계정이 없습니다.");
        }
      },
      onError: (error) {
        _addLog("💥 로그인 스트림 오류: $error");
      },
    );


    // 자동 로그인(silent sign-in)이 꼭 필요하다면, 버튼의 초기화가
    // 끝난 뒤(다음 프레임 이후)로 지연시켜 충돌 가능성을 줄입니다.
    // 그래도 완전한 해결책은 아니므로, 가능하면 버튼에게만 맡기는 것을 권장합니다.
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   Future.delayed(const Duration(milliseconds: 300), () {
    //     _googleSignIn.signInSilently().catchError((err) {
    //       _addLog("ℹ️ 자동 로그인 세션 없음: $err");
    //     });
    //   });
    // });
  }

  void _addLog(String message) {
    setState(() {
      _logMessage += "\n\n$message";
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Auth Web 테스트 (test/ 폴더)"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: web.renderButton(
                configuration: web.GSIButtonConfiguration(
                  type: web.GSIButtonType.standard,
                  theme: web.GSIButtonTheme.outline,
                  size: web.GSIButtonSize.large,
                  text: web.GSIButtonText.signinWith,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isSuccess ? Colors.green[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isSuccess ? Colors.green : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _logMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: Colors.black87,
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