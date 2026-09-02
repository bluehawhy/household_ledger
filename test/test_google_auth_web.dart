import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/ui/google_sign_in_button.dart';

/// 웹 Google 인증을 실제 브라우저에서 확인하기 위한 수동 smoke test.
///
/// 실행:
///   flutter run -d chrome -t test/test_google_auth_web.dart
void main() {
  runApp(const GoogleAuthWebTestApp());
}

class GoogleAuthWebTestApp extends StatelessWidget {
  const GoogleAuthWebTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Auth Web Test',
      theme: ThemeData(useMaterial3: true),
      home: const GoogleAuthWebTestPage(),
    );
  }
}

class GoogleAuthWebTestPage extends StatefulWidget {
  const GoogleAuthWebTestPage({super.key});

  @override
  State<GoogleAuthWebTestPage> createState() => _GoogleAuthWebTestPageState();
}

class _GoogleAuthWebTestPageState extends State<GoogleAuthWebTestPage> {
  final GoogleAuthManager _authManager = GoogleAuthManager();
  final TextEditingController _spreadsheetIdController = TextEditingController();

  StreamSubscription<dynamic>? _accountSubscription;
  dynamic _account;
  AuthClient? _client;
  bool _scopeAuthorized = false;
  bool _busy = false;
  String _status = '대기 중';
  String _driveResult = '-';
  String _sheetsResult = '-';

  @override
  void initState() {
    super.initState();
    _accountSubscription = _authManager.onCurrentUserChanged.listen((account) async {
      if (!mounted || account == null) return;
      setState(() {
        _account = account;
        _status = 'Google 로그인 성공';
      });
      await _checkAuthorization();
    });
  }

  Future<void> _restoreSignIn() async {
    await _run('Google 로그인 세션 복원', () async {
      final account = await _authManager.signInSilently();
      if (account == null) throw Exception('복원된 Google 로그인 세션이 없습니다.');
      _account = account;
      _status = 'Google 로그인 세션 복원 성공';
      await _checkAuthorization();
    });
  }

  Future<void> _checkAuthorization() async {
    if (_account == null) throw Exception('먼저 Google 로그인 계정을 확보해야 합니다.');
    final authorized = await _authManager.canAccessScopes();
    if (!mounted) return;
    setState(() {
      _scopeAuthorized = authorized;
      _status = authorized ? 'Drive / Sheets OAuth 권한 확인 성공' : 'Drive / Sheets OAuth 권한 필요';
    });
  }

  Future<void> _requestAuthorization() async {
    await _run('Drive / Sheets 권한 요청', () async {
      if (_account == null) throw Exception('먼저 Google 로그인을 완료하세요.');
      final authorized = await _authManager.authorizeScopes();
      if (!authorized) throw Exception('Google API 권한 승인이 취소되었거나 실패했습니다.');
      _scopeAuthorized = true;
      _status = 'Drive / Sheets OAuth 권한 승인 성공';
    });
  }

  Future<void> _createClient() async {
    await _run('googleapis AuthClient 생성', () async {
      if (_account == null) throw Exception('먼저 Google 로그인을 완료하세요.');
      if (!_scopeAuthorized) throw Exception('먼저 Drive / Sheets 권한을 승인하세요.');
      _client = await _authManager.getClient();
      _status = 'googleapis AuthClient 생성 성공';
    });
  }

  Future<void> _callDriveApi() async {
    await _run('Drive API 호출', () async {
      final client = _client ?? await _authManager.getClient();
      _client = client;
      final api = drive.DriveApi(client);
      final response = await api.files.list(pageSize: 1, spaces: 'drive');
      final file = response.files?.isNotEmpty == true ? response.files!.first : null;
      _driveResult = file == null ? '성공 (파일 없음)' : '성공: ${file.name ?? '(이름 없음)'}';
      _status = 'Drive API 호출 성공';
    });
  }

  Future<void> _callSheetsApi() async {
    await _run('Sheets API 호출', () async {
      final spreadsheetId = _spreadsheetIdController.text.trim();
      if (spreadsheetId.isEmpty) throw Exception('Spreadsheet ID를 입력하세요.');
      final client = _client ?? await _authManager.getClient();
      _client = client;
      final api = sheets.SheetsApi(client);
      final spreadsheet = await api.spreadsheets.get(spreadsheetId);
      _sheetsResult = '성공: ${spreadsheet.properties?.title ?? '(제목 없음)'}';
      _status = 'Sheets API 호출 성공';
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '$label 진행 중...';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _status = '$label 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    _spreadsheetIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = _account?.email?.toString() ?? '로그인 안 됨';
    return Scaffold(
      appBar: AppBar(title: const Text('Google Auth Web Smoke Test')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('상태: $_status'),
                const SizedBox(height: 8),
                Text('계정: $email'),
                const SizedBox(height: 24),
                const Text('1. Google 로그인', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Center(child: buildGoogleSignInButton(onPressed: () {})),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _restoreSignIn,
                  child: const Text('로그인 세션 복원 테스트'),
                ),
                const SizedBox(height: 24),
                const Text('2. OAuth 권한', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_scopeAuthorized ? '권한 상태: 승인됨' : '권한 상태: 승인 필요'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy || _account == null ? null : _checkAuthorization,
                  child: const Text('권한 상태 확인'),
                ),
                ElevatedButton(
                  onPressed: _busy || _account == null ? null : _requestAuthorization,
                  child: const Text('Drive / Sheets 권한 요청'),
                ),
                const SizedBox(height: 24),
                const Text('3. googleapis 인증', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy || !_scopeAuthorized ? null : _createClient,
                  child: const Text('AuthClient 생성'),
                ),
                const SizedBox(height: 24),
                const Text('4. 실제 API 호출', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy || !_scopeAuthorized ? null : _callDriveApi,
                  child: const Text('Drive API 테스트'),
                ),
                Text('Drive 결과: $_driveResult'),
                const SizedBox(height: 12),
                TextField(
                  controller: _spreadsheetIdController,
                  decoration: const InputDecoration(
                    labelText: 'Spreadsheet ID',
                    hintText: 'Sheets API 테스트용',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _busy || !_scopeAuthorized ? null : _callSheetsApi,
                  child: const Text('Sheets API 테스트'),
                ),
                Text('Sheets 결과: $_sheetsResult'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
