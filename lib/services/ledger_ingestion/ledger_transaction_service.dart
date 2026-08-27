import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_spreadsheet_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// 가계부 거래의 조회, 추가, 수정, 중복 검사를 담당한다.
class LedgerDataService {
  final LedgerSpreadsheetService sheetSetupService;

  LedgerDataService({LedgerSpreadsheetService? sheetSetupService})
      : sheetSetupService =
            sheetSetupService ?? LedgerSpreadsheetService();

  CategoryMapper get categoryMapper => sheetSetupService.categoryMapper;

  static const List<String> defaultHeader = [
    "날짜", "거래유형", "거래 수단", "분류", "내용", "금액", "메모"
  ];

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  // 🔵 단일 항목 입력 로직
  Future<bool> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
    if (item.amount <= 0) {
      AppLogger.i("⚠️ [0원 패스] [${item.formattedDate}] '${item.description}' 금액이 0원이므로 저장하지 않습니다.");
      return false;
    }

    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final sheetsApi = sheets.SheetsApi(client);

    final targetSpreadsheetId = (spreadsheetId != null && spreadsheetId.isNotEmpty)
        ? spreadsheetId
        : await sheetSetupService.setupLedgerSpreadsheetForYear(client, item.date.year);

    if (targetSpreadsheetId == null) {
      AppLogger.i("⚠️ 대상 스프레드시트 ID를 찾을 수 없습니다.");
      return false;
    }

    final updatedItem = item.copyWith(
      category: categoryMapper.getCategory(
        item.description,
        isIncome: item.type == TransactionType.income,
      ),
    );

    final monthSheetName = '${updatedItem.date.month}월';
    await _ensureMonthSheetExists(sheetsApi, targetSpreadsheetId, monthSheetName);

    final range = "'$monthSheetName'!A1:G1000";
    final response = await sheetsApi.spreadsheets.values.get(
      targetSpreadsheetId,
      range,
    );
    final List<List<dynamic>> existingRows = response.values ?? [];

    if (_checkDuplicate(existingRows, updatedItem)) {
      AppLogger.i("⚠️ [중복 패스] [${updatedItem.formattedDate}] '${updatedItem.description}' (${updatedItem.amount}원) 내역이 이미 존재합니다.");
      return false;
    }

    return await appendTransactionData(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
      existingRows,
      updatedItem,
    );
  }

  // 🟡 수입 / 지출 내역 수정(업데이트) 로직
  Future<bool> updateTransaction({
    required AuthClient client,
    required LedgerItem oldItem,
    required LedgerItem newItem,
    String? spreadsheetId,
  }) async {
    AppLogger.i("[oldItem]: $oldItem");
    AppLogger.i("[newItem]: $newItem");
    if (newItem.amount == 0) {
      AppLogger.i("⚠️ [0원 패스] 수정하려는 금액이 0원입니다.");
      return false;
    }

    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = (spreadsheetId != null && spreadsheetId.isNotEmpty)
        ? spreadsheetId
        : await sheetSetupService.setupLedgerSpreadsheetForYear(client, oldItem.date.year);

    if (targetSpreadsheetId == null) {
      AppLogger.i("⚠️ 대상 스프레드시트 ID를 찾을 수 없습니다.");
      return false;
    }

    final updatedNewItem = newItem.copyWith(
      category: categoryMapper.getCategory(
        newItem.description,
        isIncome: newItem.type == TransactionType.income,
      ),
    );

    final monthSheetName = '${oldItem.date.month}월';
    final range = "'$monthSheetName'!A1:G1000";

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );

      final List<List<dynamic>> rows = response.values ?? [];
      if (rows.isEmpty) {
        AppLogger.i("⚠️ [$monthSheetName] 시트에 데이터가 존재하지 않습니다.");
        return false;
      }

      int targetRowIndex = -1;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length > 5) {
          final existingDate = row[0].toString().trim();
          final existingDesc = row[4].toString().trim();
          final existingAmount = row[5].toString().replaceAll(',', '').trim();

          if (existingDate == oldItem.formattedDate.trim() &&
              existingDesc == oldItem.description.trim() &&
              existingAmount == oldItem.amount.toString().trim()) {
            targetRowIndex = i + 1;
            break;
          }
        }
      }

      if (targetRowIndex == -1) {
        AppLogger.i("⚠️ [$monthSheetName] 수정할 기존 내역을 시트에서 찾을 수 없습니다: "
            "[${oldItem.formattedDate}] ${oldItem.description} (${oldItem.amount}원)");
        return false;
      }

      final isIncome = updatedNewItem.type == TransactionType.income;
      final List<Object?> rowData = [
        updatedNewItem.formattedDate,
        isIncome ? "수입" : "지출",
        updatedNewItem.payMethod ?? "-",
        updatedNewItem.category,
        updatedNewItem.description,
        updatedNewItem.amount,
        updatedNewItem.memo,
      ];

      final targetRange = "'$monthSheetName'!A$targetRowIndex:G$targetRowIndex";

      final valueRange = sheets.ValueRange(
        range: targetRange,
        values: [rowData],
      );

      await sheetsApi.spreadsheets.values.update(
        valueRange,
        targetSpreadsheetId,
        targetRange,
        valueInputOption: "USER_ENTERED",
      );

      AppLogger.i("✅ [$monthSheetName] 내역 수정 완료! (행: $targetRowIndex, 범위: $targetRange)");
      return true;
    } on sheets.DetailedApiRequestError catch (e) {
      AppLogger.i("❌ [$monthSheetName] 시트 업데이트 API 에러 (${e.status}): ${e.message}");
      return false;
    } catch (e) {
      AppLogger.i("❌ [$monthSheetName] 내역 수정 중 예외 발생: $e");
      return false;
    }
  }

  /// 월별 다중 항목 배치 전송
  Future<bool> appendTransactionBatch(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<LedgerItem> items,
  ) async {
    if (items.isEmpty) return true;

    try {
      final range = "'$sheetName'!A1:G1000";
      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        range,
      );
      final List<List<dynamic>> existingRows = response.values ?? [];

      if (existingRows.isEmpty) {
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [defaultHeader]),
          spreadsheetId,
          "'$sheetName'!A1:G1",
          valueInputOption: "USER_ENTERED",
        );
        existingRows.add(defaultHeader);
      }

      final List<List<Object?>> newRows = [];

      for (final item in items) {
        if (item.amount <= 0) continue;

        if (_checkDuplicate(existingRows, item)) {
          AppLogger.i("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
          continue;
        }

        final isIncome = item.type == TransactionType.income;
        newRows.add([
          item.formattedDate,
          isIncome ? "수입" : "지출",
          item.payMethod ?? "-",
          item.category,
          item.description,
          item.amount,
          item.memo,
        ]);
      }

      if (newRows.isNotEmpty) {
        final startRow = existingRows.length + 1;
        final endRow = startRow + newRows.length - 1;
        final targetRange = "'$sheetName'!A$startRow:G$endRow";

        final batchRequest = sheets.BatchUpdateValuesRequest(
          valueInputOption: "USER_ENTERED",
          data: [
            sheets.ValueRange(
              range: targetRange,
              values: newRows,
            )
          ],
        );

        await sheetsApi.spreadsheets.values.batchUpdate(
          batchRequest,
          spreadsheetId,
        );
      }

      AppLogger.i("✅ [$sheetName] 통합 배치 입력 완료 (총 ${newRows.length}건)");
      return true;
    } catch (e) {
      AppLogger.i("❌ [appendTransactionBatch] ($sheetName) 배치 전송 실패: $e");
      return false;
    }
  }

  Map<String, List<LedgerItem>> groupItemsByYearAndMonth(List<LedgerItem> items) {
    final Map<String, List<LedgerItem>> grouped = {};

    for (final item in items) {
      final key = "${item.date.year}_${item.date.month}";
      grouped.putIfAbsent(key, () => []).add(item);
    }

    return grouped;
  }

  Future<Map<String, int>> processMultiYearMonthBatch(
    AuthClient client,
    sheets.SheetsApi sheetsApi,
    List<LedgerItem> items,
  ) async {
    int totalSuccess = 0;
    int totalSkipped = 0;

    final groupedMap = groupItemsByYearAndMonth(items);

    for (final entry in groupedMap.entries) {
      final yearMonthKey = entry.key;
      final parts = yearMonthKey.split('_');
      final int year = int.parse(parts[0]);
      final int month = int.parse(parts[1]);
      final List<LedgerItem> groupItems = entry.value;

      final sheetName = "${month}월";
      final String? spreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(client, year);

      if (spreadsheetId == null) {
        AppLogger.i("⚠️ [$year년] 시트를 찾지 못하거나 생성하지 못해 처리를 가로채거나 제외합니다.");
        totalSkipped += groupItems.length;
        continue;
      }

      AppLogger.i("🚀 [$year년 $sheetName] ${groupItems.length}개 항목 처리 시작 (Spreadsheet ID: $spreadsheetId)");

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

    AppLogger.i("📊 [최종 완료] 성공: $totalSuccess건, 실패/건너뜀: $totalSkipped건");
    return {'success': totalSuccess, 'skipped': totalSkipped};
  }

  Future<void> _ensureMonthSheetExists(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
  ) async {
    final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
    final sheetExists = spreadsheet.sheets?.any(
          (s) => s.properties?.title == sheetName,
        ) ??
        false;

    if (!sheetExists) {
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

      final headerValueRange = sheets.ValueRange(
        range: "'$sheetName'!A1:G1",
        values: [defaultHeader],
      );

      await sheetsApi.spreadsheets.values.update(
        headerValueRange,
        spreadsheetId,
        "'$sheetName'!A1:G1",
        valueInputOption: "USER_ENTERED",
      );
    }
  }

  bool _checkDuplicate(List<List<dynamic>> rows, LedgerItem item) {
    if (rows.length <= 1) return false;

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length > 5) {
        final existingDate = row[0].toString().trim();
        final existingDesc = row[4].toString().trim();
        final existingAmount = row[5].toString().replaceAll(',', '').trim();

        if (existingDate == item.formattedDate.trim() &&
            existingDesc == item.description.trim() &&
            existingAmount == item.amount.toString().trim()) {
          return true;
        }
      }
    }
    return false;
  }

  /// 입력 서비스가 API 실패와 중복 스킵을 구분할 수 있도록 중복 여부를 노출한다.
  bool isDuplicateTransaction(List<List<dynamic>> rows, LedgerItem item) {
    return _checkDuplicate(rows, item);
  }

  Future<bool> appendTransactionData(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<List<dynamic>> existingRows,
    LedgerItem item,
  ) async {
    if (item.amount == 0) {
      AppLogger.i("⚠️ [0원 패스] [${item.formattedDate}] '${item.description}' 금액이 0원이므로 저장하지 않습니다.");
      return false;
    }

    if (_checkDuplicate(existingRows, item)) {
      AppLogger.i("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
      return false;
    }

    final isIncome = item.type == TransactionType.income;
    final rowData = [
      item.formattedDate,
      isIncome ? "수입" : "지출",
      item.payMethod ?? "-",
      item.category ?? (isIncome ? "주수입" : "미분류"),
      item.description,
      item.amount,
      item.memo ?? "",
    ];

    final targetRow = existingRows.length + 1;
    final targetRange = "'$sheetName'!A$targetRow:G$targetRow";

    try {
      final valueRange = sheets.ValueRange(
        range: targetRange,
        values: [rowData],
      );

      await sheetsApi.spreadsheets.values.update(
        valueRange,
        spreadsheetId,
        targetRange,
        valueInputOption: "USER_ENTERED",
      );

      AppLogger.i("✅ [$sheetName] ${isIncome ? '수입' : '지출'} 입력 성공 (행: $targetRow, 범위: $targetRange)");
      return true;
    } catch (e) {
      AppLogger.i("❌ [$sheetName] 시트 업데이트 실패: $e");
      return false;
    }
  }

  // 🟢 월별 수입 / 지출 내역 조회 로직
  Future<List<LedgerItem>> getMonthlyExpenses({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    return await getMonthlyTransactions(
      client: client,
      year: year,
      month: month,
      type: TransactionType.expense,
    );
  }

  Future<List<LedgerItem>> getMonthlyIncomes({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    return await getMonthlyTransactions(
      client: client,
      year: year,
      month: month,
      type: TransactionType.income,
    );
  }

  Future<List<LedgerItem>> getMonthlyTransactions({
    required AuthClient client,
    required int year,
    required int month,
    required TransactionType type,
  }) async {
    final allItems = await getMonthlyLedger(client: client, year: year, month: month);
    return allItems.where((item) => item.type == type).toList();
  }

  Future<List<LedgerItem>> getMonthlyLedger({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(client, year);

    if (targetSpreadsheetId == null) {
      AppLogger.i("⚠️ [$year년 $month월] 시트를 찾을 수 없어 빈 목록을 반환합니다.");
      return [];
    }

    final monthSheetName = '$month월';
    final range = "'$monthSheetName'!A1:G1000";

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );

      final rows = response.values;
      if (rows == null || rows.length <= 1) {
        return [];
      }

      final List<LedgerItem> items = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.length <= 5) continue;

        final rawDate = row[0].toString().trim();
        final rawType = row[1].toString().trim();
        final rawPayMethod = row[2].toString().trim();
        final rawCategory = row[3].toString().trim();
        final rawDesc = row[4].toString().trim();
        final rawAmount = row[5].toString().replaceAll(',', '').trim();
        final rawMemo = row.length > 6 ? row[6].toString().trim() : null;

        if (rawDate.isEmpty || rawAmount.isEmpty || rawDesc.isEmpty) continue;

        final parsedAmount = int.tryParse(rawAmount);
        final parsedDate = DateTime.tryParse(rawDate);

        if (parsedAmount == null || parsedDate == null) continue;

        final TransactionType type = (rawType == "수입")
            ? TransactionType.income
            : TransactionType.expense;

        items.add(
          LedgerItem(
            date: parsedDate,
            type: type,
            description: rawDesc,
            amount: parsedAmount,
            category: rawCategory.isNotEmpty ? rawCategory : "미분류",
            payMethod: (rawPayMethod != "-" && rawPayMethod.isNotEmpty) ? rawPayMethod : null,
            memo: rawMemo ?? "",
          ),
        );
      }

      return items;
    } on sheets.DetailedApiRequestError catch (e) {
      AppLogger.i("⚠️ [$monthSheetName] 시트 읽기 실패 (${e.status}): ${e.message}");
      return [];
    } catch (e) {
      AppLogger.i("⚠️ [$monthSheetName] 내역 조회 중 예외 발생: $e");
      return [];
    }
  }
}

@Deprecated('Use LedgerDataService instead')
class HouseholdSheetService extends LedgerDataService {}
