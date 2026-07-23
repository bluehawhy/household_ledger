import 'dart:convert';
import 'dart:io';
import '../spread_sheet/google_spreadsheet.dart';

/// 텍스트 입력을 분석하여 LedgerItem 객체로 변환하는 순수 파서 서비스
class TextParserService {
  Map<String, List<String>> _incomeCategories = {};
  Map<String, List<String>> _expenseCategories = {};
  Map<String, List<String>> _payMethods = {};

  /// 루트에 있는 'ledger_ingestion_info.json' 파일을 로드하여 초기화합니다.
  Future<void> init([String filePath = 'ledger_ingestion_info.json']) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print("⚠️ [TextParserService] '$filePath' 파일을 찾을 수 없습니다. 기본 파싱 알고리즘만 사용됩니다.");
      return;
    }

    try {
      final jsonString = await file.readAsString();
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
      print("❌ [TextParserService] JSON 로드 에러: $e");
    }
  }

  /// 단일 줄 텍스트를 분석하여 LedgerItem 객체로 변환합니다.
  LedgerItem parseSingleLine(String input) {
    String text = input.trim();
    if (text.isEmpty) {
      throw FormatException("입력된 텍스트가 비어있습니다.");
    }

    // 1. 날짜 추출
    DateTime date = _extractDate(text, outText: (remaining) => text = remaining);

    // 2. 금액 추출
    int amount = _extractAmount(text, outText: (remaining) => text = remaining);

    // 3. 수입/지출 유형 판단
    TransactionType type = _determineType(text);

    // 4. 지출 수단 추출 (JSON '지출 수단' 참조)
    String? payMethod = _extractPayMethod(text, type: type, outText: (remaining) => text = remaining);

    // 5. 카테고리 추출 (JSON '지출 분류' / '수입 분류' 참조)
    String? category = _extractCategory(text, type: type);

    // 6. 남은 텍스트 정리하여 '내역(description)'으로 구성
    String description = text.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  /// 1. 날짜 추출 (YYYY-MM-DD, YYYY/MM/DD, MM-DD, MM/DD, MM DD, M D, 오늘, 어제 등)
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

    // YYYY-MM-DD 또는 YYYY/MM/DD
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

    // MM-DD 또는 MM/DD
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

    // MM DD 또는 M D ('7 25', '07 05' 등)
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

  /// 2. 금액 추출
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

  /// 3. 수입/지출 유형 판단
  TransactionType _determineType(String text) {
    if (text.contains("수입") || text.contains("입금") || text.contains("월급") || text.contains("환불")) {
      return TransactionType.income;
    }
    return TransactionType.expense;
  }

  /// 4. 지출 수단 추출 (JSON의 '지출 수단' 참고)
  String? _extractPayMethod(String text, {required TransactionType type, required Function(String) outText}) {
    if (type == TransactionType.income) {
      outText(text);
      return null;
    }

    // JSON에 정의된 지출 수단 매칭 (예: "신용카드" 키의 키워드 ["신용카드", "신한카드"...])
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

  /// 5. 카테고리 추출 (JSON의 '지출 분류' / '수입 분류' 참고)
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