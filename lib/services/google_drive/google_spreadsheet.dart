import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';


// ============================================================================
// JSON 기반 카테고리 자동 매퍼
// ============================================================================
class CategoryMapper {
  // 카테고리명 -> 키워드 리스트 매핑
  Map<String, List<String>> incomeCategories = {};
  Map<String, List<String>> expenseCategories = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> loadCategoryJson([String filePath = 'assets/ledger_ingestion_info.json']) async {
    try {
      final jsonString = await JsonAssetManager.loadJson(filePath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // 💡 단일 리스트 or 중첩 Map 구조에 관계없이 모든 키워드를 Flatten(평탄화) 추출하는 헬퍼 함수
      Map<String, List<String>> parseCategoryStructure(dynamic rawData) {
        final Map<String, List<String>> resultMap = {};

        if (rawData is! Map<String, dynamic>) return resultMap;

        rawData.forEach((key, value) {
          if (value is List) {
            // 1단계 구조인 경우: "급여": ["월급", "급여"]
            resultMap[key] = value.map((e) => e.toString()).toList();
          } else if (value is Map<String, dynamic>) {
            // 2단계 중첩 구조인 경우: "식비": { "식당/외식": ["점심", "식당"] }
            value.forEach((subKey, subValue) {
              if (subValue is List) {
                resultMap[subKey] = subValue.map((e) => e.toString()).toList();
              }
            });
          }
        });

        return resultMap;
      }

      // 수입 분류 파싱
      if (data.containsKey("수입 분류")) {
        incomeCategories = parseCategoryStructure(data["수입 분류"]);
      }

      // 지출 분류 파싱 (2단계 중첩 Map 대응)
      if (data.containsKey("지출 분류")) {
        expenseCategories = parseCategoryStructure(data["지출 분류"]);
      }

      _isLoaded = true;
      print("✅ [CategoryMapper] 카테고리 JSON 데이터 로드 완료! (수입: ${incomeCategories.length}개, 지출: ${expenseCategories.length}개 항목)");
    } catch (e) {
      print("⚠️ [CategoryMapper] JSON 로드/파싱 에러 ($filePath): $e");
      _isLoaded = true; // 실패 시에도 반복 로드 시도를 막기 위해 flag 처리
    }
  }

  /// 적합한 카테고리를 찾아 반환 (예: "맥도날드" 입력 시 -> "식당/외식" 반환)
  String getCategory(String description, {required bool isIncome}) {
    final categories = isIncome ? incomeCategories : expenseCategories;

    for (var entry in categories.entries) {
      final categoryName = entry.key; // 소분류 이름 (예: "식당/외식", "카페/디저트")
      final keywords = entry.value;    // 키워드 리스트 (예: ["맥도날드", "버거킹", ...])

      for (var keyword in keywords) {
        if (keyword.isNotEmpty && description.contains(keyword)) {
          return categoryName;
        }
      }
    }
    return "미분류";
  }
}

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 연도별 시트 ID를 관리/캐싱하는 클래스
// ============================================================================
class LedgerCacheManager {
  String? _folderId;
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  bool get isInitialized => _folderId != null;

  /// 앱 초기화 시 구글 드라이브의 '가계부' 폴더 내 모든 연도별 시트 목록을 한 번에 스캔 및 캐싱
  Future<void> initializeAllSheets(drive.DriveApi driveApi, {String folderName = "가계부"}) async {
    // 1. '가계부' 폴더 ID 가져오기/생성
    _folderId ??= await _getOrCreateFolder(driveApi, folderName);

    // 2. 폴더 내 존재하는 모든 '가계부_YYYY' 파일 일괄 조회
    final query = "'$_folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
    final fileList = await driveApi.files.list(q: query);

    _yearToSpreadsheetIdMap.clear();

    if (fileList.files != null) {
      for (var file in fileList.files!) {
        if (file.name != null && file.id != null) {
          // 파일명에서 연도 추출 (예: "가계부_2026" -> 2026)
          final regExp = RegExp(r'가계부_(\d{4})');
          final match = regExp.firstMatch(file.name!);
          if (match != null) {
            final year = int.parse(match.group(1)!);
            _yearToSpreadsheetIdMap[year] = file.id!;
          }
        }
      }
    }
    print("✅ [LedgerCacheManager] 연도별 시트 캐시 완료: $_yearToSpreadsheetIdMap");
  }

  /// 특정 연도의 시트 ID 가져오기 (캐시에 존재하면 API 호출 없이 0초 반환)
  String? getSpreadsheetId(int year) {
    return _yearToSpreadsheetIdMap[year];
  }

  /// 신규 생성된 연도 시트 ID 등록
  void registerSpreadsheetId(int year, String spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

  /// '가계부' 폴더 ID 반환
  Future<String> getFolderId(drive.DriveApi driveApi, {String folderName = "가계부"}) async {
    _folderId ??= await _getOrCreateFolder(driveApi, folderName);
    return _folderId!;
  }

  /// 폴더 생성/조회 헬퍼
  Future<String> _getOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
    print("\n📁 '가계부' 폴더 확인 중...");
    final query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 폴더 사용 (ID: $id)");
      return id;
    }

    print("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final createdFolder = await driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return createdFolder.id!;
  }

  /// 캐시 초기화
  void clear() {
    _folderId = null;
    _yearToSpreadsheetIdMap.clear();
  }
}

// ============================================================================
// 3. 📊 가계부 구글 드라이브 및 스프레드시트 통합 관리 서비스 클래스
// ============================================================================
class HouseholdSheetService {
  final CategoryMapper categoryMapper = CategoryMapper();
  final LedgerCacheManager cacheManager = LedgerCacheManager(); // 💡 캐시 매니저 도입

  /// 서비스 초기화 시 JSON 설정 파일 및 구글 드라이브 시트 목록 사전 스캔
  Future<void> init(
    AuthClient client, [
    String filePath = 'assets/ledger_ingestion_info.json',
  ]) async {
    await categoryMapper.loadCategoryJson(filePath);
    final driveApi = drive.DriveApi(client);
    await cacheManager.initializeAllSheets(driveApi);
  }

  // ==========================================================================
  // 🟢 [기능 A] 파일 및 시트 구조 생성 및 ID 관리
  // ==========================================================================

  /// [기존 호환용] 현재 연도 기준 가계부 설정
  Future<String> setupLedgerSpreadsheet(AuthClient client) async {
    return await setupLedgerSpreadsheetForYear(client, DateTime.now().year);
  }

  /// [확장용] 특정 연도 가계부 설정 (캐시 체크 적용)
  Future<String> setupLedgerSpreadsheetForYear(AuthClient client, int year) async {
    // 1. 캐시에 존재하면 API 호출 없이 0.001초만에 즉시 반환
    final cachedId = cacheManager.getSpreadsheetId(year);
    if (cachedId != null) {
      return cachedId;
    }

    // 2. 카테고리 로드 상태 안전장치
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final driveApi = drive.DriveApi(client);
    final sheetsApi = sheets.SheetsApi(client);

    final folderId = await cacheManager.getFolderId(driveApi);
    final fileName = "가계부_$year";

    // 3. 신규 시트 생성 또는 구글 드라이브 내 기존 파일 탐색
    final spreadsheetId = await _getOrCreateSpreadsheet(
      driveApi,
      sheetsApi,
      folderId,
      fileName,
    );

    // 4. 캐시 매니저에 ID 저장
    cacheManager.registerSpreadsheetId(year, spreadsheetId);

    return spreadsheetId;
  }

  Future<String> _getOrCreateSpreadsheet(
    drive.DriveApi driveApi,
    sheets.SheetsApi sheetsApi,
    String folderId,
    String fileName,
  ) async {
    print("\n📊 2. '$fileName' 파일 확인 중...");

    final query =
        "name = '$fileName' and '$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 파일이 이미 존재합니다. (ID: $id)");
      return id;
    }

    print("  └ ➕ '$fileName' 파일이 없어 새 시트를 생성합니다...");

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

    print("  └ 🎨 Overview 안내표, 월별 수식 및 헤더를 입력하는 중...");
    await _initializeAllSheets(sheetsApi, spreadsheetId);

    return spreadsheetId;
  }

  Future<void> _initializeAllSheets(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
  ) async {
    List<sheets.ValueRange> data = [];

    // 1. JSON 기반 Overview 안내표 작성
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
        row.add("=SUMIF('$m월'!\$B:\$B, \$A$rowNum, '$m월'!\$D:\$D)");
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
        row.add("=SUMIF('$m월'!\$H:\$H, \$A$rowNum, '$m월'!\$J:\$J)");
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

    // 4. 1~12월 시트 기본 헤더 생성
    for (int month = 1; month <= 12; month++) {
      final sheetName = '$month월';
      data.add(
        sheets.ValueRange(
          range: "'$sheetName'!A1:J1",
          values: [
            [
              "날짜", "수입 분류", "내용", "금액", "",
              "날짜", "지출 수단", "지출 분류", "내용", "금액"
            ]
          ],
        ),
      );
    }

    final request = sheets.BatchUpdateValuesRequest(
      valueInputOption: "USER_ENTERED",
      data: data,
    );

    await sheetsApi.spreadsheets.values.batchUpdate(request, spreadsheetId);
    print("  └ ✅ Overview 통계표 및 범례 작성 완료!");
  }

  // ==========================================================================
  // 🔵 [기능 B] 수입 / 지출 내역 입력 로직
  // ==========================================================================

  Future<void> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final sheetsApi = sheets.SheetsApi(client);

    final targetSpreadsheetId = (spreadsheetId != null && spreadsheetId.isNotEmpty)
        ? spreadsheetId
        : await setupLedgerSpreadsheetForYear(client, item.date.year);

    if (item.category == null || item.category!.isEmpty) {
      item.category = categoryMapper.getCategory(
        item.description,
        isIncome: item.type == TransactionType.income,
      );
    }

    final monthSheetName = '${item.date.month}월';

    await _ensureMonthSheetExists(sheetsApi, targetSpreadsheetId, monthSheetName);

    final range = "'$monthSheetName'!A1:J1000";
    List<List<dynamic>> existingRows = [];

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );
      existingRows = response.values ?? [];
    } on sheets.DetailedApiRequestError catch (e) {
      print("⚠️ [$monthSheetName] 시트 읽기 실패 (${e.status}): ${e.message}");
      return;
    } catch (e) {
      print("⚠️ [$monthSheetName] 시트 읽기 중 예외 발생: $e");
      return;
    }

    if (existingRows.isEmpty) {
      final defaultHeader = [
        "날짜", "수입 분류", "내용", "금액", "", "날짜", "지출 수단", "지출 분류", "내용", "금액"
      ];

      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(range: "'$monthSheetName'!A1:J1", values: [defaultHeader]),
        targetSpreadsheetId,
        "'$monthSheetName'!A1:J1",
        valueInputOption: "USER_ENTERED",
      );

      existingRows = [defaultHeader];
    }

    if (_checkDuplicate(existingRows, item)) {
      print("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
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

  /// 월별 다중 항목 배치 전송 (단 1회의 API 호출로 처리)
  Future<bool> appendTransactionBatch(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<LedgerItem> items,
  ) async {
    if (items.isEmpty) return true;

    try {
      final range = "'$sheetName'!A1:J1000";
      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        range,
      );
      final List<List<dynamic>> existingRows = response.values ?? [];

      if (existingRows.isEmpty) {
        final defaultHeader = [
          "날짜", "수입 분류", "내용", "금액", "", "날짜", "지출 수단", "지출 분류", "내용", "금액"
        ];
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [defaultHeader]),
          spreadsheetId,
          "'$sheetName'!A1:J1",
          valueInputOption: "USER_ENTERED",
        );
        existingRows.add(defaultHeader);
      }

      int lastIncomeRowIdx = 0;
      int lastExpenseRowIdx = 0;

      for (int i = 1; i < existingRows.length; i++) {
        final row = existingRows[i];
        if (row.isNotEmpty && row[0].toString().trim().isNotEmpty) {
          lastIncomeRowIdx = i;
        }
        if (row.length > 5 && row[5].toString().trim().isNotEmpty) {
          lastExpenseRowIdx = i;
        }
      }

      final List<List<Object?>> incomeRows = [];
      final List<List<Object?>> expenseRows = [];

      for (final item in items) {
        final formattedDate = item.formattedDate;
        final incomeKeywords = ["수입", "입금", "월급", "환불"];
        final String categoryStr = item.category ?? '';
        final bool isIncome = item.type == TransactionType.income ||
            incomeKeywords.any((keyword) => categoryStr.contains(keyword));

        if (isIncome) {
          incomeRows.add([
            formattedDate,
            item.category ?? '주수입',
            item.description,
            item.amount,
          ]);
        } else {
          expenseRows.add([
            formattedDate,
            item.payMethod ?? '카드',
            item.category ?? '미분류',
            item.description,
            item.amount,
          ]);
        }
      }

      final List<sheets.ValueRange> valueRangesToUpdate = [];

      if (incomeRows.isNotEmpty) {
        final startRow = lastIncomeRowIdx + 2;
        final endRow = startRow + incomeRows.length - 1;
        valueRangesToUpdate.add(
          sheets.ValueRange(
            range: "'$sheetName'!A$startRow:D$endRow",
            values: incomeRows,
          ),
        );
      }

      if (expenseRows.isNotEmpty) {
        final startRow = lastExpenseRowIdx + 2;
        final endRow = startRow + expenseRows.length - 1;
        valueRangesToUpdate.add(
          sheets.ValueRange(
            range: "'$sheetName'!F$startRow:J$endRow",
            values: expenseRows,
          ),
        );
      }

      if (valueRangesToUpdate.isNotEmpty) {
        final batchRequest = sheets.BatchUpdateValuesRequest(
          valueInputOption: "USER_ENTERED",
          data: valueRangesToUpdate,
        );

        await sheetsApi.spreadsheets.values.batchUpdate(
          batchRequest,
          spreadsheetId,
        );
      }

      print("✅ [$sheetName] 배치 입력 완료 (수입: ${incomeRows.length}건, 지출: ${expenseRows.length}건)");
      return true;
    } catch (e) {
      print("❌ [appendTransactionBatch] ($sheetName) 배치 전송 실패: $e");
      return false;
    }
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
      print("➕ '$sheetName' 시트가 존재하지 않아 새로 생성합니다...");

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
        range: "'$sheetName'!A1:J1",
        values: [
          [
            "날짜", "수입 분류", "내용", "금액", "",
            "날짜", "지출 수단", "지출 분류", "내용", "금액"
          ]
        ],
      );

      await sheetsApi.spreadsheets.values.update(
        headerValueRange,
        spreadsheetId,
        "'$sheetName'!A1:J1",
        valueInputOption: "USER_ENTERED",
      );
    }
  }

  bool _checkDuplicate(List<List<dynamic>> rows, LedgerItem item) {
    if (rows.length <= 1) return false;

    final isIncome = item.type == TransactionType.income;
    final dateIdx = isIncome ? 0 : 5;
    final descIdx = isIncome ? 2 : 8;
    final amountIdx = isIncome ? 3 : 9;

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];

      if (row.length > amountIdx) {
        final existingDate = row[dateIdx].toString().trim();
        final existingDesc = row[descIdx].toString().trim();
        final existingAmount = row[amountIdx].toString().replaceAll(',', '').trim();

        if (existingDate == item.formattedDate &&
            existingDesc == item.description &&
            existingAmount == item.amount.toString()) {
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
    if (existingRows.isEmpty) return false;

    final isIncome = item.type == TransactionType.income;
    final headerRow = existingRows[0].map((e) => e.toString().trim()).toList();

    final dateIndices = <int>[];
    final descIndices = <int>[];
    final amountIndices = <int>[];

    for (int i = 0; i < headerRow.length; i++) {
      if (headerRow[i] == "날짜") dateIndices.add(i);
      if (headerRow[i] == "내용") descIndices.add(i);
      if (headerRow[i] == "금액") amountIndices.add(i);
    }

    final targetIndex = isIncome ? 0 : 1;

    if (dateIndices.length <= targetIndex ||
        descIndices.length <= targetIndex ||
        amountIndices.length <= targetIndex) {
      print("⚠️ [$sheetName] ${isIncome ? '첫 번째(수입)' : '두 번째(지출)'} 헤더를 찾을 수 없습니다.");
      return false;
    }

    final dateIdx = dateIndices[targetIndex];
    final descIdx = descIndices[targetIndex];
    final amountIdx = amountIndices[targetIndex];

    final rowData = isIncome
        ? [
            item.formattedDate,
            item.category,
            item.description,
            item.amount,
          ]
        : [
            item.formattedDate,
            item.payMethod ?? "현금",
            item.category,
            item.description,
            item.amount,
          ];

    int lastFilledRowIndex = 0;

    for (int i = 1; i < existingRows.length; i++) {
      final row = existingRows[i];

      if (row.length > dateIdx && row[dateIdx].toString().trim().isNotEmpty) {
        lastFilledRowIndex = i;

        if (row.length > descIdx && row.length > amountIdx) {
          final existingDate = row[dateIdx].toString().trim();
          final existingDesc = row[descIdx].toString().trim();
          final existingAmount = row[amountIdx].toString().replaceAll(',', '').trim();

          if (existingDate == item.formattedDate.trim() &&
              existingDesc == item.description.trim() &&
              existingAmount == item.amount.toString().trim()) {
            print("⚠️ 중복 데이터 감지되어 스킵됨: [${item.formattedDate}] ${item.description} (${item.amount}원)");
            return false;
          }
        }
      }
    }

    final targetRow = (lastFilledRowIndex == 0) ? 2 : lastFilledRowIndex + 2;

    String colToLetter(int colIndex) {
      String letter = "";
      int tempCol = colIndex;
      while (tempCol >= 0) {
        letter = String.fromCharCode((tempCol % 26) + 65) + letter;
        tempCol = (tempCol ~/ 26) - 1;
      }
      return letter;
    }

    final startColLetter = colToLetter(dateIdx);
    final endColLetter = colToLetter(dateIdx + rowData.length - 1);
    final targetRange = "'$sheetName'!$startColLetter$targetRow:$endColLetter$targetRow";

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

      print("✅ [$sheetName] ${isIncome ? '수입' : '지출'} 입력 성공 (행: $targetRow, 범위: $targetRange)");
      return true;
    } catch (e) {
      print("❌ [$sheetName] 시트 업데이트 실패: $e");
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
    final sheetsApi = sheets.SheetsApi(client);

    // 캐시 매니저를 활용해 빠른 ID 반환
    final targetSpreadsheetId = await setupLedgerSpreadsheetForYear(client, year);

    final monthSheetName = '$month월';
    final range = "'$monthSheetName'!A1:J1000";

    try {
      final response = await sheetsApi.spreadsheets.values.get(
        targetSpreadsheetId,
        range,
      );

      final rows = response.values;
      if (rows == null || rows.length <= 1) {
        return [];
      }

      final isIncome = (type == TransactionType.income);
      final List<LedgerItem> items = [];

      final dateIdx = isIncome ? 0 : 5;
      final payMethodIdx = isIncome ? null : 6;
      final categoryIdx = isIncome ? 1 : 7;
      final descIdx = isIncome ? 2 : 8;
      final amountIdx = isIncome ? 3 : 9;

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];

        if (row.length <= amountIdx) continue;

        final rawDate = row[dateIdx].toString().trim();
        final rawDesc = row[descIdx].toString().trim();
        final rawAmount = row[amountIdx].toString().replaceAll(',', '').trim();

        if (rawDate.isEmpty || rawAmount.isEmpty || rawDesc.isEmpty) continue;

        final parsedAmount = int.tryParse(rawAmount);
        final parsedDate = DateTime.tryParse(rawDate);

        if (parsedAmount == null || parsedDate == null) continue;

        final category = row.length > categoryIdx ? row[categoryIdx].toString().trim() : "미입력";
        final payMethod = (payMethodIdx != null && row.length > payMethodIdx)
            ? row[payMethodIdx].toString().trim()
            : null;

        items.add(
          LedgerItem(
            date: parsedDate,
            type: type,
            description: rawDesc,
            amount: parsedAmount,
            category: category,
            payMethod: payMethod,
          ),
        );
      }

      return items;
    } on sheets.DetailedApiRequestError catch (e) {
      print("⚠️ [$monthSheetName] 시트 읽기 실패 (${e.status}): ${e.message}");
      return [];
    } catch (e) {
      print("⚠️ [$monthSheetName] 내역 조회 중 예외 발생: $e");
      return [];
    }
  }
}


