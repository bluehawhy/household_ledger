import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 연도별 시트 ID를 관리/캐싱하는 클래스
// ============================================================================
class LedgerCacheManager {
  // Map 구조로 관리하여 여러 폴더를 다룰 때 발생할 수 있는 혼동 및 버그 방지
  final Map<String, String> _folderIdMap = {};
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  bool get isInitialized => _folderIdMap.isNotEmpty;

  /// 앱 초기화 시 구글 드라이브의 특정 폴더 내 모든 연도별 시트 목록을 한 번에 스캔 및 캐싱
  Future<void> initializeAllSheets(drive.DriveApi driveApi, {String folderName = "가계부"}) async {
    final folderId = await getFolderId(driveApi, folderName: folderName);

    final query = "'$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
    final fileList = await driveApi.files.list(q: query);

    _yearToSpreadsheetIdMap.clear();

    if (fileList.files != null) {
      // 💡 동적 folderName 정규식 적용 (예: "가계부_2026" or "차계부_2026")
      final regExp = RegExp(RegExp.escape(folderName) + r'_(\d{4})');

      for (var file in fileList.files!) {
        if (file.name != null && file.id != null) {
          final match = regExp.firstMatch(file.name!);
          if (match != null) {
            final year = int.parse(match.group(1)!);
            _yearToSpreadsheetIdMap[year] = file.id!;
          }
        }
      }
    }
    AppLogger.i("[$folderName] 연도별 시트 캐시 완료: $_yearToSpreadsheetIdMap");
  }

  /// 특정 연도의 시트 ID 가져오기 (캐시에 존재하면 API 호출 없이 반환)
  String? getSpreadsheetId(int year) {
    return _yearToSpreadsheetIdMap[year];
  }

  /// 신규 생성된 연도 시트 ID 등록
  void registerSpreadsheetId(int year, String spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

  /// 폴더 ID 반환 (Map 기반 캐싱 적용)
  Future<String> getFolderId(drive.DriveApi driveApi, {String folderName = "가계부"}) async {
    if (!_folderIdMap.containsKey(folderName)) {
      _folderIdMap[folderName] = await _getOrCreateFolder(driveApi, folderName);
    }
    return _folderIdMap[folderName]!;
  }

  /// 폴더 생성/조회 헬퍼
  Future<String> _getOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
    AppLogger.i("📁 '$folderName' 폴더 확인 중...");
    final query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      AppLogger.i("  └ 💡 기존 폴더 사용 (ID: $id)");
      return id;
    }

    AppLogger.i("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final createdFolder = await driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return createdFolder.id!;
  }

  /// 캐시 초기화
  void clear() {
    _folderIdMap.clear();
    _yearToSpreadsheetIdMap.clear();
  }
}

// ============================================================================
// 📊 가계부 구글 드라이브 및 스프레드시트 통합 관리 서비스 클래스
// ============================================================================
class LedgerSheetSetupService {
  final CategoryMapper categoryMapper = CategoryMapper();
  final LedgerCacheManager cacheManager = LedgerCacheManager();
  final Map<int, Future<String>> _spreadsheetInitFutures = {};

  /// 서비스 초기화 시 JSON 설정 파일 및 구글 드라이브 시트 목록 사전 스캔
  Future<void> init(
    AuthClient client, [
    String filePath = 'assets/ledger_ingestion_info.json',
  ]) async {
    await categoryMapper.loadCategoryJson(filePath);
    final driveApi = drive.DriveApi(client);
    await cacheManager.initializeAllSheets(driveApi);
  }

  /// 특정 연도 가계부 설정 (캐시 체크 및 동시성 락 적용)
  Future<String> setupLedgerSpreadsheetForYear(AuthClient client, int year) async {
    final cachedId = cacheManager.getSpreadsheetId(year);
    if (cachedId != null) {
      return cachedId;
    }

    if (_spreadsheetInitFutures.containsKey(year)) {
      AppLogger.i("💡 [$year년] 시트 확인/생성 작업이 이미 진행 중이므로 완료를 기다립니다.");
      return await _spreadsheetInitFutures[year]!;
    }

    final initFuture = _setupLedgerSpreadsheetForYearInternal(client, year);
    _spreadsheetInitFutures[year] = initFuture;

    try {
      final spreadsheetId = await initFuture;
      return spreadsheetId;
    } finally {
      _spreadsheetInitFutures.remove(year);
    }
  }

  Future<String> _setupLedgerSpreadsheetForYearInternal(AuthClient client, int year) async {
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final driveApi = drive.DriveApi(client);
    final sheetsApi = sheets.SheetsApi(client);

    final folderId = await cacheManager.getFolderId(driveApi);
    final fileName = "가계부_$year";

    final spreadsheetId = await _getOrCreateSpreadsheet(
      driveApi,
      sheetsApi,
      folderId,
      fileName,
    );

    cacheManager.registerSpreadsheetId(year, spreadsheetId);
    return spreadsheetId;
  }

  Future<String> _getOrCreateSpreadsheet(
    drive.DriveApi driveApi,
    sheets.SheetsApi sheetsApi,
    String folderId,
    String fileName,
  ) async {
    AppLogger.i("📊 '$fileName' 파일 확인 중...");

    final query =
        "name = '$fileName' and '$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      AppLogger.i("  └ 💡 기존 파일이 이미 존재합니다. (ID: $id)");
      return id;
    }

    AppLogger.i("  └ ➕ '$fileName' 파일이 없어 새 시트를 생성합니다...");

    final List<sheets.Sheet> sheetsList = [
      sheets.Sheet(properties: sheets.SheetProperties(title: 'Overview')),
    ];

    for (int month = 1; month <= 12; month++) {
      sheetsList.add(
        sheets.Sheet(properties: sheets.SheetProperties(title: '$month월')),
      );
    }

    final spreadsheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: fileName),
      sheets: sheetsList,
    );

    final createdSpreadsheet = await sheetsApi.spreadsheets.create(spreadsheet);
    final spreadsheetId = createdSpreadsheet.spreadsheetId!;

    await driveApi.files.update(
      drive.File(),
      spreadsheetId,
      addParents: folderId,
    );

    AppLogger.i("  └ 🎨 Overview 안내표, 월별 수식 및 통합 헤더를 입력하는 중...");
    await _initializeAllSheets(sheetsApi, spreadsheetId);

    return spreadsheetId;
  }

  Future<void> _initializeAllSheets(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
  ) async {
    List<sheets.ValueRange> data = [];

    // 1. Overview 안내표 작성
    final List<List<String>> overviewGuide = [
      ["📌 [수입 분류 안내]", ""],
    ];

    categoryMapper.incomeCategories.forEach((cat, keywords) {
      overviewGuide.add([cat, keywords.join(", ")]);
    });

    overviewGuide.add(["", ""]);
    overviewGuide.add(["📌 [지출 분류 안내]", ""]);

    categoryMapper.expenseCategories.forEach((cat, keywords) {
      overviewGuide.add([cat, keywords.join(", ")]);
    });

    final int guideEndRow = overviewGuide.length;
    data.add(
      sheets.ValueRange(
        range: "'Overview'!A1:B$guideEndRow",
        values: overviewGuide,
      ),
    );

    // 2. 수입 종합 통계표 생성
    final monthsHeader = [
      "수입분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];

    final incomeList = categoryMapper.incomeCategories.keys.toList();
    List<List<String>> incomeTable = [monthsHeader];

    final int incomeStartRow = guideEndRow + 3;

    for (int i = 0; i < incomeList.length; i++) {
      final category = incomeList[i];
      final rowNum = incomeStartRow + 1 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIFS('$m월'!\$F:\$F, '$m월'!\$B:\$B, \"수입\", '$m월'!\$D:\$D, \$A$rowNum)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      incomeTable.add(row);
    }

    final int incomeFirstDataRow = incomeStartRow + 1;
    final int incomeLastDataRow = incomeStartRow + incomeList.length;

    List<String> incomeTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      incomeTotalRow.add("=SUM($colLetter$incomeFirstDataRow:$colLetter$incomeLastDataRow)");
    }
    incomeTable.add(incomeTotalRow);

    final int incomeEndRow = incomeStartRow + incomeTable.length - 1;

    data.add(
      sheets.ValueRange(
        range: "'Overview'!A$incomeStartRow:N$incomeEndRow",
        values: incomeTable,
      ),
    );

    // 3. 지출 종합 통계표 생성
    final expenseList = categoryMapper.expenseCategories.keys.toList();
    final expenseMonthsHeader = [
      "지출분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];
    List<List<String>> expenseTable = [expenseMonthsHeader];

    final int expenseStartRow = incomeEndRow + 3;

    for (int i = 0; i < expenseList.length; i++) {
      final category = expenseList[i];
      final rowNum = expenseStartRow + 1 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIFS('$m월'!\$F:\$F, '$m월'!\$B:\$B, \"지출\", '$m월'!\$D:\$D, \$A$rowNum)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      expenseTable.add(row);
    }

    final int expenseFirstDataRow = expenseStartRow + 1;
    final int expenseLastDataRow = expenseStartRow + expenseList.length;

    List<String> expenseTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      expenseTotalRow.add("=SUM($colLetter$expenseFirstDataRow:$colLetter$expenseLastDataRow)");
    }
    expenseTable.add(expenseTotalRow);

    final int expenseEndRow = expenseStartRow + expenseTable.length - 1;

    data.add(
      sheets.ValueRange(
        range: "'Overview'!A$expenseStartRow:N$expenseEndRow",
        values: expenseTable,
      ),
    );

    final batchUpdateRequest = sheets.BatchUpdateValuesRequest(
      valueInputOption: "USER_ENTERED",
      data: data,
    );

    await sheetsApi.spreadsheets.values.batchUpdate(
      batchUpdateRequest,
      spreadsheetId,
    );
  }
}

// ============================================================================
// 💳 가계부 거래 데이터 CRUD 서비스
// ============================================================================
class LedgerDataService {
  // 💡 의존성 주입(DI) 적용: 외부에서 전달받거나 기본 인스턴스 사용
  final LedgerSheetSetupService sheetSetupService;
  final CategoryMapper categoryMapper = CategoryMapper();

  LedgerDataService({LedgerSheetSetupService? sheetSetupService})
      : sheetSetupService = sheetSetupService ?? LedgerSheetSetupService();

  static const List<String> defaultHeader = [
    "날짜", "거래유형", "거래 수단", "분류", "내용", "금액", "메모"
  ];

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  // ==========================================================================
  // 🔵 단일 항목 입력 로직
  // ==========================================================================
  Future<void> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
    if (item.amount <= 0) {
      AppLogger.i("⚠️ [0원 패스] [${item.formattedDate}] '${item.description}' 금액이 0원이므로 저장하지 않습니다.");
      return;
    }
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(client, item.date.year);

    item = item.copyWith(
      category: categoryMapper.getCategory(
        item.description,
        isIncome: item.type == TransactionType.income,
      ),
    );

    final monthSheetName = '${item.date.month}월';
    await _ensureMonthSheetExists(sheetsApi, targetSpreadsheetId, monthSheetName);

    final range = "'$monthSheetName'!A1:G1000";
    List<List<dynamic>> existingRows = [];

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );
      existingRows = response.values ?? [];
    } on sheets.DetailedApiRequestError catch (e) {
      AppLogger.i("⚠️ [$monthSheetName] 시트 읽기 실패 (${e.status}): ${e.message}");
      return;
    } catch (e) {
      AppLogger.i("⚠️ [$monthSheetName] 시트 읽기 중 예외 발생: $e");
      return;
    }

    if (existingRows.isEmpty) {
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(range: "'$monthSheetName'!A1:G1", values: [defaultHeader]),
        targetSpreadsheetId,
        "'$monthSheetName'!A1:G1",
        valueInputOption: "USER_ENTERED",
      );
      existingRows = [defaultHeader];
    }

    if (_checkDuplicate(existingRows, item)) {
      AppLogger.i("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
      return;
    }

    await appendTransactionData(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
      existingRows,
      item,
    );
  }

  // ==========================================================================
  // 🟡 수입 / 지출 내역 수정(업데이트) 로직
  // ==========================================================================
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

    newItem = newItem.copyWith(
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

      final isIncome = newItem.type == TransactionType.income;
      final List<Object?> rowData = [
        newItem.formattedDate,
        isIncome ? "수입" : "지출",
        newItem.payMethod ?? "-",
        newItem.category ?? "미분류",
        newItem.description,
        newItem.amount,
        newItem.memo ?? "",
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
          item.category ?? (isIncome ? '주수입' : '미분류'),
          item.description,
          item.amount,
          item.memo ?? "",
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
      final String spreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(client, year);

      AppLogger.i("🚀 [$year년 $sheetName] ${groupItems.length}개 항목 처리 시작 (Spreadsheet ID: $spreadsheetId)");

      final success = await appendTransactionBatch(
        sheetsApi,
        spreadsheetId,
        sheetName,
        groupItems,
      );

      if (success) {
        totalSuccess += groupItems.length;
      }
    }

    AppLogger.i("📊 [최종 완료] 성공: $totalSuccess건");
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

  // ==========================================================================
  // 🟢 [기능 C] 월별 수입 / 지출 내역 조회 로직 (중복 제거 및 간소화)
  // ==========================================================================

  /// 💡 getMonthlyLedger를 통해 가져온 전체 리스트에서 필터링만 수행
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

  /// 특정 연월의 수입 또는 지출 내역 리스트 조회
  Future<List<LedgerItem>> getMonthlyTransactions({
    required AuthClient client,
    required int year,
    required int month,
    required TransactionType type,
  }) async {
    final allItems = await getMonthlyLedger(client: client, year: year, month: month);
    return allItems.where((item) => item.type == type).toList();
  }

  /// 특정 연월의 전체 거래 내역(수입 + 지출) 단일 진실 공급원(Single Source of Truth)
  Future<List<LedgerItem>> getMonthlyLedger({
    required AuthClient client,
    required int year,
    required int month,
  }) async {
    final sheetsApi = sheets.SheetsApi(client);
    final targetSpreadsheetId = await sheetSetupService.setupLedgerSpreadsheetForYear(client, year);

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

@Deprecated('Use LedgerSheetSetupService and LedgerDataService instead')
class HouseholdSheetService extends LedgerDataService {}

// ============================================================================
// 데이터 전달 클래스 및 수집 서비스
// ============================================================================
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

      final List<String> lines = _textParserService.parseInputLines(rawInput);

      if (lines.isEmpty) {
        return LedgerSubmitResult(
          isSuccess: false,
          errorMessage: '처리할 수 있는 텍스트가 없습니다.',
        );
      }

      int successCount = 0;
      int duplicateCount = 0;
      int failCount = 0;

      if (lines.length == 1) {
        final singleEntryService = SingleEntryService();
        final Map<String, dynamic> itemMap =
            _textParserService.parseSingleLineToMap(lines.first);

        final ParseResult result =
            await singleEntryService.appendParseSingleLine(
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
        final multiEntryService = MultiEntryService();
        final List<Map<String, dynamic>> itemMaps = lines
            .map((line) => _textParserService.parseSingleLineToMap(line))
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

      return LedgerSubmitResult(
        isSuccess: true,
        total: lines.length,
        success: successCount,
        duplicate: duplicateCount,
        fail: failCount,
      );
    } catch (e, stackTrace) {
      AppLogger.i('❌ 업로드 중 에러 발생: $e\n$stackTrace');
      return LedgerSubmitResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }
}