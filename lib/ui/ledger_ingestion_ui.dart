import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

// 프로젝트 경로에 맞춰 import 경로를 확인해 주세요!
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

/// 🚀 GoogleAuthClient
/// HTTP 요청 시마다 GoogleUser의 authHeaders를 불러와
/// 만료된 Access Token을 백그라운드에서 자동으로 갱신해주는 Custom Client
class GoogleAuthClient extends http.BaseClient implements auth.AuthClient {
  final GoogleSignInAccount _user;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._user);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 요청 직전에 authHeaders를 부르면 구글 SDK가 만료 여부를 판단해 알아서 갱신해줍니다.
    final headers = await _user.authHeaders;
    request.headers.addAll(headers);
    return _inner.send(request);
  }

  @override
  auth.AccessCredentials get credentials => auth.AccessCredentials(
        auth.AccessToken('Bearer', '', DateTime.now().toUtc()),
        null,
        [],
      );

  @override
  void close() {
    _inner.close();
  }
}

class LedgerIngestionUI extends StatefulWidget {
  final GoogleSignInAccount googleUser; // 전달받은 구글 계정 정보

  const LedgerIngestionUI({super.key, required this.googleUser});

  @override
  State<LedgerIngestionUI> createState() => LedgerIngestionUIState();
}

class LedgerIngestionUIState extends State<LedgerIngestionUI> {
  final TextEditingController _inputController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 🚀 텍스트 분리 전처리 함수 (1줄인 경우와 다중 줄인 경우 구분)
  List<String> _parseInputLines(String rawInput) {
    final trimmedInput = rawInput.trim();
    if (trimmedInput.isEmpty) return [];

    // 개행 문자(\n)가 없으면 1줄 입력으로 간주 -> 그대로 반환
    if (!trimmedInput.contains('\n')) {
      return [trimmedInput];
    }

    // [여러 줄 입력인 경우]
    final singleLineText = trimmedInput
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final dateRegex = RegExp(
      r'(?:\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b|\b\d{1,2}[./-]\d{1,2}\b)',
    );

    final List<String> resultLines = [];
    final matches = dateRegex.allMatches(singleLineText).toList();

    if (matches.isEmpty) {
      return [singleLineText];
    }

    for (int i = 0; i < matches.length; i++) {
      final int start = matches[i].start;
      final int end = (i + 1 < matches.length) ? matches[i + 1].start : singleLineText.length;

      if (i == 0 && start > 0) {
        final prefix = singleLineText.substring(0, start).trim();
        if (prefix.isNotEmpty) {
          resultLines.add(prefix);
        }
      }

      final lineSegment = singleLineText.substring(start, end).trim();
      if (lineSegment.isNotEmpty) {
        resultLines.add(lineSegment);
      }
    }

    return resultLines;
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
                Navigator.of(dialogContext).pop();
                if (isSuccess) {
                  _inputController.clear(); // 성공 시 입력창 초기화
                }
              },
              child: const Text('확인', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  /// 팝업 내부 카운트 표기를 위한 헬퍼 위젯
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
      // 1. 전달받은 googleUser 기반으로 자동 토큰 갱신 Client 생성
      final authClient = GoogleAuthClient(widget.googleUser);

      // 2. 서비스 인스턴스 생성
      final sheetsApi = sheets.SheetsApi(authClient);
      final sheetService = HouseholdSheetService();
      final parserService = TextParserService();

      await parserService.init();

      // 3. 연도별 가계부 시트 ID 가져오기 (GoogleAuthClient가 auth.AuthClient를 구현함)
      final spreadsheetId = await sheetService.setupLedgerSpreadsheet(authClient);

      // 4. 입력 텍스트 조건별 정돈 및 분할 (1줄/다중줄 처리)
      final lines = _parseInputLines(rawInput);

      int successCount = 0;
      int duplicateCount = 0;
      int failCount = 0;

      // 5. 각 줄별 실행 및 결과 상태 카운트
      for (final line in lines) {
        final result = await parserService.appendParseSingleLine(
          sheetsApi,
          spreadsheetId,
          line,
        );

        if (result == ParseResult.success) {
          successCount++;
        } else if (result == ParseResult.duplicate) {
          duplicateCount++;
        } else {
          failCount++;
        }
      }

      // 6. 결과 팝업 표시
      if (mounted) {
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
            // 사용자 계정 정보
            Text(
              '계정: ${widget.googleUser.email}',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),

            // 1. 텍스트 입력창
            TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '가계부 내역을 입력하세요.\n예: 2026/1/3 10,600 쿠팡(쿠페이)',
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

            // 2. 전송 버튼
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