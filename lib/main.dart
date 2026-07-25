import 'package:flutter/material.dart';
import 'package:googleapis_auth/googleapis_auth.dart';

import 'services/auth/google_auth.dart'; // 💡 google_auth.dart로 변경!

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
  String _statusMessage = "버튼을 눌러 구글 인증을 테스트하세요.";
  bool _isLoading = false;

  Future<void> _testGoogleAuthOnly() async {
    setState(() => _isLoading = true);

    try {
      final googleAuthManager = GoogleAuthManager();
      final client = await googleAuthManager.getClient();
      
      // 성공 시 로직
      print("구글 인증 성공!");
      client.close(); // 클라이언트 사용 후 닫기
    } catch (e) {
      // 사용자가 로그인 취소 / 설정 오류 발생 시 처리
      print("로그인 중 에러 발생: $e");
      // 예: ScaffoldMessenger.of(context).showSnackBar(...)
    } finally {
      setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Auth 단독 테스트"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testGoogleAuthOnly,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.security),
              label: Text(
                _isLoading ? "인증 진행 중..." : "구글 로그인 단독 테스트",
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
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