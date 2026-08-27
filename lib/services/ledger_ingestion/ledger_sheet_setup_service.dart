import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


// ============================================================================
// 📊 가계부 구글 드라이브 및 스프레드시트 통합 관리 서비스 클래스
// ============================================================================
class SpreadsheetService {
final CategoryMapper categoryMapper = CategoryMapper();
  final LedgerCacheManager cacheManager = LedgerCacheManager();
  final Map<int, Future<String?>> _spreadsheetInitFutures = {};

  /// 서비스 초기화 시 JSON 설정 파일 및 구글 드라이브 시트 목록 사전 스캔
  Future<void> init(
    AuthClient client, [
    String filePath = 'assets/ledger_ingestion_info.json',
  ]) async {
    await categoryMapper.loadCategoryJson(filePath);
    final driveApi = drive.DriveApi(client);

    // 1. 리팩터링된 Repository 객체 생성
    final folderRepo = DriveFolderService(driveApi);
    final sheetRepo = SpreadSheetService(driveApi);

    // 2. Repository 전달
    await cacheManager.initializeAllSheets(
      folderRepo: folderRepo,
      sheetRepo: sheetRepo,
    );
  }

  /// 특정 연도 가계부 설정 (타 계정용 등 생성 방지 옵션 createIfNotFound 추가)
  Future<String?> setupLedgerSpreadsheetForYear(
    AuthClient client,
    int year, {
    bool createIfNotFound = true,
  }) async {
    final cachedId = cacheManager.getSpreadsheetId(year);
    if (cachedId != null) {
      return cachedId;
    }

    if (_spreadsheetInitFutures.containsKey(year)) {
      AppLogger.i("💡 [$year년] 시트 확인 작업 진행 중...");
      return await _spreadsheetInitFutures[year]!;
    }

    final initFuture = _setupLedgerSpreadsheetForYearInternal(
      client,
      year,
      createIfNotFound: createIfNotFound,
    );
    _spreadsheetInitFutures[year] = initFuture;

    try {
      final spreadsheetId = await initFuture;
      if (spreadsheetId != null) {
        cacheManager.registerSpreadsheetId(year, spreadsheetId);
      }
      return spreadsheetId;
    } finally {
      _spreadsheetInitFutures.remove(year);
    }
  }

  Future<String?> _setupLedgerSpreadsheetForYearInternal(
      AuthClient client,
      int year, {
      required bool createIfNotFound,
    }) async {
      if (!categoryMapper.isLoaded) {
        await categoryMapper.loadCategoryJson();
      }

      final driveApi = drive.DriveApi(client);
      final sheetsApi = sheets.SheetsApi(client);
      final folderRepo = DriveFolderService(driveApi);

      const folderName = "가계부";
      String? folderId;

      // 1. 기존 폴더 조회
      folderId = await folderRepo.getFolderId(folderName);

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
        AppLogger.i("⚠️ '$fileName' 파일이 존재하지 않으며, 타 계정이므로 신규 생성을 진행하지 않습니다.");
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