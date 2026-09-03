import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_row_mapper.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_spreadsheet_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// 가계부 거래의 추가, 수정, 배치 저장을 담당한다.
class LedgerWriteService {
  final LedgerSpreadsheetService sheetSetupService;

  LedgerWriteService({LedgerSpreadsheetService? sheetSetupService})
      : sheetSetupService =
            sheetSetupService ?? LedgerSpreadsheetService();

  CategoryMapper get categoryMapper => sheetSetupService.categoryMapper;

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  /// 단일 거래를 저장한다.
  Future<bool> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
    if (item.amount <= 0) {
      AppLogger.i(
        "⚠️ [0원 패스] [${item.formattedDate}] '${item.description}' 금액이 0원이므로 저장하지 않습니다.",
      );
      return false;
    }

    await _ensureCategoryMapperLoaded();

    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = spreadsheetId?.isNotEmpty == true
        ? spreadsheetId!
        : await sheetSetupService.setupLedgerSpreadsheetForYear(
            client,
            item.date.year,
          );

    if (targetSpreadsheetId == null) {
      AppLogger.i('⚠️ 대상 스프레드시트 ID를 찾을 수 없습니다.');
      return false;
    }

    final updatedItem = _withResolvedCategory(item);
    final monthSheetName = '${updatedItem.date.month}월';

    await _ensureMonthSheetExists(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
    );

    final existingRows = await _getSheetRows(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
    );

    if (_checkDuplicate(existingRows, updatedItem)) {
      AppLogger.i(
        "⚠️ [중복 패스] [${updatedItem.formattedDate}] '${updatedItem.description}' (${updatedItem.amount}원) 내역이 이미 존재합니다.",
      );
      return false;
    }

    return appendTransactionData(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
      existingRows,
      updatedItem,
    );
  }

  /// 기존 거래를 수정한다.
  Future<bool> updateTransaction({
    required AuthClient client,
    required LedgerItem oldItem,
    required LedgerItem newItem,
    String? spreadsheetId,
    String? accountEmail,
  }) async {
    AppLogger.i('[oldItem]: $oldItem');
    AppLogger.i('[newItem]: $newItem');

    if (newItem.amount <= 0) {
      AppLogger.i('⚠️ [0원 패스] 수정하려는 금액이 0원입니다.');
      return false;
    }

    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = spreadsheetId?.isNotEmpty == true
        ? spreadsheetId!
        : await sheetSetupService.setupLedgerSpreadsheetForYear(
            client,
            oldItem.date.year,
            accountEmail: accountEmail,
            createIfNotFound: accountEmail == null,
          );

    if (targetSpreadsheetId == null) {
      AppLogger.i('⚠️ 대상 스프레드시트 ID를 찾을 수 없습니다.');
      return false;
    }

    // 수정 화면에서 사용자가 선택한 분류를 자동 분류 결과로 덮어쓰지 않는다.
    final updatedNewItem = newItem;
    final monthSheetName = '${oldItem.date.month}월';
    final range = "'$monthSheetName'!1:1000";

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );
      final rows = response.values ?? [];
      if (rows.isEmpty) {
        AppLogger.i("⚠️ [$monthSheetName] 헤더 행을 찾을 수 없습니다.");
        return false;
      }

      final headers = rows.first;
      final targetRowIndex = _findTransactionRow(rows, headers, oldItem);

      if (targetRowIndex == -1) {
        AppLogger.i(
          "⚠️ [$monthSheetName] 수정할 기존 내역을 찾을 수 없습니다: "
          "[${oldItem.formattedDate}] ${oldItem.description} (${oldItem.amount}원)",
        );
        return false;
      }

      final updates = <sheets.ValueRange>[];
      for (var columnIndex = 0; columnIndex < headers.length; columnIndex++) {
        final value = LedgerRowMapper.valueForHeader(
          updatedNewItem,
          headers[columnIndex],
        );
        if (value == null) continue;

        final columnName = LedgerRowMapper.columnName(columnIndex);
        final cellRange =
            "'$monthSheetName'!$columnName$targetRowIndex";
        updates.add(
          sheets.ValueRange(
            range: cellRange,
            values: [
              [value],
            ],
          ),
        );
      }

      if (updates.isEmpty) {
        AppLogger.i("⚠️ [$monthSheetName] 수정 가능한 헤더를 찾을 수 없습니다.");
        return false;
      }

      await sheetsApi.spreadsheets.values.batchUpdate(
        sheets.BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: updates,
        ),
        targetSpreadsheetId,
      );

      AppLogger.i(
        '✅ [$monthSheetName] 내역 수정 완료! '
        '(행: $targetRowIndex, 수정 셀: ${updates.length}개)',
      );
      return true;
    } on sheets.DetailedApiRequestError catch (e) {
      AppLogger.i(
        '❌ [$monthSheetName] 시트 업데이트 API 에러 '
        '(${e.status}): ${e.message}',
      );
      return false;
    } catch (e) {
      AppLogger.i('❌ [$monthSheetName] 내역 수정 중 예외 발생: $e');
      return false;
    }
  }

  /// 월별 다중 거래를 배치 저장한다.
  Future<bool> appendTransactionBatch(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<LedgerItem> items,
  ) async {
    if (items.isEmpty) return true;

    try {
      final existingRows = await _getSheetRows(
        sheetsApi,
        spreadsheetId,
        sheetName,
      );

      if (existingRows.isEmpty) {
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [LedgerRowMapper.defaultHeader]),
          spreadsheetId,
          "'$sheetName'!A1:H1",
          valueInputOption: 'USER_ENTERED',
        );
        existingRows.add(LedgerRowMapper.defaultHeader);
      }

      final newRows = <List<Object?>>[];

      for (final item in items) {
        if (item.amount <= 0) continue;

        if (_checkDuplicate(existingRows, item)) {
          AppLogger.i(
            "⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.",
          );
          continue;
        }

        newRows.add(LedgerRowMapper.toRow(item));
        // 같은 배치 안의 중복도 차단한다.
        existingRows.add(newRows.last);
      }

      if (newRows.isEmpty) {
        AppLogger.i('ℹ️ [$sheetName] 추가할 거래가 없습니다.');
        return true;
      }

      final startRow = existingRows.length - newRows.length + 1;
      final endRow = startRow + newRows.length - 1;
      final targetRange = "'$sheetName'!A$startRow:H$endRow";

      await sheetsApi.spreadsheets.values.batchUpdate(
        sheets.BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: [
            sheets.ValueRange(
              range: targetRange,
              values: newRows,
            ),
          ],
        ),
        spreadsheetId,
      );

      AppLogger.i(
        '✅ [$sheetName] 통합 배치 입력 완료 (총 ${newRows.length}건)',
      );
      return true;
    } catch (e) {
      AppLogger.i(
        '❌ [appendTransactionBatch] ($sheetName) 배치 전송 실패: $e',
      );
      return false;
    }
  }

  Map<String, List<LedgerItem>> groupItemsByYearAndMonth(
    List<LedgerItem> items,
  ) {
    final grouped = <String, List<LedgerItem>>{};

    for (final item in items) {
      final key = '${item.date.year}_${item.date.month}';
      grouped.putIfAbsent(key, () => []).add(item);
    }

    return grouped;
  }

  Future<Map<String, int>> processMultiYearMonthBatch(
    AuthClient client,
    sheets.SheetsApi sheetsApi,
    List<LedgerItem> items,
  ) async {
    var totalSuccess = 0;
    var totalSkipped = 0;

    final groupedMap = groupItemsByYearAndMonth(items);

    for (final entry in groupedMap.entries) {
      final parts = entry.key.split('_');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final groupItems = entry.value;
      final sheetName = '${month}월';

      final spreadsheetId =
          await sheetSetupService.setupLedgerSpreadsheetForYear(client, year);

      if (spreadsheetId == null) {
        AppLogger.i(
          '⚠️ [$year년] 시트를 찾지 못하거나 생성하지 못해 처리를 제외합니다.',
        );
        totalSkipped += groupItems.length;
        continue;
      }

      AppLogger.i(
        '🚀 [$year년 $sheetName] ${groupItems.length}개 항목 처리 시작 '
        '(Spreadsheet ID: $spreadsheetId)',
      );

      final success = await appendTransactionBatch(
        sheetsApi,
        spreadsheetId,
        sheetName,
        groupItems,
      );

      if (success) {
        totalSuccess += groupItems.length;
      } else {
        totalSkipped += groupItems.length;
      }
    }

    AppLogger.i(
      '📊 [최종 완료] 성공: $totalSuccess건, 실패/건너뜀: $totalSkipped건',
    );
    return {'success': totalSuccess, 'skipped': totalSkipped};
  }

  bool isDuplicateTransaction(
    List<List<dynamic>> rows,
    LedgerItem item,
  ) {
    return _checkDuplicate(rows, item);
  }

  Future<bool> appendTransactionData(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<List<dynamic>> existingRows,
    LedgerItem item,
  ) async {
    if (item.amount <= 0) {
      AppLogger.i(
        "⚠️ [0원 패스] [${item.formattedDate}] '${item.description}' 금액이 0원이므로 저장하지 않습니다.",
      );
      return false;
    }

    if (_checkDuplicate(existingRows, item)) {
      AppLogger.i(
        "⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.",
      );
      return false;
    }

    final targetRow = existingRows.length + 1;
    final targetRange = "'$sheetName'!A$targetRow:H$targetRow";

    try {
      await sheetsApi.spreadsheets.values.update(
        LedgerRowMapper.toValueRange(
          range: targetRange,
          item: item,
        ),
        spreadsheetId,
        targetRange,
        valueInputOption: 'USER_ENTERED',
      );

      AppLogger.i(
        "✅ [$sheetName] ${item.type == TransactionType.income ? '수입' : '지출'} "
        '입력 성공 (행: $targetRow, 범위: $targetRange)',
      );
      return true;
    } catch (e) {
      AppLogger.i('❌ [$sheetName] 시트 업데이트 실패: $e');
      return false;
    }
  }

  Future<void> _ensureCategoryMapperLoaded() async {
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }
  }

  LedgerItem _withResolvedCategory(LedgerItem item) {
    return item.copyWith(
      category: categoryMapper.getCategory(
        item.description,
        isIncome: item.type == TransactionType.income,
      ),
    );
  }

  Future<List<List<dynamic>>> _getSheetRows(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
  ) async {
    final range = "'$sheetName'!A1:H1000";
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      range,
    );
    return response.values ?? [];
  }

  int _findTransactionRow(
    List<List<dynamic>> rows,
    List<dynamic> headers,
    LedgerItem item,
  ) {
    final dateIndex = LedgerRowMapper.indexOfHeader(headers, '날짜');
    final descriptionIndex = LedgerRowMapper.indexOfHeader(headers, '내용');
    final amountIndex = LedgerRowMapper.indexOfHeader(headers, '금액');
    if (dateIndex == null || descriptionIndex == null || amountIndex == null) {
      return -1;
    }

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= dateIndex ||
          row.length <= descriptionIndex ||
          row.length <= amountIndex) {
        continue;
      }

      final existingDate = row[dateIndex].toString().trim();
      final existingDesc = row[descriptionIndex].toString().trim();
      final existingAmount =
          row[amountIndex].toString().replaceAll(',', '').trim();

      if (existingDate == item.formattedDate.trim() &&
          existingDesc == item.description.trim() &&
          existingAmount == item.amount.toString().trim()) {
        return i + 1;
      }
    }

    return -1;
  }

  Future<void> _ensureMonthSheetExists(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
  ) async {
    final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
    final sheetExists = spreadsheet.sheets?.any(
          (sheet) => sheet.properties?.title == sheetName,
        ) ??
        false;

    if (sheetExists) return;

    AppLogger.i("➕ '$sheetName' 시트가 존재하지 않아 새로 생성합니다...");

    final addSheetRequest = sheets.Request(
      addSheet: sheets.AddSheetRequest(
        properties: sheets.SheetProperties(title: sheetName),
      ),
    );

    await sheetsApi.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(requests: [addSheetRequest]),
      spreadsheetId,
    );

    final headerRange = "'$sheetName'!A1:H1";
    await sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(
        range: headerRange,
        values: [LedgerRowMapper.defaultHeader],
      ),
      spreadsheetId,
      headerRange,
      valueInputOption: 'USER_ENTERED',
    );
  }

  bool _checkDuplicate(List<List<dynamic>> rows, LedgerItem item) {
    if (rows.length <= 1) return false;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= 5) continue;

      final existingDate = row[0].toString().trim();
      final existingDesc = row[4].toString().trim();
      final existingAmount = row[5].toString().replaceAll(',', '').trim();

      if (existingDate == item.formattedDate.trim() &&
          existingDesc == item.description.trim() &&
          existingAmount == item.amount.toString().trim()) {
        return true;
      }
    }

    return false;
  }
}
