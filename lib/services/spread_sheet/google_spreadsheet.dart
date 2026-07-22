//google_spreadsheet.dart

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

  Future<void> loadCategoryJson(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print("⚠️ [CategoryMapper] JSON 파일을 찾을 수 없습니다 ($filePath). 기본값('미입력')으로 진행됩니다.");
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
      print("✅ [CategoryMapper] 카테고리 JSON 데이터 로드 완료");
    } catch (e) {
      print("❌ [CategoryMapper] JSON 파싱 에러: $e");
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

  // --------------------------------------------------------------------------
  // 🟢 [기능 A] 파일 및 시트 구조 생성 로직 (기존 함수명 호환 유지)
  // --------------------------------------------------------------------------

  /// [기존 호환용] 현재 연도 기준 가계부 설정
  Future<String> setupLedgerSpreadsheet(AuthClient client) async {
    return await setupLedgerSpreadsheetForYear(client, DateTime.now().year);
  }

  /// [확장용] 특정 연도 가계부 설정
  Future<String> setupLedgerSpreadsheetForYear(AuthClient client, int year) async {
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

    final List<List<String>> overviewGuide = [
      ["📌 [수입 분류 안내]", ""],
      ["주수입", "월급, 상여금, 사업소득"],
      ["부수입", "부업, 당근마켓/중고거래 판매, 기타 수입"],
      ["금융소득", "이자, 배당금, 주식/코인 수익"],
      ["포인트/캐시백", "네이버페이 포인트, 카드 캐시백, 기프티콘 사용"],
      ["", ""],
      ["📌 [지출 분류 안내]", ""],
      ["식비", "식재료 구매, 외식, 배달음식, 카페/디저트"],
      ["고정지출", "월세, 공과금(전기/수도/가스), 통신비, 보험료, 구독서비스 등"],
      ["생활/주거", "생필품, 가구/가전, 청소/위생용품"],
      ["교통/차량", "대중교통, 주유비, 주차비, 정비/통행료"],
      ["쇼핑/패션", "의류, 잡화, 뷰티, 미용실"],
      ["문화/여가", "영화/공연, 취미, 여행, 운동/헬스"],
      ["경조사/선물", "부조금, 축의금, 명절/생일 선물, 용돈"],
      ["의료/건강", "병원비, 약국, 영양제"],
      ["교육/자기개발", "학원비, 도서 구매, 강의/시험 응시료"],
      ["기타", "예비비, 분류 불가 지출"],
    ];

    data.add(
      sheets.ValueRange(range: "'Overview'!A1:B17", values: overviewGuide),
    );

    final monthsHeader = [
      "수입분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];
    final incomeCategories = ["주수입", "부수입", "금융소득", "포인트/캐시백"];
    List<List<String>> incomeTable = [monthsHeader];

    for (int i = 0; i < incomeCategories.length; i++) {
      final category = incomeCategories[i];
      final rowNum = 21 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIF('${m}월'!\$B:\$B, \$A$rowNum, '${m}월'!\$D:\$D)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      incomeTable.add(row);
    }

    List<String> incomeTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      incomeTotalRow.add("=SUM(${colLetter}21:${colLetter}24)");
    }
    incomeTable.add(incomeTotalRow);

    data.add(
      sheets.ValueRange(range: "'Overview'!A20:N25", values: incomeTable),
    );

    final expenseCategories = [
      "식비", "고정지출", "생활/주거", "교통/차량", "쇼핑/패션",
      "문화/여가", "경조사/선물", "의료/건강", "교육/자기개발", "기타"
    ];
    final expenseMonthsHeader = [
      "지출분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];
    List<List<String>> expenseTable = [expenseMonthsHeader];

    for (int i = 0; i < expenseCategories.length; i++) {
      final category = expenseCategories[i];
      final rowNum = 29 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIF('${m}월'!\$H:\$H, \$A$rowNum, '${m}월'!\$J:\$J)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      expenseTable.add(row);
    }

    List<String> expenseTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      expenseTotalRow.add("=SUM(${colLetter}29:${colLetter}38)");
    }
    expenseTable.add(expenseTotalRow);

    data.add(
      sheets.ValueRange(range: "'Overview'!A28:N39", values: expenseTable),
    );

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
    print("  └ ✅ Overview 종합 통계표 및 1~12월 헤더 입력 세팅 완벽 완료!");
  }

  // --------------------------------------------------------------------------
  // 🔵 [기능 B] 수입 / 지출 내역 신규 입력 로직
  // --------------------------------------------------------------------------

  Future<void> addTransaction({
    required AuthClient client,
    required LedgerItem item,
    String? spreadsheetId,
  }) async {
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

    await _ensureMonthSheetExists(sheetsApi, targetSpreadsheetId, monthSheetName);

    final range = "'$monthSheetName'!A1:J1000";
    final response =
        await sheetsApi.spreadsheets.values.get(targetSpreadsheetId, range);
    final existingRows = response.values ?? [];

    if (_checkDuplicate(existingRows, item)) {
      print("⚠️ [중복 패스] [${item.formattedDate}] '${item.description}' (${item.amount}원) 내역이 이미 존재합니다.");
      return;
    }

    await _appendTransactionData(
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

      // 💡 BatchUpdateRequest -> BatchUpdateSpreadsheetRequest 로 수정 완료
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

  Future<void> _appendTransactionData(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String sheetName,
    List<List<dynamic>> existingRows,
    LedgerItem item,
  ) async {
    final isIncome = item.type == TransactionType.income;
    final checkIdx = isIncome ? 0 : 5;

    int targetRow = 2;

    for (int i = 1; i < existingRows.length; i++) {
      if (existingRows[i].length > checkIdx &&
          existingRows[i][checkIdx].toString().isNotEmpty) {
        targetRow = i + 2;
      }
    }

    final targetRange = isIncome
        ? "'$sheetName'!A$targetRow:D$targetRow"
        : "'$sheetName'!F$targetRow:J$targetRow";

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

    print(
      "✅ [$sheetName] ${isIncome ? '수입' : '지출'} 입력 성공 (행 번호: $targetRow) -> [${item.formattedDate}] ${item.description}: ${item.amount}원 (분류: ${item.category})",
    );
  }
}