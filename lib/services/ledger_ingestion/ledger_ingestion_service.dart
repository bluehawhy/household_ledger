import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_transaction_service.dart';
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
    String? accountEmail,
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
          final itemMap = _textParserService.parseSingleLineToMap(line);
          itemMap['raw_txt'] = line.trim();
          itemMaps.add(itemMap);
        } catch (e) {
          failCount++;
          AppLogger.i('❌ 입력 행 파싱 실패: "$line" | $e');
        }
      }

      final missingYears = accountEmail == null
          ? <int>[]
          : await _findMissingTargetSpreadsheets(
              authClient: authClient,
              accountEmail: accountEmail,
              itemMaps: itemMaps,
            );
      if (missingYears.isNotEmpty) {
        return LedgerSubmitResult(
          isSuccess: false,
          total: lines.length,
          fail: failCount + itemMaps.length,
          errorMessage:
              '기준 계정($accountEmail)에 ${missingYears.join(', ')}년 가계부 스프레드시트가 없습니다.\n'
              '해당 연도의 스프레드시트를 먼저 생성한 후 다시 입력해 주세요.',
        );
      }

      if (itemMaps.length == 1) {
        final result = await SingleEntryService().appendParseSingleLine(
          authClient,
          sheetsApi,
          itemMaps.first,
          accountEmail: accountEmail,
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
          accountEmail: accountEmail,
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

  Future<List<int>> _findMissingTargetSpreadsheets({
    required auth.AuthClient authClient,
    required String accountEmail,
    required List<Map<String, dynamic>> itemMaps,
  }) async {
    final years = <int>{};
    for (final itemMap in itemMaps) {
      try {
        years.add(LedgerItem.fromMap(itemMap).date.year);
      } catch (_) {
        // Individual parsing failures are reported through the normal fail count.
      }
    }

    if (years.isEmpty) return [];

    final sheetService = LedgerDataService();
    await sheetService.init(authClient);
    final missingYears = <int>[];
    for (final year in years) {
      final spreadsheetId = await sheetService.sheetSetupService
          .setupLedgerSpreadsheetForYear(
            authClient,
            year,
            accountEmail: accountEmail,
            createIfNotFound: false,
          );
      if (spreadsheetId == null) missingYears.add(year);
    }
    missingYears.sort();
    return missingYears;
  }
}
