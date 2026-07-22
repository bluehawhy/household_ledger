import 'package:flutter/material.dart';

// 💡 새롭게 정립한 경로로 import를 수정했습니다.
import '../services/auth/google_auth.dart';
import '../services/spread_sheet/google_spreadsheet.dart';

class MainUiScreen extends StatefulWidget {
  const MainUiScreen({super.key});

  @override
  State<MainUiScreen> createState() => _MainUiScreenState();
}

class _MainUiScreenState extends State<MainUiScreen> {
  // 조건부 임포트 매니저(GoogleSheetManager)가 앱/데스크톱 환경을 알아서 판별해 동작합니다.
  final GoogleSheetManager _sheetManager = GoogleSheetManager();

  bool _isLoading = false;
  String _statusMessage = "버튼을 누르면 구글 로그인 후 가계부를 생성합니다.";
  String? _spreadsheetId;

  Future<void> _handleStartProcess() async {
    setState(() {
      _isLoading = true;
      _statusMessage = "🔑 구글 로그인 및 가계부 설정 진행 중...";
      _spreadsheetId = null;
    });

    try {
      final spreadsheetId = await _sheetManager.runHouseholdLedgerSetup();

      setState(() {
        _spreadsheetId = spreadsheetId;
        _statusMessage = "🎉 가계부 시트 설정이 성공적으로 완료되었습니다!";
      });
    } catch (e) {
      setState(() {
        _statusMessage = "❌ 작업 도중 에러가 발생했습니다:\n$e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('구글 연동 가계부'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 24),
              const Text(
                '구글 드라이브 가계부 시스템',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: _spreadsheetId != null ? Colors.green : Colors.grey[700],
                ),
              ),
              if (_spreadsheetId != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  "시트 ID: $_spreadsheetId",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleStartProcess,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login),
                label: Text(_isLoading ? "처리 중..." : "구글 로그인 & 가계부 생성"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}