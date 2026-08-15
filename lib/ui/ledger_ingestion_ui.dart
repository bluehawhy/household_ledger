import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:household_ledger/services/utils/app_logger.dart';
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

class LedgerIngestionUI extends StatefulWidget {
  final GoogleSignInAccount googleUser;

  const LedgerIngestionUI({super.key, required this.googleUser});

  @override
  State<LedgerIngestionUI> createState() => LedgerIngestionUIState();
}

class LedgerIngestionUIState extends State<LedgerIngestionUI> {
  final TextEditingController _inputController = TextEditingController();
  bool _isSubmitting = false;
  String _previousText = '';
  int _lastTypedSlashIndex = -1; // 💡 마지막으로 타이핑된 '/'의 인덱스 추적
  
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

    // 💡 사용자가 키보드로 한 글자씩 입력하는 경우만 감지
    if (lengthChange == 1 && selection.baseOffset > 0) {
      final typedChar = currentText[selection.baseOffset - 1];

      // 💡 [수정] _lastTypedSlashIndex가 유효한 인덱스일 때만 연속 입력을 확인
      if (typedChar == '/' && _lastTypedSlashIndex != -1 && _lastTypedSlashIndex == selection.baseOffset - 2) {
        // 두 번째 '/'가 연속으로 입력된 경우: 날짜로 변환
        final formattedDateWithSpace = '${DateFormat('yyyy/MM/dd').format(DateTime.now())} ';
        final newText = currentText.substring(0, selection.baseOffset - 2) + formattedDateWithSpace + currentText.substring(selection.baseOffset);
        final newOffset = selection.baseOffset - 2 + formattedDateWithSpace.length;

        _inputController.value = _inputController.value.copyWith(text: newText, selection: TextSelection.collapsed(offset: newOffset));
        _lastTypedSlashIndex = -1; // 상태 초기화
      } else if (typedChar == '/') {
        // 첫 번째 '/'가 입력된 경우: 위치만 기록
        _lastTypedSlashIndex = selection.baseOffset - 1;
      } else {
        // 다른 문자가 입력된 경우: 상태 초기화
        _lastTypedSlashIndex = -1;
      }
    } else {
      // 붙여넣기, 삭제 등 다른 종류의 변경 시 상태 초기화
      _lastTypedSlashIndex = -1;
    }

    // 다음 비교를 위해 현재 텍스트를 저장
    _previousText = _inputController.text;
  }

  /// 🚀 GoogleAuthManager를 통해 크로스 플랫폼 안전한 AuthClient 수급
  Future<auth.AuthClient> _getAuthClient() async {
    final authManager = GoogleAuthManager();
    return await authManager.getClient();
  }

  /// 🚀 결과 안내 팝업(Dialog)을 표시하는 함수
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
                Navigator.of(dialogContext).pop(); // 1. 다이얼로그 닫기
                // 2. 💡 성공 시에만 이전 화면(Overview)으로 복귀
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




  /// 🚀 전송 이벤트 전용 함수
  Future<void> submitLedgerEntry([String? text]) async {
    final rawInput = text ?? _inputController.text;
    AppLogger.i("rawInput: '$rawInput'");

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
      // 1. 크로스 플랫폼 안전한 _getAuthClient() 호출
      final authClient = await _getAuthClient();

      // 2. 서비스 인스턴스 생성
      final sheetsApi = sheets.SheetsApi(authClient);
      final textParserService = TextParserService();

      await textParserService.init();

      // 3. 입력 텍스트 전처리/분할
      final List<String> lines = textParserService.parseInputLines(rawInput);

      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('처리할 수 있는 텍스트가 없습니다.')),
          );
        }
        return;
      }

      int successCount = 0;
      int duplicateCount = 0;
      int failCount = 0;

      // -----------------------------------------------------------------
      // 🔀 [분기] 1줄이면 SingleEntryService, 2줄 이상이면 MultiEntryService
      // -----------------------------------------------------------------
      if (lines.length == 1) {
        // 1줄 단일 처리
        final singleEntryService = SingleEntryService();
        final Map<String, dynamic> itemMap = textParserService.parseSingleLineToMap(lines.first);

        final ParseResult result = await singleEntryService.appendParseSingleLine(
         authClient,
          sheetsApi,
          itemMap,
        );

        if (result == ParseResult.success) {
          successCount = 1;
        } else if (result == ParseResult.duplicate) {
          duplicateCount = 1;
        } else {
          failCount = 1;
        }
      } else {
        // 2줄 이상 다중 캐시/배치 처리 (429 API 쿼터 에러 방지)
        final multiEntryService = MultiEntryService();

        // 전체 라인을 Map 리스트로 먼저 변환
        final List<Map<String, dynamic>> itemMaps = lines
            .map((line) => textParserService.parseSingleLineToMap(line))
            .toList();

        final resultMap = await multiEntryService.appendParseMultiLines(
          authClient,

          
          sheetsApi,
          itemMaps,
        );

        successCount = resultMap[ParseResult.success] ?? 0;
        duplicateCount = resultMap[ParseResult.duplicate] ?? 0;
        failCount = resultMap[ParseResult.fail] ?? 0;
      }

      // 4. 성공 시 입력창 초기화 및 결과 팝업 표시
      if (mounted) {
        if (successCount > 0) {
          _inputController.clear();
        }

        _showResultDialog(
          isSuccess: true,
          total: lines.length,
          success: successCount,
          duplicate: duplicateCount,
          fail: failCount,
        );
      }
    } catch (e, stackTrace) {
      print('❌ 업로드 중 에러 발생: $e');
      print('📍 스택 트레이스:\n$stackTrace');

      if (mounted) {
        _showResultDialog(
          isSuccess: false,
          total: 0,
          success: 0,
          duplicate: 0,
          fail: 0,
          errorMessage: e.toString(),
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
              '계정: ${widget.googleUser.email}',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '가계부 내역을 입력하세요.\n예: 2026/1/3 10,600 쿠팡(쿠페이)\n //을 입력하시면 날짜가 제공 됩니다.',
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
              onPressed: _isSubmitting ? null : () => submitLedgerEntry(),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(
                _isSubmitting ? '전송 중...' : '전송하기',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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