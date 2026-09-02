import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_row_mapper.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_spreadsheet_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// Google Sheets에서 가계부 거래를 조회하는 서비스.
class LedgerReadService {
  final LedgerSpreadsheetService sheetSetupService;

  LedgerReadService({LedgerSpreadsheetService? sheetSetupService})
      : sheetSetupService =
            sheetSetupService ?? LedgerSpreadsheetService();

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  /// 월별 지출 내역을 조회한다.
  Future<List<LedgerItem>> getMonthlyExpenses({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    return getMonthlyTransactions(
      client: client,
      year: year,
      month: month,
      type: TransactionType.expense,
    );
  }

  /// 월별 수입 내역을 조회한다.
  Future<List<LedgerItem>> getMonthlyIncomes({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    return getMonthlyTransactions(
      client: client,
      year: year,
      month: month,
      type: TransactionType.income,
    );
  }

  /// 지정된 거래 유형의 월별 내역을 조회한다.
  Future<List<LedgerItem>> getMonthlyTransactions({
    required AuthClient client,
    required int year,
    required int month,
    required TransactionType type,
  }) async {
    final allItems = await getMonthlyLedger(
      client: client,
      year: year,
      month: month,
    );

    return allItems.where((item) => item.type == type).toList();
  }

  /// 월별 전체 거래 내역을 조회한다.
  Future<List<LedgerItem>> getMonthlyLedger({
    required AuthClient client,
    required int year,
    required int month,
    String? accountEmail,
  }) async {
    final sheetsApi = sheets.SheetsApi(client);
    await sheetSetupService.init(client);
    final spreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(
      client,
      year,
      accountEmail: accountEmail,
      createIfNotFound: sheetSetupService.isCurrentAccount(accountEmail),
    );

    if (spreadsheetId == null) {
      AppLogger.i(
        '⚠️ [$year년 $month월] 시트를 찾을 수 없어 빈 목록을 반환합니다.',
      );
      return [];
    }

    final sheetName = '$month월';
    final range = "'$sheetName'!A1:H1000";

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        range,
      );

      final rows = response.values;
      if (rows == null || rows.length <= 1) return [];

      final items = <LedgerItem>[];

      for (var i = 1; i < rows.length; i++) {
        final item = LedgerRowMapper.fromRow(rows[i]);
        if (item != null) {
          items.add(item);
        }
      }

      return items;
    } on sheets.DetailedApiRequestError catch (e) {
      AppLogger.i(
        '⚠️ [$sheetName] 시트 읽기 실패 (${e.status}): ${e.message}',
      );
      return [];
    } catch (e) {
      AppLogger.i('⚠️ [$sheetName] 내역 조회 중 예외 발생: $e');
      return [];
    }
  }
}
