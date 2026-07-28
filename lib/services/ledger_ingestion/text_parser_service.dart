import 'dart:convert';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';

/// 텍스트 입력을 분석하여 Map 형태의 가계부 데이터로 변환하는 서비스
class TextParserService {
  Map<String, List<String>> _incomeCategories = {};
  Map<String, List<String>> _expenseCategories = {};
  Map<String, List<String>> _payMethods = {};
  Map<String, dynamic> _binData = {};

  /// JSON 리소스 로드 및 초기화
  Future<void> init([String filePath = 'assets/ledger_ingestion_info.json']) async {
    try {
      final binJsonString = await JsonAssetManager.loadJson('assets/card_bin_data.json');
      _binData = jsonDecode(binJsonString) as Map<String, dynamic>;
      print("✅ [TextParserService] BIN 데이터 로드 완료 (${_binData.length}개)");
    } catch (e) {
      print("⚠️ [TextParserService] BIN 데이터 로드 실패: $e");
    }

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
      print("⚠️ [TextParserService] '$filePath' 로드 실패: $e");
    }
  }

  /// 🚀 [추가됨] 입력 텍스트를 날짜 기준으로 여러 줄(문장)로 분할/전처리하는 함수
  List<String> parseInputLines(String rawInput) {
    final trimmedInput = rawInput.trim();
    if (trimmedInput.isEmpty) return [];

    if (!trimmedInput.contains('\n')) {
      return [trimmedInput];
    }

    final singleLineText = trimmedInput
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final dateRegex = RegExp(
      r'(?:\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b|\b\d{1,2}[./-]\d{1,2}\b)',
    );

    final List<String> resultLines = [];
    final matches = dateRegex.allMatches(singleLineText).toList();

    if (matches.isEmpty) {
      return [singleLineText];
    }

    for (int i = 0; i < matches.length; i++) {
      final int start = matches[i].start;
      final int end = (i + 1 < matches.length) ? matches[i + 1].start : singleLineText.length;

      if (i == 0 && start > 0) {
        final prefix = singleLineText.substring(0, start).trim();
        if (prefix.isNotEmpty) {
          resultLines.add(prefix);
        }
      }

      final lineSegment = singleLineText.substring(start, end).trim();
      if (lineSegment.isNotEmpty) {
        resultLines.add(lineSegment);
      }
    }

    return resultLines;
  }

  /// 단일 줄 텍스트를 파싱하여 Map<String, dynamic> 형태로 반환합니다.
  Map<String, dynamic> parseSingleLineToMap(String input) {
    String rawText = input.trim();
    if (rawText.isEmpty) {
      throw FormatException("입력된 텍스트가 비어있습니다.");
    }

    List<String> tokens = rawText.contains('\t')
        ? rawText.split(RegExp(r'\t+'))
        : rawText.split(RegExp(r'\s+'));

    tokens = tokens.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    DateTime? date;
    int? amount;
    TransactionType type = TransactionType.expense;
    String? payMethod;
    String? category;

    List<String> remainingTokens = [];

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

    return {
      'date': date,
      'type': type,
      'payMethod': payMethod,
      'description': description,
      'amount': amount,
      'category': category ?? "미입력",
    };
  }

  bool _isIgnoredWord(String token) {
    const ignoredList = ["정상", "일시불", "승인", "취소", "완료"];
    return ignoredList.contains(token);
  }

  String? _matchPayMethod(String token) {
    for (var entry in _payMethods.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) return entry.key;
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
        if (token.contains(keyword)) return entry.key;
      }
    }
    return null;
  }
}