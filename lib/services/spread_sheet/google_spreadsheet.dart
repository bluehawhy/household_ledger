import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart';

// ============================================================================
// 1. 데이터 모델 및 Enum
// ============================================================================
enum TransactionType { income, expense }

class LedgerItem {
  final DateTime date; // 입력 날짜
  final TransactionType type; // 수입 or 지출
  final String? payMethod; // 지출 수단
  final String description; // 내용
  final int amount; // 금액
  String? category; // 분류

  LedgerItem({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    this.payMethod,
    this.category,
  });

  String get formattedDate =>
      "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
}

// ============================================================================
// 2. JSON 기반 카테고리 자동 매퍼
// ============================================================================
class CategoryMapper {
  Map<String, List<String>> incomeCategories = {};
  Map<String, List<String>> expenseCategories = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> loadCategoryJson([String filePath = 'ledger_ingestion_info.json']) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print("⚠️ [CategoryMapper] JSON 파일($filePath)을 찾을 수 없습니다.");
      _isLoaded = true;
      return;
    }

    try {
      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);

      if (data.containsKey("수입 분류")) {
        final Map<String, dynamic> income = data["수입 분류"];
        incomeCategories = income.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      }

      if (data.containsKey("지출 분류")) {
        final Map<String, dynamic> expense = data["지출 분류"];
        expenseCategories = expense.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      }
      _isLoaded = true;
      print("✅ [CategoryMapper] 카테고리 JSON 데이터 로드 완료!");
    } catch (e) {
      print("❌ [CategoryMapper] JSON 파싱 에러: $e");
      _isLoaded = true;
    }
  }

  String getCategory(String description, {required bool isIncome}) {
    final categories = isIncome ? incomeCategories : expenseCategories;

    for (var entry in categories.entries) {
      final categoryName = entry.key;
      final keywords = entry.value;

      for (var keyword in keywords) {
        if (description.contains(keyword)) {
          return categoryName;
        }
      }
    }
    return "미입력";
  }
}

// ============================================================================
// 3. 📊 가계부 구글 드라이브 및 스프레드시트 통합 관리 서비스 클래스
// ============================================================================
class HouseholdSheetService {
  final CategoryMapper categoryMapper = CategoryMapper();

  /// 서비스 초기화 시 JSON 설정 파일 로드
  Future<void> init([String filePath = 'ledger_ingestion_info.json']) async {
    await categoryMapper.loadCategoryJson(filePath);
  }

  // --------------------------------------------------------------------------
  // 🟢 [기능 A] 파일 및 시트 구조 생성 로직
  // --------------------------------------------------------------------------

  /// [기존 호환용] 현재 연도 기준 가계부 설정
  Future<String> setupLedgerSpreadsheet(AuthClient client) async {
    return await setupLedgerSpreadsheetForYear(client, DateTime.now().year);
  }

  /// [확장용] 특정 연도 가계부 설정
  Future<String> setupLedgerSpreadsheetForYear(AuthClient client, int year) async {
    // 안전장치: 카테고리가 안 읽혀있다면 JSON 로드 실행
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final driveApi = drive.DriveApi(client);
    final sheetsApi = sheets.SheetsApi(client);

    final folderId = await _getOrCreateFolder(driveApi, "가계부");
    final fileName = "가계부_$year";

    return await _getOrCreateSpreadsheet(
      driveApi,
      sheetsApi,
      folderId,
      fileName,
    );
  }

  Future<String> _getOrCreateFolder(
    drive.DriveApi driveApi,
    String folderName,
  ) async {
    print("\n📁 1. '$folderName' 폴더 확인 중...");

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 폴더 사용 (ID: $id)");
      return id;
    }

    print("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final folderMetaData = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await driveApi.files.create(folderMetaData);
    print("  └ 🎉 폴더 생성 완료! (ID: ${createdFolder.id})");
    return createdFolder.id!;
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
        sheets.Sheet(properties: sheets.SheetProperties(title: '${month}월')),
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

    // ------------------------------------------------------------------------
    // 1. JSON 기반 Overview 안내표 작성
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // 2. 수입 종합 통계표 생성 (동적 위치 계산)
    // ------------------------------------------------------------------------
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
        row.add("=SUMIF('${m}월'!\$B:\$B, \$A$rowNum, '${m}월'!\$D:\$D)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      incomeTable.add(row);
    }

    final int incomeFirstDataRow = incomeStartRow + 1;
    final int incomeLastDataRow = incomeStartRow + incomeList.length;

    List<String> incomeTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      incomeTotalRow.add("=SUM(${colLetter}$incomeFirstDataRow:${colLetter}$incomeLastDataRow)");
    }
    incomeTable.add(incomeTotalRow);

    final int incomeEndRow = incomeStartRow + incomeTable.length - 1;

    data.add(
      sheets.ValueRange(
        range: "'Overview'!A$incomeStartRow:N$incomeEndRow",
        values: incomeTable,
      ),
    );

    // ------------------------------------------------------------------------
    // 3. 지출 종합 통계표 생성 (동적 위치 계산)
    // ------------------------------------------------------------------------
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
        row.add("=SUMIF('${m}월'!\$H:\$H, \$A$rowNum, '${m}월'!\$J:\$J)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      expenseTable.add(row);
    }

    final int expenseFirstDataRow = expenseStartRow + 1;
    final int expenseLastDataRow = expenseStartRow + expenseList.length;

    List<String> expenseTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      expenseTotalRow.add("=SUM(${colLetter}$expenseFirstDataRow:${colLetter}$expenseLastDataRow)");
    }
    expenseTable.add(expenseTotalRow);

    final int expenseEndRow = expenseStartRow + expenseTable.length - 1;

    data.add(
      sheets.ValueRange(
        range: "'Overview'!A$expenseStartRow:N$expenseEndRow",
        values: expenseTable,
      ),
    );

    // ------------------------------------------------------------------------
    // 4. 1~12월 시트 헤더 생성
    // ------------------------------------------------------------------------
    for (int month = 1; month <= 12; month++) {
      final sheetName = '${month}월';
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

  // --------------------------------------------------------------------------
  // 🔵 [기능 B] 수입 / 지출 내역 신규 입력 로직
  
  Future<void> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
    if (!categoryMapper.isLoaded) {
      await categoryMapper.loadCategoryJson();
    }

    final sheetsApi = sheets.SheetsApi(client);

    String targetSpreadsheetId;
    if (spreadsheetId != null && spreadsheetId.isNotEmpty) {
      targetSpreadsheetId = spreadsheetId;
    } else {
      targetSpreadsheetId = await setupLedgerSpreadsheetForYear(client, item.date.year);
    }

    if (item.category == null || item.category!.isEmpty) {
      item.category = categoryMapper.getCategory(
        item.description,
        isIncome: item.type == TransactionType.income,
      );
    }

    final monthSheetName = '${item.date.month}월';

    // 1. 해당 월의 시트 탭 존재 확인 및 생성
    await _ensureMonthSheetExists(sheetsApi, targetSpreadsheetId, monthSheetName);

    // 원본 range 사용 (googleapis 패키지가 내부적으로 URL 인코딩 처리함)
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
      // 읽기 실패 시 데이터 오작동 방지를 위해 중단
      return;
    } catch (e) {
      print("⚠️ [$monthSheetName] 시트 읽기 중 예외 발생: $e");
      return;
    }

    // 시트에 헤더도 없는 빈 상태라면 기본 헤더 생성
    if (existingRows.isEmpty) {
      final defaultHeader = [
        "날짜", "수입 분류", "내용", "금액", "", "날짜", "지출 수단", "지출 분류", "내용", "금액"
      ];
      
      final headerValueRange = sheets.ValueRange(
        range: "'$monthSheetName'!A1:J1",
        values: [defaultHeader],
      );

      await sheetsApi.spreadsheets.values.update(
        headerValueRange,
        targetSpreadsheetId,
        "'$monthSheetName'!A1:J1",
        valueInputOption: "USER_ENTERED",
      );

      existingRows = [defaultHeader];
    }

    // 2. 중복 체크
    if (_checkDuplicate(existingRows, item)) {
      print("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
      return;
    }

    // 3. 데이터 추가 기입
    await appendTransactionData(
      sheetsApi,
      targetSpreadsheetId,
      monthSheetName,
      existingRows,
      item,
    );
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
        final existingAmount =
            row[amountIdx].toString().replaceAll(',', '').trim();

        if (existingDate == item.formattedDate &&
            existingDesc == item.description &&
            existingAmount == item.amount.toString()) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> appendTransactionData(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<List<dynamic>> existingRows,
    LedgerItem item,
  ) async {
    if (existingRows.isEmpty) return;

    final isIncome = item.type == TransactionType.income;
    final headerRow = existingRows[0].map((e) => e.toString().trim()).toList();

    // 1. 헤더 행에서 '날짜', '내용', '금액'의 모든 인덱스 위치(1번째: 수입, 2번째: 지출) 찾기
    final dateIndices = <int>[];
    final descIndices = <int>[];
    final amountIndices = <int>[];

    for (int i = 0; i < headerRow.length; i++) {
      if (headerRow[i] == "날짜") dateIndices.add(i);
      if (headerRow[i] == "내용") descIndices.add(i);
      if (headerRow[i] == "금액") amountIndices.add(i);
    }

    // 필요한 헤더 개수 검증 (수입: 0번 인덱스 필요 / 지출: 1번 인덱스 필요)
    final targetIndex = isIncome ? 0 : 1;

    if (dateIndices.length <= targetIndex ||
        descIndices.length <= targetIndex ||
        amountIndices.length <= targetIndex) {
      print("⚠️ [$sheetName] ${isIncome ? '첫 번째(수입)' : '두 번째(지출)'} 헤더('날짜', '내용', '금액')를 찾을 수 없습니다.");
      return;
    }

    // 수입/지출 여부에 따라 사용할 최종 열 인덱스 선택
    final dateIdx = dateIndices[targetIndex];
    final descIdx = descIndices[targetIndex];
    final amountIdx = amountIndices[targetIndex];

    // 2. 입력할 데이터 배열 세팅
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

    // 3. 기존 데이터 순회하며 중복 체크 및 타겟 행(targetRow) 계산
    int targetRow = 2;

    for (int i = 1; i < existingRows.length; i++) {
      final row = existingRows[i];

      // 해당 영역의 '날짜' 셀에 값이 있는 경우
      if (row.length > dateIdx && row[dateIdx].toString().trim().isNotEmpty) {
        targetRow = i + 2; // 다음 빈 행 계산

        // 중복 체크 (날짜, 내용, 금액 비교)
        if (row.length > amountIdx) {
          final existingDate = row[dateIdx].toString().trim();
          final existingDesc = row[descIdx].toString().trim();
          final existingAmount = row[amountIdx].toString().replaceAll(',', '').trim();

          if (existingDate == item.formattedDate.trim() &&
              existingDesc == item.description.trim() &&
              existingAmount == item.amount.toString().trim()) {
            print("⚠️ 중복 데이터 감지되어 스킵됨: [${item.formattedDate}] ${item.description} (${item.amount}원)");
            return; // 중복이면 스킵
          }
        }
      }
    }

    // 4. 숫자 인덱스를 구글 시트 알파벳(A, B, C...)으로 변환
    String _colToLetter(int colIndex) {
      String letter = "";
      while (colIndex >= 0) {
        letter = String.fromCharCode((colIndex % 26) + 65) + letter;
        colIndex = (colIndex ~/ 26) - 1;
      }
      return letter;
    }

    // 시작 열('날짜')부터 입력 데이터 개수(rowData.length)만큼의 끝 열을 동적 계산
    final startColIndex = dateIdx;
    final endColIndex = startColIndex + rowData.length - 1;

    final startColLetter = _colToLetter(startColIndex);
    final endColLetter = _colToLetter(endColIndex);
    final targetRange = "'$sheetName'!$startColLetter$targetRow:$endColLetter$targetRow";

    // 5. 시트 업데이트 요청
    final valueRange = sheets.ValueRange(
      range: targetRange,
      values: [rowData],
    );
    
    await sheetsApi.spreadsheets.values.update(
      valueRange,
      spreadsheetId,
      targetRange, // 👈 Uri.encodeComponent(targetRange) 대신 targetRange 원본 전달
      valueInputOption: "USER_ENTERED",
    );

    print("✅ [$sheetName] ${isIncome ? '수입' : '지출'} 입력 성공 (행: $targetRow, 범위: $targetRange) -> [${item.formattedDate}] ${item.description}: ${item.amount}원");
  }

}