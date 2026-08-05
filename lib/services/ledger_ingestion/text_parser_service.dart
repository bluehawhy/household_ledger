import 'dart:convert';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';

/// JSON 설정 기반 무시 대상 관리 클래스
class TransactionParserConfig {
  List<String> ignoredWords = [];
  List<RegExp> ignoredPatterns = [];

  TransactionParserConfig();

  TransactionParserConfig.fromJson(Map<String, dynamic> json) {
    final ignoreConfig = json["무시 대상 설정"];
    if (ignoreConfig != null) {
      ignoredWords = List<String>.from(ignoreConfig["무시 키워드"] ?? []);

      final patternsMap = ignoreConfig["무시 정규식 패턴"] as Map<String, dynamic>?;
      if (patternsMap != null) {
        ignoredPatterns = patternsMap.values
            .map((patternStr) => RegExp(patternStr.toString(), caseSensitive: false))
            .toList();
      }
    }
  }

  /// 토큰 단위 검사
  bool isIgnored(String token) {
    if (ignoredWords.any((word) => token.contains(word))) {
      return true;
    }
    if (ignoredPatterns.any((pattern) => pattern.hasMatch(token))) {
      return true;
    }
    return false;
  }

  /// 문장 전체 덩어리 정제 (JSON 정규식 활용)
  String cleanText(String rawText) {
    if (rawText.isEmpty) return rawText;

    String cleaned = rawText;

    for (final pattern in ignoredPatterns) {
      String patternStr = pattern.pattern;

      // 문장 내 부분 치환을 방지하는 앞뒤 ^ 및 $ 앵커 보정
      if (patternStr.startsWith('^')) patternStr = patternStr.substring(1);
      if (patternStr.endsWith('\$')) patternStr = patternStr.substring(0, patternStr.length - 1);

      // JSON 원본 문자열의 이중 백슬래시(\s, \d 등) 보정
      patternStr = patternStr.replaceAll(r'\\', r'\');

      try {
        final inlineRegExp = RegExp(patternStr, caseSensitive: false);
        cleaned = cleaned.replaceAll(inlineRegExp, ' ');
      } catch (e) {
        // 정규식 예외 발생 시 무시
      }
    }

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}




/// 텍스트 입력을 분석하여 Map 형태의 가계부 데이터로 변환하는 서비스
class TextParserService {
  static final _fullDatePattern = RegExp(r'^(\d{4})[.-/](\d{1,2})[.-/](\d{1,2})(?:\s+\d{1,2}:\d{1,2})?$');
  static final _shortDatePattern = RegExp(r'^(\d{1,2})[.-/](\d{1,2})(?:\s+\d{1,2}:\d{1,2})?$');
  static final _cardNoPattern = RegExp(r'^\d{4}[-*\s]+[\d*]{2,4}[-*\s]+[\d*]{2,4}[-*\s]+\d{4}$');
  static final _amountPattern = RegExp(r'^-?\s*(\d{1,3}(,\d{3})*|\d+)(원)?$');

  // Config 객체 선언
  TransactionParserConfig _config = TransactionParserConfig();

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

      // 1. 무시 대상 Config 데이터 로드
      _config = TransactionParserConfig.fromJson(data);

      // 2. 수입/지출/결제수단 카테고리 로드
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

  /// 💡 [완전 자동화 전처리] JSON Config에만 의존하여 사전 정제 수행
  String _preCleanInput(String rawInput) {
    if (rawInput.trim().isEmpty) return '';
    return _config.cleanText(rawInput);
  }

  /// 입력 텍스트를 날짜 기준으로 여러 줄(문장)로 분할/전처리하는 함수
  List<String> parseInputLines(String rawInput) {
    // 💡 1단계: Config 기반 사전 정제(전처리)로 잔액/승인번호 덩어리 제거
    final cleanedText = _preCleanInput(rawInput);
    if (cleanedText.isEmpty) return [];

    // 줄바꿈 보정
    final singleLineText = cleanedText
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

  /// 단일 줄 텍스트를 파싱하여 Map<String, dynamic> 형태로 반환
  Map<String, dynamic> parseSingleLineToMap(String input) {
    // 💡 단일 문장 파싱 시작 시점에도 Pre-cleaning 적용
    String rawText = _preCleanInput(input);
    if (rawText.isEmpty) {
      throw FormatException("입력된 텍스트가 비어있습니다.");
    }

    List<String> tokens = _tokenize(rawText);
    print("🔹 토큰화된 입력: $tokens");

    DateTime? date;
    int? amount;
    TransactionType type = TransactionType.expense;
    String? payMethod;
    String? category;

    List<String> remainingTokens = [];

    for (String token in tokens) {
      // -------------------------------------------------------------
      // [1단계: 설정파일 기반 무시 대상 검사]
      // -------------------------------------------------------------
      if (_config.isIgnored(token)) {
        continue; // 무시 대상이면 패스!
      }

      // 카드번호 패턴 (카드사 감지 시 payMethod 확정 후 패스)
      if (_cardNoPattern.hasMatch(token)) {
        payMethod ??= _detectCardIssuer(token);
        continue;
      }

      // -------------------------------------------------------------
      // [2단계: 주요 정보 추출]
      // -------------------------------------------------------------

      // 날짜
      if (date == null) {
        final parsedDate = _parseDate(token);
        if (parsedDate != null) {
          date = parsedDate;
          continue;
        }
      }

      // 금액
      if (amount == null) {
        final parsedAmount = _parseAmount(token);
        if (parsedAmount != null) {
          amount = parsedAmount;
          continue;
        }
      }

      // 거래 유형 (수입/지출)
      if (type == TransactionType.expense && _isIncomeType(token)) {
        type = TransactionType.income;
        category ??= _matchCategory(token, type: TransactionType.income);
      }

      // 결제 수단
      if (payMethod == null) {
        final foundPayMethod = _matchPayMethod(token);
        if (foundPayMethod != null) {
          payMethod = foundPayMethod;
          continue;
        }
      }

      // 카테고리
      if (category == null) {
        final foundCategory = _matchCategory(token, type: type);
        if (foundCategory != null) {
          category = foundCategory;
        }
      }

      // -------------------------------------------------------------
      // [3단계: 적요 후보 수집]
      // -------------------------------------------------------------
      remainingTokens.add(token);
    }

    // 기본값 처리
    date ??= DateTime.now();
    amount ??= 0;

    // 카테고리 미지정 시 남은 토큰에서 재탐색
    if (category == null && remainingTokens.isNotEmpty) {
      for (String t in remainingTokens) {
        category = _matchCategory(t, type: type);
        if (category != null) break;
      }
    }
    
    // -------------------------------------------------------------
    // [4단계: 적요(Description) 최종 조합]
    // -------------------------------------------------------------
    final Set<String> groupHeaderKeys = {
      ..._incomeCategories.keys,
      ..._payMethods.keys,
      ..._expenseCategories.keys,
    };

    final cleanedTokens = remainingTokens.where((t) {
      return !groupHeaderKeys.contains(t.trim());
    }).toList();

    String description = cleanedTokens.join(' ').trim();
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

  // ==========================================
  // Private 헬퍼 함수들
  // ==========================================

  List<String> _tokenize(String text) {
    List<String> tokens = text.contains('\t')
        ? text.split(RegExp(r'\t+'))
        : text.split(RegExp(r'\s+'));
    return tokens.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  DateTime? _parseDate(String token) {
    if (token == "오늘") return DateTime.now();
    if (token == "어제") return DateTime.now().subtract(const Duration(days: 1));

    final fullMatch = _fullDatePattern.firstMatch(token);
    if (fullMatch != null) {
      return DateTime(
        int.parse(fullMatch.group(1)!),
        int.parse(fullMatch.group(2)!),
        int.parse(fullMatch.group(3)!),
      );
    }

    final shortMatch = _shortDatePattern.firstMatch(token);
    if (shortMatch != null) {
      return DateTime(
        DateTime.now().year,
        int.parse(shortMatch.group(1)!),
        int.parse(shortMatch.group(2)!),
      );
    }

    return null;
  }

  int? _parseAmount(String token) {
    final match = _amountPattern.firstMatch(token);
    if (match != null) {
      String cleanStr = token.replaceAll(RegExp(r'[^\d-]'), '');
      
      if (cleanStr.startsWith('0') && cleanStr != '0') {
        return null;
      }

      int? parsedNum = int.tryParse(cleanStr);
      
      if (parsedNum != null && parsedNum != 0) {
        return parsedNum;
      }
    }
    return null;
  }

  bool _isIncomeType(String token) {
    const defaultIncomeKeywords = ["수입", "입금", "월급", "환불"];
    if (defaultIncomeKeywords.any((keyword) => token.contains(keyword))) {
      return true;
    }

    for (var keywords in _incomeCategories.values) {
      for (var keyword in keywords) {
        if (token.contains(keyword)) {
          return true;
        }
      }
    }

    return false;
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

    for (var categoryKey in categories.keys) {
      if (token.contains(categoryKey)) {
        return categoryKey;
      }
    }

    for (var entry in categories.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return null;
  }
}