// ledger_ingestion_ui.dart

import 'package:flutter/material.dart';
import 'package:household_ledger/services/auth/app_account.dart';
import 'package:intl/intl.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_ingestion_service.dart';

class LedgerIngestionUI extends StatefulWidget {
  final AppAccount googleUser;
  final String accountEmail;

  const LedgerIngestionUI({
    super.key,
    required this.googleUser,
    required this.accountEmail,
  });

  @override
  State<LedgerIngestionUI> createState() => LedgerIngestionUIState();
}

class LedgerIngestionUIState extends State<LedgerIngestionUI> {
  final TextEditingController _inputController = TextEditingController();
  final LedgerIngestionService _ingestionService = LedgerIngestionService();

  bool _isSubmitting = false;
  String _previousText = '';
  int _lastTypedSlashIndex = -1;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _inputController.removeListener(_onTextChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = _inputController.text;
    final selection = _inputController.selection;
    final lengthChange = currentText.length - _previousText.length;

    if (lengthChange == 1 && selection.baseOffset > 0) {
      final typedChar = currentText[selection.baseOffset - 1];

      if (typedChar == '/' &&
          _lastTypedSlashIndex != -1 &&
          _lastTypedSlashIndex == selection.baseOffset - 2) {
        final formattedDateWithSpace =
            '${DateFormat('yyyy/MM/dd').format(DateTime.now())} ';
        final newText = currentText.substring(0, selection.baseOffset - 2) +
            formattedDateWithSpace +
            currentText.substring(selection.baseOffset);
        final newOffset =
            selection.baseOffset - 2 + formattedDateWithSpace.length;

        _inputController.value = _inputController.value.copyWith(
            text: newText,
            selection: TextSelection.collapsed(offset: newOffset));
        _lastTypedSlashIndex = -1;
      } else if (typedChar == '/') {
        _lastTypedSlashIndex = selection.baseOffset - 1;
      } else {
        _lastTypedSlashIndex = -1;
      }
    } else {
      _lastTypedSlashIndex = -1;
    }

    _previousText = _inputController.text;
  }

  /// 🚀 UI 버튼 눌렀을 때 호출되는 핸들러 (UI 조작 및 결과 안내만 담당)
  Future<void> _handleSubmit() async {
    final rawInput = _inputController.text;

    if (rawInput.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해 주세요.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // 1. AuthClient 준비
      final authClient = await GoogleAuthManager().getClient();

      // 2. 비즈니스 로직 클래스로 rawInput 넘겨서 실행
      final LedgerSubmitResult result = await _ingestionService.processAndSubmit(
        authClient: authClient,
        rawInput: rawInput,
        accountEmail: widget.accountEmail,
      );

      // 3. UI 갱신 및 다이얼로그 표시
      if (mounted) {
        if (result.isSuccess && result.success > 0) {
          _inputController.clear();
        }

        _showResultDialog(
          isSuccess: result.isSuccess,
          total: result.total,
          success: result.success,
          duplicate: result.duplicate,
          fail: result.fail,
          errorMessage: result.errorMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showResultDialog({
    required bool isSuccess,
    required int total,
    required int success,
    required int duplicate,
    required int fail,
    String? errorMessage,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: isSuccess ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(isSuccess ? '전송 완료' : '전송 실패'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSuccess) ...[
                Text('총 $total건 중 처리가 완료되었습니다.'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _buildResultRow('✅ 성공', '$success 건', Colors.green[700]),
                      if (duplicate > 0) ...[
                        const SizedBox(height: 6),
                        _buildResultRow('⚠️ 중복 스킵', '$duplicate 건', Colors.orange[800]),
                      ],
                      if (fail > 0) ...[
                        const SizedBox(height: 6),
                        _buildResultRow('❌ 파싱/입력 실패', '$fail 건', Colors.red[700]),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                const Text('처리 중 오류가 발생했습니다.'),
                const SizedBox(height: 8),
                Text(
                  errorMessage ?? '알 수 없는 에러가 발생했습니다.',
                  style: TextStyle(color: Colors.red[800], fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (isSuccess) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('확인', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultRow(String label, String countText, Color? textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(
          countText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('가계부 내역 입력'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '기준 계정: ${widget.accountEmail}',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    '가계부 내역을 입력하세요.\n예: 2026/1/3 10,600 쿠팡(쿠페이)\n //을 입력하시면 날짜가 제공 됩니다.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _handleSubmit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _isSubmitting ? '전송 중...' : '전송하기',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
