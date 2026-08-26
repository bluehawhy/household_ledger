import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/ledger_ingestion/entry_input_service.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_sheet_setup_service.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 연도별 시트 ID 캐싱/관리 클래스
// ============================================================================
class LedgerCacheManager {
  final Map<String, String> _folderIdMap = {};
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  bool get isInitialized => _folderIdMap.isNotEmpty;

  /// 폴더 ID 조회 및 캐싱 (Folder Repository 이용)
  Future<String> getFolderId(
    DriveFolderRepository folderRepo, {
    String folderName = "가계부",
  }) async {
    if (!_folderIdMap.containsKey(folderName)) {
      _folderIdMap[folderName] = await folderRepo.getOrCreateFolder(folderName);
    }
    return _folderIdMap[folderName]!;
  }

  /// 모든 연도별 시트 목록 스캔 및 캐싱 (Folder & Sheet Repository 이용)
  Future<void> initializeAllSheets({
    required DriveFolderRepository folderRepo,
    required DriveSheetRepository sheetRepo,
    String folderName = "가계부",
  }) async {
    final folderId = await getFolderId(folderRepo, folderName: folderName);
    
    final yearSheets = await sheetRepo.getYearlySpreadsheets(
      folderId: folderId,
      folderName: folderName,
    );

    _yearToSpreadsheetIdMap.clear();
    _yearToSpreadsheetIdMap.addAll(yearSheets);

    AppLogger.i("[$folderName] 연도별 시트 캐시 완료: $_yearToSpreadsheetIdMap");
  }

  /// 특정 연도의 시트 ID 가져오기 (캐시에서 읽기)
  String? getSpreadsheetId(int year) => _yearToSpreadsheetIdMap[year];

  /// 신규 생성된 연도 시트 ID 수동 등록
  void registerSpreadsheetId(int year, String spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

  /// 캐시 전체 초기화
  void clear() {
    _folderIdMap.clear();
    _yearToSpreadsheetIdMap.clear();
  }
}



// ============================================================================
/// 구글 드라이브 시트(스프레드시트) 조회 전담 클래스
// ============================================================================
class DriveSheetRepository {
  final drive.DriveApi _driveApi;

  DriveSheetRepository(this._driveApi);

  /// 1️⃣ 특정 폴더 내의 모든 시트 목록 조회 ({파일명 : 시트 ID})
  Future<Map<String, String>> getSpreadsheetsInFolder({
    required String folderId,
  }) async {
    final sheetMap = <String, String>{};
    final query =
        "'$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";

    final fileList = await _driveApi.files.list(
      q: query,
      $fields: "files(id, name)",
    );

    if (fileList.files != null) {
      for (var file in fileList.files!) {
        if (file.name != null && file.id != null) {
          sheetMap[file.name!] = file.id!;
        }
      }
    }

    AppLogger.i("폴더(ID: $folderId) 내 시트 목록: $sheetMap");
    return sheetMap;
  }

  /// 2️⃣ 특정 폴더 내에서 연도 패턴이 맞는 시트 목록만 파싱하여 가져오기 ({연도 : 시트 ID})
  /// 예: '가계부_2024' -> 2024 : spreadsheetId
  Future<Map<int, String>> getYearlySpreadsheets({
    required String folderId,
    required String folderName,
  }) async {
    final sheetMap = await getSpreadsheetsInFolder(folderId: folderId);
    final yearToIdMap = <int, String>{};

    final regExp = RegExp(RegExp.escape(folderName) + r'_(\d{4})');

    sheetMap.forEach((fileName, fileId) {
      final match = regExp.firstMatch(fileName);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        yearToIdMap[year] = fileId;
      }
    });

    return yearToIdMap;
  }
}


// ============================================================================
// 스프레드시트 내 데이터 전달
// ============================================================================
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

// ============================================================================
// 💳 가계부 거래 데이터 CRUD 서비스
// ============================================================================
class LedgerDataService {
  final LedgerSheetSetupService sheetSetupService;

  LedgerDataService({LedgerSheetSetupService? sheetSetupService})
      : sheetSetupService = sheetSetupService ?? LedgerSheetSetupService();

  CategoryMapper get categoryMapper => sheetSetupService.categoryMapper;

  static const List<String> defaultHeader = [
    "날짜", "거래유형", "거래 수단", "분류", "내용", "금액", "메모"
  ];

  Future<void> init(AuthClient client) async {
    await sheetSetupService.init(client);
  }

  // ==========================================================================
  // 🔵 단일 항목 입력 로직
  // ==========================================================================
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

    // 기존 데이터 읽어서 중복 여부 확인
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
        updatedNewItem.category ?? "미분류",
        updatedNewItem.description,
        updatedNewItem.amount,
        updatedNewItem.memo ?? "",
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
  // 🟢 [기능 C] 월별 수입 / 지출 내역 조회 로직
  // ==========================================================================

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

@Deprecated('Use LedgerSheetSetupService and LedgerDataService instead')
class HouseholdSheetService extends LedgerDataService {}


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


class GoogleSpreadsheetService {
  final drive.DriveApi _driveApi;

  GoogleSpreadsheetService(AuthClient client)
      : _driveApi = drive.DriveApi(client);

  /// 특정 파일(스프레드시트) 또는 폴더를 특정 이메일 사용자와 공유합니다.
  /// 
  /// - 이미 동일한 권한이 존재하는 경우: API 호출을 생략하고 기존 권한 객체를 반환합니다.
  /// - 권한 변경이 필요한 경우: [permissions.update]를 수행합니다.
  /// - 기존 권한이 없는 경우: [permissions.create]로 새로운 권한을 생성합니다.
  Future<drive.Permission> shareFileOrFolder({
    required String fileOrFolderId,
    required String email,
    String role = 'writer', // 기본값: 편집자 권한
    bool sendNotificationEmail = true,
  }) async {
    try {
      // 1. 기존 공유 권한 목록 조회
      final permissionsList = await _driveApi.permissions.list(
        fileOrFolderId,
        $fields: 'permissions(id, type, role, emailAddress)',
      );

      // 2. 입력된 이메일과 일치하는 기존 권한 찾기
      drive.Permission? existingPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            existingPermission = p;
            break;
          }
        }
      }

      // 3. 기존 권한 상태에 따른 조건부 처리
      if (existingPermission != null) {
        // CASE 3-1: 동일한 권한이 이미 존재 -> 생략
        if (existingPermission.role == role) {
          print('ℹ️ [$email] 사용자에게 이미 동일한 권한($role)이 부여되어 있습니다. 공유를 생략합니다.');
          return existingPermission;
        }

        // CASE 3-2: 권한 수준 변경 필요 -> update 호출
        print('🔄 [$email] 기존 권한(${existingPermission.role})을 새 권한($role)으로 업데이트합니다.');
        final updatedPermission = drive.Permission()..role = role;

        final result = await _driveApi.permissions.update(
          updatedPermission,
          fileOrFolderId,
          existingPermission.id!,
        );

        print('✅ 권한 업데이트 성공: ${result.id} ($email -> $role)');
        return result;
      }

      // CASE 3-3: 기존 권한 없음 -> 새로 생성
      print('➕ [$email] 새 사용자 공유 권한($role)을 생성합니다.');
      final newPermission = drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email;

      final result = await _driveApi.permissions.create(
        newPermission,
        fileOrFolderId,
        sendNotificationEmail: sendNotificationEmail,
      );

      print('✅ 성공적으로 공유되었습니다: ${result.id} ($email -> $role)');
      return result;

    } catch (e) {
      print('❌ 시트/폴더 공유 작업 실패: $e');
      rethrow;
    }
      }
  /// 특정 파일(스프레드시트) 또는 폴더에서 특정 이메일 사용자의 공유 권한을 제거합니다.
  /// 
  /// - [fileOrFolderId]: 대상 파일 또는 폴더 ID
  /// - [email]: 권한을 제거할 대상자의 이메일 주소
  /// - 상속된 권한일 경우 limitedAccess 패턴을 적용합니다.
  Future<bool> removeShare({
    required String fileOrFolderId,
    required String email,
  }) async {
    try {
      // 1. 기존 공유 권한 목록 조회
      final permissionsList = await _driveApi.permissions.list(
        fileOrFolderId,
        $fields: 'permissions(id, emailAddress, role)',
      );

      // 2. 삭제 대상 이메일에 해당하는 권한(Permission) 찾기
      drive.Permission? targetPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            targetPermission = p;
            break;
          }
        }
      }

      // 3. 해당 권한이 존재하는 경우 처리
      if (targetPermission != null && targetPermission.id != null) {
        try {
          // 우선 일반적인 직접 권한 삭제 시도
          await _driveApi.permissions.delete(
            fileOrFolderId,
            targetPermission.id!,
          );
          print('🗑️ [$email] 사용자의 공유 권한을 성공적으로 제거했습니다.');
          return true;
        } on drive.DetailedApiRequestError catch (e) {
          // 403 에러 발생 시 (상속된 권한인 경우)
          if (e.status == 403 && e.message?.contains('inherited') == true) {
            print('⚠️ 상속된 권한이 감지되었습니다. 상위 폴더의 공유를 해제해야 파일 접근 권한이 상속 해제됩니다.');
            print('💡 (참고: 상위 폴더 공유를 해제하려면 해당 폴더 ID로 removeShare를 실행하세요.)');
            return false;
          }
          rethrow;
        }
      } else {
        print('ℹ️ [$email] 사용자는 기존 공유 대상에 존재하지 않습니다.');
        return false;
      }
    } catch (e) {
      print('❌ 공유 권한 제거 실패: $e');
      rethrow;
    }
  }



}








