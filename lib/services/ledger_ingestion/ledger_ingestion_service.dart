import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_row_mapper.dart';
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

  const LedgerSubmitResult({
    required this.isSuccess,
    this.total = 0,
    this.success = 0,
    this.duplicate = 0,
    this.fail = 0,
    this.errorMessage,
  });
}

/// 자유 형식 텍스트의 파싱부터 Google Sheets 저장까지 담당한다.
class LedgerIngestionService {
  final TextParserService _textParserService = TextParserService();
  final LedgerDataService _ledgerService = LedgerDataService();

  Future<LedgerSubmitResult> processAndSubmit({
    required auth.AuthClient authClient,
    required String rawInput,
    String? accountEmail,
  }) async {
    AppLogger.i("rawInput 처리 시작: '$rawInput'");

    try {
      await _textParserService.init();
      final lines = _textParserService.parseInputLines(rawInput);
      if (lines.isEmpty) {
        return const LedgerSubmitResult(
          isSuccess: false,
          errorMessage: '처리할 수 있는 텍스트가 없습니다.',
        );
      }

      final parsed = _parseItems(lines);
      if (parsed.items.isEmpty) {
        return LedgerSubmitResult(
          isSuccess: false,
          total: lines.length,
          fail: parsed.fail,
          errorMessage: '저장할 수 있는 가계부 내역이 없습니다.',
        );
      }

      final targets = await _resolveTargetSpreadsheets(
        authClient: authClient,
        accountEmail: accountEmail,
        years: parsed.items.map((item) => item.date.year).toSet(),
      );
      if (targets.missingYears.isNotEmpty) {
        final targetName = accountEmail == null ? '현재 계정' : accountEmail;
        return LedgerSubmitResult(
          isSuccess: false,
          total: lines.length,
          fail: parsed.fail + parsed.items.length,
          errorMessage:
              '기준 계정($targetName)에 ${targets.missingYears.join(', ')}년 가계부 스프레드시트가 없습니다.\n'
              '해당 연도의 스프레드시트를 먼저 생성한 후 다시 입력해 주세요.',
        );
      }

      final submitted = await _submitItems(
        sheetsApi: sheets.SheetsApi(authClient),
        items: parsed.items,
        spreadsheetIds: targets.spreadsheetIds,
      );

      return LedgerSubmitResult(
        isSuccess: true,
        total: lines.length,
        success: submitted.success,
        duplicate: submitted.duplicate,
        fail: parsed.fail + submitted.fail,
      );
    } catch (e, stackTrace) {
      AppLogger.i('❌ 업로드 중 에러 발생: $e\n$stackTrace');
      return LedgerSubmitResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  _ParsedItems _parseItems(List<String> lines) {
    final items = <LedgerItem>[];
    var fail = 0;

    for (final line in lines) {
      try {
        final itemMap = _textParserService.parseSingleLineToMap(line);
        itemMap['raw_txt'] = line.trim();
        final item = LedgerItem.fromMap(itemMap);
        if (item.amount <= 0) {
          throw const FormatException('금액은 0원보다 커야 합니다.');
        }
        items.add(item);
      } catch (e) {
        fail++;
        AppLogger.i('❌ 입력 행 파싱 실패: "$line" | $e');
      }
    }

    return _ParsedItems(items: items, fail: fail);
  }

  Future<_TargetSpreadsheets> _resolveTargetSpreadsheets({
    required auth.AuthClient authClient,
    required String? accountEmail,
    required Set<int> years,
  }) async {
    await _ledgerService.init(authClient);

    final spreadsheetIds = <int, String>{};
    final missingYears = <int>[];
    final sortedYears = years.toList()..sort();

    for (final year in sortedYears) {
      final spreadsheetId = await _ledgerService.sheetSetupService
          .setupLedgerSpreadsheetForYear(
            authClient,
            year,
            accountEmail: accountEmail,
            createIfNotFound: accountEmail == null,
          );
      if (spreadsheetId == null) {
        missingYears.add(year);
      } else {
        spreadsheetIds[year] = spreadsheetId;
      }
    }

    return _TargetSpreadsheets(
      spreadsheetIds: spreadsheetIds,
      missingYears: missingYears,
    );
  }

  Future<_SubmissionCounts> _submitItems({
    required sheets.SheetsApi sheetsApi,
    required List<LedgerItem> items,
    required Map<int, String> spreadsheetIds,
  }) async {
    final groupedItems = <int, Map<int, List<LedgerItem>>>{};
    for (final item in items) {
      groupedItems
          .putIfAbsent(item.date.year, () => {})
          .putIfAbsent(item.date.month, () => [])
          .add(item);
    }

    var success = 0;
    var duplicate = 0;
    var fail = 0;

    for (final yearEntry in groupedItems.entries) {
      final spreadsheetId = spreadsheetIds[yearEntry.key];
      if (spreadsheetId == null) {
        fail += yearEntry.value.values.fold<int>(
          0,
          (sum, entries) => sum + entries.length,
        );
        continue;
      }

      for (final monthEntry in yearEntry.value.entries) {
        final sheetName = '${monthEntry.key}월';
        final pendingItems = monthEntry.value;

        try {
          final response = await sheetsApi.spreadsheets.values.get(
            spreadsheetId,
            "'$sheetName'!1:1000",
          );
          final existingRows = response.values ?? [];
          final existingKeys = _existingTransactionKeys(existingRows);
          final batchKeys = <String>{};
          final itemsToAppend = <LedgerItem>[];

          for (final item in pendingItems) {
            final key = _transactionKey(item);
            if (existingKeys.contains(key) || !batchKeys.add(key)) {
              duplicate++;
              AppLogger.i(
                '🔁 [중복 스킵] [${yearEntry.key}년 $sheetName] '
                '${item.formattedDate} | ${item.description} | ${item.amount}원',
              );
            } else {
              itemsToAppend.add(item);
            }
          }

          if (itemsToAppend.isEmpty) continue;

          final saved = await _ledgerService.appendTransactionBatch(
            sheetsApi,
            spreadsheetId,
            sheetName,
            itemsToAppend,
          );
          if (saved) {
            success += itemsToAppend.length;
          } else {
            fail += itemsToAppend.length;
          }
        } catch (e) {
          fail += pendingItems.length;
          AppLogger.i(
            '❌ [${yearEntry.key}년 $sheetName] 입력 실패: $e',
          );
        }
      }
    }

    AppLogger.i('📊 [처리 완료] 성공: $success, 중복: $duplicate, 실패: $fail');
    return _SubmissionCounts(
      success: success,
      duplicate: duplicate,
      fail: fail,
    );
  }

  Set<String> _existingTransactionKeys(List<List<dynamic>> rows) {
    if (rows.length <= 1) return {};

    final headers = rows.first;
    final keys = <String>{};
    for (var index = 1; index < rows.length; index++) {
      final item = LedgerRowMapper.fromRow(rows[index], headers: headers);
      if (item != null) keys.add(_transactionKey(item));
    }
    return keys;
  }

  String _transactionKey(LedgerItem item) {
    return '${item.formattedDate}_${item.description.trim()}_${item.amount}';
  }
}

class _ParsedItems {
  final List<LedgerItem> items;
  final int fail;

  const _ParsedItems({required this.items, required this.fail});
}

class _TargetSpreadsheets {
  final Map<int, String> spreadsheetIds;
  final List<int> missingYears;

  const _TargetSpreadsheets({
    required this.spreadsheetIds,
    required this.missingYears,
  });
}

class _SubmissionCounts {
  final int success;
  final int duplicate;
  final int fail;

  const _SubmissionCounts({
    required this.success,
    required this.duplicate,
    required this.fail,
  });
}
