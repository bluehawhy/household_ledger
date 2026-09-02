import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_row_mapper.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


// ============================================================================
// 📊 가계부 구글 드라이브 및 스프레드시트 통합 관리 서비스 클래스
// ============================================================================
/// 연도별 가계부 파일과 월별 시트를 생성·조회·초기화한다.
class LedgerSpreadsheetService {
  final CategoryMapper categoryMapper = CategoryMapper();
  final LedgerCacheManager cacheManager = LedgerCacheManager();
  final Map<String, Future<String?>> _spreadsheetInitFutures = {};
  String? _currentUserEmail;

  /// 초기화 작업의 중복 실행을 막기 위한 Future.
  Future<void>? _initializationFuture;

  /// 서비스 초기화가 완료되었는지 여부.
  bool get isInitialized => _initializationFuture == null
      ? false
      : cacheManager.isInitialized;

  bool isCurrentAccount(String? accountEmail) {
    return accountEmail == null ||
        accountEmail.toLowerCase() == _currentUserEmail?.toLowerCase();
  }

  /// 서비스 초기화 시 JSON 설정 파일 및 구글 드라이브 시트 목록을 사전 스캔한다.
  Future<void> init(
    AuthClient client, [
    String filePath = 'assets/ledger_ingestion_info.json',
  ]) async {
    // 동일 서비스 인스턴스에서 동시에 여러 번 초기화하지 않는다.
    if (_initializationFuture != null) {
      await _initializationFuture;
      return;
    }

    final future = _initialize(client, filePath);
    _initializationFuture = future;

    try {
      await future;
    } catch (_) {
      // 초기화 실패 시 다음 호출에서 재시도할 수 있도록 상태를 되돌린다.
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<void> _initialize(
    AuthClient client,
    String filePath,
  ) async {
    AppLogger.i("📁 가계부 Drive/Spreadsheet 전체 초기화 시작");

    await categoryMapper.loadCategoryJson(filePath);
    final driveApi = drive.DriveApi(client);

    final folderRepo = DriveFolderService(driveApi);
    final sheetRepo = DriveSheetService(driveApi);
    final currentUserEmail = await folderRepo.getUserEmail();
    _currentUserEmail = currentUserEmail;

    AppLogger.i("📁 현재 Google 계정: $currentUserEmail");

    // 내 계정 + 공유받은 모든 가계부 폴더와 그 안의 스프레드시트를
    // 한 번에 스캔해서 캐시에 저장한다.
    await cacheManager.initializeAllSheets(
      folderRepo: folderRepo,
      sheetRepo: sheetRepo,
      accountEmail: currentUserEmail,
      folderName: "가계부",
    );

    AppLogger.i(
      "📁 전체 가계부 폴더: ${cacheManager.cachedAccountEmails.map((email) => MapEntry(email, cacheManager.getFoldersByAccount(email))).toList()}",
    );
    AppLogger.i(
      "📊 전체 가계부 스프레드시트: ${cacheManager.allSpreadsheetIds}",
    );
    AppLogger.i("📁 가계부 Drive/Spreadsheet 전체 초기화 완료");
  }

  /// 시트 조회/생성 전에 초기화가 반드시 완료되도록 보장한다.
  Future<void> _ensureInitialized(AuthClient client) async {
    if (isInitialized) {
      return;
    }

    AppLogger.i("🔄 가계부 캐시가 초기화되지 않아 전체 목록 스캔을 시작합니다.");
    await init(client);
  }

  /// 특정 연도 가계부 설정 (타 계정용 등 생성 방지 옵션 createIfNotFound 추가)
  Future<String?> setupLedgerSpreadsheetForYear(
    AuthClient client,
    int year, {
    bool createIfNotFound = true,
    String? accountEmail,
  }) async {
    // OverviewPage/기존 호출부에서 init()을 생략하더라도
    // 여기서 전체 폴더/스프레드시트 캐시를 먼저 준비한다.
    await _ensureInitialized(client);

    final cachedId = accountEmail == null
        ? cacheManager.getSpreadsheetId(year)
        : cacheManager.getSpreadsheetIdForAccount(
            accountEmail: accountEmail,
            year: year,
          );
    if (cachedId != null) {
      return cachedId;
    }

    final spreadsheetCacheKey = '${accountEmail ?? 'my'}_$year';
    if (_spreadsheetInitFutures.containsKey(spreadsheetCacheKey)) {
      AppLogger.i("💡 [$year년] 시트 확인 작업 진행 중...");
      return await _spreadsheetInitFutures[spreadsheetCacheKey]!;
    }

    final initFuture = _setupLedgerSpreadsheetForYearInternal(
      client,
      year,
      createIfNotFound: createIfNotFound,
      accountEmail: accountEmail,
    );
    _spreadsheetInitFutures[spreadsheetCacheKey] = initFuture;

    try {
      final spreadsheetId = await initFuture;
      if (spreadsheetId != null && accountEmail == null) {
        cacheManager.registerSpreadsheetId(year, spreadsheetId);
      }
      return spreadsheetId;
    } finally {
      _spreadsheetInitFutures.remove(spreadsheetCacheKey);
    }
  }

  Future<String?> _setupLedgerSpreadsheetForYearInternal(
      AuthClient client,
      int year, {
      required bool createIfNotFound,
      String? accountEmail,
    }) async {
      if (!categoryMapper.isLoaded) {
        await categoryMapper.loadCategoryJson();
      }

      final driveApi = drive.DriveApi(client);
      final sheetsApi = sheets.SheetsApi(client);
      final folderRepo = DriveFolderService(driveApi);

      const folderName = "가계부";
      String? folderId;

      if (accountEmail != null) {
        folderId = cacheManager.getFoldersByAccount(accountEmail)?[folderName];
        if (folderId == null) {
          AppLogger.i("⚠️ [$accountEmail] '$folderName' 공유 폴더를 찾지 못했습니다.");
          return null;
        }
      }

      // 1. 기존 폴더 조회
      folderId ??= await folderRepo.getFolderId(folderName);

      // 2. 폴더가 없고 createIfNotFound가 false인 경우 (타 계정 등) 진행 불가
      if (folderId == null && !createIfNotFound) {
        AppLogger.i("⚠️ '$folderName' 폴더가 존재하지 않으며, 타 계정이므로 신규 폴더 및 파일 생성을 진행하지 않습니다.");
        return null;
      }

      // 3. 폴더가 없는 경우 내 계정이면 신규 생성
      if (folderId == null) {
        try {
          folderId = await folderRepo.createFolder(folderName);
        } catch (e) {
          AppLogger.e("가계부 폴더 생성에 실패했습니다: $e");
          return null;
        }
      }

      final fileName = "가계부_$year";

      // 4. 기존 스프레드시트 조회
      final existingId = await _getSpreadsheet(driveApi, folderId, fileName);
      if (existingId != null) {
        return existingId;
      }

      // 5. 스프레드시트가 없고 createIfNotFound가 false인 경우 생성하지 않음
      if (!createIfNotFound) {
        AppLogger.i("⚠️ '$fileName' 파일이 존재하지 않아 신규 생성을 진행하지 않습니다.");
        return null;
      }

      // 6. 신규 스프레드시트 생성
      return await _createSpreadsheet(
        driveApi,
        sheetsApi,
        folderId,
        fileName,
      );
    }

  /// 🔍 1. 기존 스프레드시트 파일 ID 조회
  Future<String?> _getSpreadsheet(
    drive.DriveApi driveApi,
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

    return null;
  }

  /// ➕ 2. 신규 스프레드시트 생성 및 초기 세팅
  Future<String> _createSpreadsheet(
    drive.DriveApi driveApi,
    sheets.SheetsApi sheetsApi,
    String folderId,
    String fileName,
  ) async {
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

    // 4. 모든 월별 시트에 거래 데이터 헤더 생성
    for (int month = 1; month <= 12; month++) {
      data.add(
        sheets.ValueRange(
          range: "'$month월'!A1:H1",
          values: [LedgerRowMapper.defaultHeader],
        ),
      );
    }

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
