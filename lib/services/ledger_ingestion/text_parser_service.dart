import 'dart:convert';
import 'dart:io';
// 1. googleapis sheets 패키지 import (sheets Prefix 지정)
import 'package:googleapis/sheets/v4.dart' as sheets;
// 2. appendTransactionData가 작성되어 있는 파일 import
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';

/// 파싱 및 시트 데이터 추가 결과 상태
enum ParseResult {
  success,   // 성공적으로 추가됨
  duplicate, // 중복 데이터로 확인되어 추가 취소/스킵됨
  fail,      // 빈 문자열, 파싱 오류, API 통신 에러 등 실패
}

/// 텍스트 입력을 분석하여 LedgerItem 객체로 변환하는 순수 파서 서비스
class TextParserService {
  // 1. sheetService 객체 선언 및 초기화
  final HouseholdSheetService sheetService = HouseholdSheetService();

  Map<String, List<String>> _incomeCategories = {};
  Map<String, List<String>> _expenseCategories = {};
  Map<String, List<String>> _payMethods = {};
  Map<String, dynamic> _binData = {};

  /// 루트에 있는 'ledger_ingestion_info.json' 파일을 로드하여 초기화합니다.
  Future<void> init([String filePath = 'assets/ledger_ingestion_info.json']) async {
    // 1. BIN 데이터 로드 (JsonAssetManager 사용)
    try {
      final binJsonString = await JsonAssetManager.loadJson('assets/card_bin_data.json');
      _binData = jsonDecode(binJsonString) as Map<String, dynamic>;
      print("✅ [TextParserService] BIN 데이터 로드 완료 (${_binData.length}개)");
    } catch (e) {
      print("⚠️ [TextParserService] BIN 데이터 로드 실패 (기본값 적용): $e");
    }

    // 2. 카테고리 매핑 데이터 로드 (JsonAssetManager 사용)
    try {
      final jsonString = await JsonAssetManager.loadJson(filePath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      if (data.containsKey("수입 분류")) {
        final Map<String, dynamic> map = data["수입 분류"];
        _incomeCategories = map.map((k, v) => MapEntry(k, List<String>.from(v)));
      }

      if (data.containsKey("지출 분류")) {
        final Map<String, dynamic> map = data["지출 분류"];
        _expenseCategories = map.map((k, v) => MapEntry(k, List<String>.from(v)));
      }

      if (data.containsKey("지출 수단")) {
        final Map<String, dynamic> map = data["지출 수단"];
        _payMethods = map.map((k, v) => MapEntry(k, List<String>.from(v)));
      }

      print("✅ [TextParserService] '$filePath' 카테고리 매핑 로드 완료");
    } catch (e) {
      print("⚠️ [TextParserService] '$filePath' 로드 실패 (기본 파싱 알고리즘만 사용): $e");
    }
  }

  /// 단일 줄 텍스트를 토큰 기반으로 분석하여 LedgerItem 객체로 변환합니다.
  LedgerItem parseSingleLine(String input) {
    String rawText = input.trim();
    if (rawText.isEmpty) {
      throw FormatException("입력된 텍스트가 비어있습니다.");
    }

    // 1. 탭(\t) 존재 여부에 따라 토큰 분리 (TAB 우선, 없으면 Space)
    List<String> tokens = rawText.contains('\t')
        ? rawText.split(RegExp(r'\t+'))
        : rawText.split(RegExp(r'\s+'));

    tokens = tokens.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    DateTime? date;
    int? amount;
    TransactionType type = TransactionType.expense; // 기본 지출
    String? payMethod;
    String? category;

    // 가계부 내역(description) 후보로 사용할 남은 토큰 목록
    List<String> remainingTokens = [];

    // 정규식 패턴 사전 정의
    final cardNoPattern = RegExp(r'^\d{4}[-*\s]+[\d*]{2,4}[-*\s]+[\d*]{2,4}[-*\s]+\d{4}$');
    final bizNoPattern = RegExp(r'^\d{3}-\d{2}-\d{5}$');
    final fullDatePattern = RegExp(r'^(\d{4})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$');
    final shortDatePattern = RegExp(r'^(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$');
    final amountPattern = RegExp(r'^(\d{1,3}(,\d{3})*|\d+)(원)?$');

    for (String token in tokens) {
      if (cardNoPattern.hasMatch(token)) {
        payMethod ??= _detectCardIssuer(token);
        continue;
      }

      if (bizNoPattern.hasMatch(token) || '*'.allMatches(token).length >= 2) {
        continue;
      }

      if (date == null) {
        if (token == "오늘") {
          date = DateTime.now();
          continue;
        } else if (token == "어제") {
          date = DateTime.now().subtract(const Duration(days: 1));
          continue;
        }

        final fullMatch = fullDatePattern.firstMatch(token);
        if (fullMatch != null) {
          date = DateTime(
            int.parse(fullMatch.group(1)!),
            int.parse(fullMatch.group(2)!),
            int.parse(fullMatch.group(3)!),
          );
          continue;
        }

        final shortMatch = shortDatePattern.firstMatch(token);
        if (shortMatch != null) {
          date = DateTime(
            DateTime.now().year,
            int.parse(shortMatch.group(1)!),
            int.parse(shortMatch.group(2)!),
          );
          continue;
        }
      }

      if (amount == null) {
        final amountMatch = amountPattern.firstMatch(token);
        if (amountMatch != null && !_isIgnoredWord(token)) {
          String rawNumStr = amountMatch.group(1)!.replaceAll(',', '');
          int parsedNum = int.parse(rawNumStr);
          if (parsedNum > 0) {
            amount = parsedNum;
            continue;
          }
        }
      }

      if (token.contains("수입") || token.contains("입금") || token.contains("월급") || token.contains("환불")) {
        type = TransactionType.income;
        continue;
      }

      if (payMethod == null) {
        String? foundPayMethod = _matchPayMethod(token);
        if (foundPayMethod != null) {
          payMethod = foundPayMethod;
          continue;
        }
      }

      if (category == null) {
        String? foundCategory = _matchCategory(token, type: type);
        if (foundCategory != null) {
          category = foundCategory;
        }
      }

      if (!_isIgnoredWord(token)) {
        remainingTokens.add(token);
      }
    }

    date ??= DateTime.now();
    amount ??= 0;

    if (category == null && remainingTokens.isNotEmpty) {
      for (String t in remainingTokens) {
        category = _matchCategory(t, type: type);
        if (category != null) break;
      }
    }

    String description = remainingTokens.join(' ').trim();
    if (description.isEmpty) {
      description = category ?? "미지정 내역";
    }

    return LedgerItem(
      date: date,
      type: type,
      description: description,
      amount: amount,
      payMethod: payMethod,
      category: category ?? "미입력",
    );
  }

  bool _isIgnoredWord(String token) {
    const ignoredList = ["정상", "일시불", "승인", "취소", "완료"];
    return ignoredList.contains(token);
  }

  String? _matchPayMethod(String token) {
    for (var entry in _payMethods.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  String _detectCardIssuer(String token) {
    final clean = token.replaceAll(RegExp(r'[^0-9]'), '');

    if (clean.length >= 6) {
      final bin6 = clean.substring(0, 6);
      final issuer = _binData[bin6]?['전표인자명'];

      if (issuer != null && issuer.toString().isNotEmpty) {
        return issuer.toString();
      }
    }

    return '신용카드';
  }

  String? _matchCategory(String token, {required TransactionType type}) {
    final categories = (type == TransactionType.income) ? _incomeCategories : _expenseCategories;
    for (var entry in categories.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// ✏️ [수정] 텍스트 파싱 후 appendTransactionData를 호출해 시트에 삽입하며 결과 상태(ParseResult)를 리턴합니다.
  Future<ParseResult> appendParseSingleLine(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String input,
  ) async {
    // 0. 빈 입력이면 실패 처리
    if (input.trim().isEmpty) {
      return ParseResult.fail;
    }

    try {
      // 1. 단일 줄 텍스트 파싱 -> LedgerItem 객체 생성
      final LedgerItem item = parseSingleLine(input);

      // 2. 월별 시트 이름 설정 (예: "7월")
      final sheetName = "${item.date.month}월";

      // 3. 기존 시트 데이터 가져오기 (동적 헤더 및 중복 체크용)
      List<List<dynamic>> existingRows = [];
      try {
        final response = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          "'$sheetName'!A1:Z1000",
        );
        existingRows = response.values ?? [];
      } catch (e) {
        print("⚠️ [$sheetName] 시트 읽기 실패 (신규 시트 또는 데이터 없음): $e");
      }

      // 4. google_spreadsheet.dart 의 appendTransactionData 에 삽입
      // ※ appendTransactionData 내부 구현 방식에 맞춰 반환값/동작 처리
      final bool isAppended = await sheetService.appendTransactionData(
        sheetsApi,
        spreadsheetId,
        sheetName,
        existingRows,
        item,
      );

      // appendTransactionData 가 bool 형태(중복 시 false)를 리턴한다고 가정할 때:
      if (isAppended) {
        return ParseResult.success;
      } else {
        return ParseResult.duplicate;
      }
    } catch (e) {
      print("❌ [appendParseSingleLine] 처리 실패: $e");
      return ParseResult.fail;
    }
  }

  DateTime _extractDate(String text, {required Function(String) outText}) {
    DateTime now = DateTime.now();

    if (text.contains("오늘")) {
      outText(text.replaceAll("오늘", ""));
      return now;
    }
    if (text.contains("어제")) {
      outText(text.replaceAll("어제", ""));
      return now.subtract(const Duration(days: 1));
    }

    final fullDateReg = RegExp(r'(\d{4})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])');
    final fullMatch = fullDateReg.firstMatch(text);
    if (fullMatch != null) {
      outText(text.replaceFirst(fullDateReg, ""));
      return DateTime(
        int.parse(fullMatch.group(1)!),
        int.parse(fullMatch.group(2)!),
        int.parse(fullMatch.group(3)!),
      );
    }

    final shortDateReg = RegExp(r'(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])');
    final shortMatch = shortDateReg.firstMatch(text);
    if (shortMatch != null) {
      outText(text.replaceFirst(shortDateReg, ""));
      return DateTime(
        now.year,
        int.parse(shortMatch.group(1)!),
        int.parse(shortMatch.group(2)!),
      );
    }

    final spaceDateReg = RegExp(r'(?:^|\s)(0?[1-9]|1[0-2])\s+(0?[1-9]|[12]\d|3[01])(?=\s|$)');
    final spaceMatch = spaceDateReg.firstMatch(text);
    if (spaceMatch != null) {
      outText(text.replaceFirst(spaceDateReg, ""));
      return DateTime(
        now.year,
        int.parse(spaceMatch.group(1)!),
        int.parse(spaceMatch.group(2)!),
      );
    }

    outText(text);
    return now;
  }

  int _extractAmount(String text, {required Function(String) outText}) {
    final amountWithWonReg = RegExp(r'(\d{1,3}(,\d{3})*|\d+)\s*원');
    final wonMatch = amountWithWonReg.firstMatch(text);

    if (wonMatch != null) {
      outText(text.replaceFirst(amountWithWonReg, ""));
      String numStr = wonMatch.group(1)!.replaceAll(',', '');
      return int.parse(numStr);
    }

    final rawNumberReg = RegExp(r'\b\d{1,3}(,\d{3})+\b|\b\d{3,9}\b');
    final rawMatch = rawNumberReg.firstMatch(text);
    if (rawMatch != null) {
      outText(text.replaceFirst(rawNumberReg, ""));
      String numStr = rawMatch.group(0)!.replaceAll(',', '');
      return int.parse(numStr);
    }

    return 0;
  }

  TransactionType _determineType(String text) {
    if (text.contains("수입") || text.contains("입금") || text.contains("월급") || text.contains("환불")) {
      return TransactionType.income;
    }
    return TransactionType.expense;
  }

  String? _extractPayMethod(String text, {required TransactionType type, required Function(String) outText}) {
    if (type == TransactionType.income) {
      outText(text);
      return null;
    }

    for (var entry in _payMethods.entries) {
      final methodTitle = entry.key;
      final keywords = entry.value;

      for (var keyword in keywords) {
        if (text.contains(keyword)) {
          outText(text.replaceFirst(keyword, ""));
          return methodTitle;
        }
      }
    }

    outText(text);
    return null;
  }

  String? _extractCategory(String text, {required TransactionType type}) {
    final categories = (type == TransactionType.income) ? _incomeCategories : _expenseCategories;

    for (var entry in categories.entries) {
      final categoryName = entry.key;
      final keywords = entry.value;

      for (var keyword in keywords) {
        if (text.contains(keyword)) {
          return categoryName;
        }
      }
    }
    return null;
  }
}