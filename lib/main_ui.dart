import 'package:flutter/material.dart';

class MainUI extends StatefulWidget {
  const MainUI({super.key});

  @override
  State<MainUI> createState() => _MainUIState();
}

class _MainUIState extends State<MainUI> {
  bool _isLoggedIn = false;
  bool _isLoading = false;

  // 가상 로그인 테스트
  void _handleMockLogin() async {
    setState(() => _isLoading = true);
    
    // 1초 뒤 로그인 완료 처리
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isLoading = false;
      _isLoggedIn = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UI 테스트: 로그인 성공! (가계부 시트 연동 준비됨)')),
      );
    }
  }

  // 가상 로그아웃
  void _handleMockLogout() {
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('가계부 (UI 테스트)'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _isLoading
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('로그인 처리 중...'),
                  ],
                )
              : !_isLoggedIn
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.account_balance_wallet,
                          size: 80,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '나만의 가계부에 오신 것을 환영합니다',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _handleMockLogin,
                          icon: const Icon(Icons.login),
                          label: const Text('Google 계정으로 로그인 (테스트)'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircleAvatar(
                          radius: 36,
                          child: Icon(Icons.person, size: 40),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '테스트 사용자님 환영합니다!',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Text('user@example.com', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            '연동된 시트 ID: mock_spreadsheet_id_12345',
                            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                          ),
                        ),
                        const SizedBox(height: 32),
                        OutlinedButton(
                          onPressed: _handleMockLogout,
                          child: const Text('로그아웃'),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}