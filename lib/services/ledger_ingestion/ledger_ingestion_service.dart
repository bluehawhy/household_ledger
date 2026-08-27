import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// 텍스트 입력을 파싱하고 Google Sheets 반영 결과를 나타낸다.
class LedgerSubmitResult {
  final bool isSuccess;
  final int total;
  final int success;
  final int duplicate;
  final int fail;
  final String? errorMessage;

  LedgerSubmitResult({
    required this.isSuccess,
    this.total = 0,
    this.success = 0,
    this.duplicate = 0,
    this.fail = 0,
    this.errorMessage,
  });
}

/// 자유 형식 거래 텍스트를 파싱해 가계부에 저장한다.
class LedgerIngestionService {
  final TextParserService _textParserService = TextParserService();

  Future<LedgerSubmitResult> processAndSubmit({
    required auth.AuthClient authClient,
    required String rawInput,
  }) async {
    AppLogger.i("rawInput 처리 시작: '$rawInput'");

    try {
      final sheetsApi = sheets.SheetsApi(authClient);
      await _textParserService.init();

      final lines = _textParserService.parseInputLines(rawInput);
      if (lines.isEmpty) {
        return LedgerSubmitResult(
          isSuccess: false,
          errorMessage: '처리할 수 있는 텍스트가 없습니다.',
        );
      }

      int successCount = 0;
      int duplicateCount = 0;
      int failCount = 0;
      final itemMaps = <Map<String, dynamic>>[];

      for (final line in lines) {
        try {
          itemMaps.add(_textParserService.parseSingleLineToMap(line));
        } catch (e) {
          failCount++;
          AppLogger.i('❌ 입력 행 파싱 실패: "$line" | $e');
        }
      }

      if (itemMaps.length == 1) {
        final result = await SingleEntryService().appendParseSingleLine(
          authClient,
          sheetsApi,
          itemMaps.first,
        );
        if (result == ParseResult.success) {
          successCount = 1;
        } else if (result == ParseResult.duplicate) {
          duplicateCount = 1;
        } else {
          failCount++;
        }
      } else if (itemMaps.length > 1) {
        final resultMap = await MultiEntryService().appendParseMultiLines(
          authClient,
          sheetsApi,
          itemMaps,
        );
        successCount = resultMap[ParseResult.success] ?? 0;
        duplicateCount = resultMap[ParseResult.duplicate] ?? 0;
        failCount += resultMap[ParseResult.fail] ?? 0;
      }

      return LedgerSubmitResult(
        isSuccess: true,
        total: lines.length,
        success: successCount,
        duplicate: duplicateCount,
        fail: failCount,
      );
    } catch (e, stackTrace) {
      AppLogger.i('❌ 업로드 중 에러 발생: $e\n$stackTrace');
      return LedgerSubmitResult(isSuccess: false, errorMessage: e.toString());
    }
  }
}
