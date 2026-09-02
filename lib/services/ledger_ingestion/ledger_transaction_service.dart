import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_read_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_spreadsheet_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_write_service.dart';

/// 가계부 거래 데이터의 기존 진입점을 유지하는 Facade 서비스.
///
/// 실제 조회/저장 로직은 [LedgerReadService]와 [LedgerWriteService]가 담당한다.
/// 기존 호출부의 변경을 최소화하기 위해 공개 API는 그대로 유지한다.
class LedgerDataService {
  final LedgerSpreadsheetService sheetSetupService;

  late final LedgerReadService _readService = LedgerReadService(
    sheetSetupService: sheetSetupService,
  );

  late final LedgerWriteService _writeService = LedgerWriteService(
    sheetSetupService: sheetSetupService,
  );

  LedgerDataService({LedgerSpreadsheetService? sheetSetupService})
      : sheetSetupService =
            sheetSetupService ?? LedgerSpreadsheetService();

  CategoryMapper get categoryMapper => sheetSetupService.categoryMapper;

  static const List<String> defaultHeader = [
    '날짜',
    '거래유형',
    '거래 수단',
    '분류',
    '내용',
    '금액',
    '메모',
    'raw_txt',
  ];

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  Future<bool> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) {
    return _writeService.addTransaction(
      client: client,
      item: item,
      spreadsheetId: spreadsheetId,
    );
  }

  Future<bool> updateTransaction({
    required AuthClient client,
    required LedgerItem oldItem,
    required LedgerItem newItem,
    String? spreadsheetId,
  }) {
    return _writeService.updateTransaction(
      client: client,
      oldItem: oldItem,
      newItem: newItem,
      spreadsheetId: spreadsheetId,
    );
  }

  Future<bool> appendTransactionBatch(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<LedgerItem> items,
  ) {
    return _writeService.appendTransactionBatch(
      sheetsApi,
      spreadsheetId,
      sheetName,
      items,
    );
  }

  Map<String, List<LedgerItem>> groupItemsByYearAndMonth(
    List<LedgerItem> items,
  ) {
    return _writeService.groupItemsByYearAndMonth(items);
  }

  Future<Map<String, int>> processMultiYearMonthBatch(
    AuthClient client,
    sheets.SheetsApi sheetsApi,
    List<LedgerItem> items,
  ) {
    return _writeService.processMultiYearMonthBatch(
      client,
      sheetsApi,
      items,
    );
  }

  bool isDuplicateTransaction(
    List<List<dynamic>> rows,
    LedgerItem item,
  ) {
    return _writeService.isDuplicateTransaction(rows, item);
  }

  Future<bool> appendTransactionData(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<List<dynamic>> existingRows,
    LedgerItem item,
  ) {
    return _writeService.appendTransactionData(
      sheetsApi,
      spreadsheetId,
      sheetName,
      existingRows,
      item,
    );
  }

  Future<List<LedgerItem>> getMonthlyExpenses({
    required AuthClient client,
    required int year,
    required int month,
  }) {
    return _readService.getMonthlyExpenses(
      client: client,
      year: year,
      month: month,
    );
  }

  Future<List<LedgerItem>> getMonthlyIncomes({
    required AuthClient client,
    required int year,
    required int month,
  }) {
    return _readService.getMonthlyIncomes(
      client: client,
      year: year,
      month: month,
    );
  }

  Future<List<LedgerItem>> getMonthlyTransactions({
    required AuthClient client,
    required int year,
    required int month,
    required TransactionType type,
  }) {
    return _readService.getMonthlyTransactions(
      client: client,
      year: year,
      month: month,
      type: type,
    );
  }

  Future<List<LedgerItem>> getMonthlyLedger({
    required AuthClient client,
    required int year,
    required int month,
    String? accountEmail,
  }) {
    return _readService.getMonthlyLedger(
      client: client,
      year: year,
      month: month,
      accountEmail: accountEmail,
    );
  }
}

@Deprecated('Use LedgerDataService instead')
class HouseholdSheetService extends LedgerDataService {}
