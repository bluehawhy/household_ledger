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
      // 1. 무시할 키워드 목록
      ignoredWords = List<String>.from(ignoreConfig["무시 키워드"] ?? []);

      // 2. 무시할 정규식 패턴 목록 (시간, 사업자번호, 마스킹 등)
      final patternsMap = ignoreConfig["무시 정규식 패턴"] as Map<String, dynamic>?;
      if (patternsMap != null) {
        ignoredPatterns = patternsMap.values
            .map((patternStr) => RegExp(patternStr.toString()))
            .toList();
      }
    }
  }

  /// 통합 무시 대상 검사
  bool isIgnored(String token) {
    // 1) 무시 키워드 부분 일치 검사
    if (ignoredWords.any((word) => token.contains(word))) {
      return true;
    }

    // 2) 등록된 정규식 패턴(시간, 사업자번호, 마스킹 등) 매칭 검사
    if (ignoredPatterns.any((pattern) => pattern.hasMatch(token))) {
      return true;
    }

    return false;
  }
}

/// 텍스트 입력을 분석하여 Map 형태의 가계부 데이터로 변환하는 서비스
class TextParserService {
  // 1. 필수 정규식 패턴 (날짜, 카드번호, 금액 등 구조 추출용)
  static final _fullDatePattern = RegExp(r'^(\d{4})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$');
  static final _shortDatePattern = RegExp(r'^(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$');
  static final _cardNoPattern = RegExp(r'^\d{4}[-*\s]+[\d*]{2,4}[-*\s]+[\d*]{2,4}[-*\s]+\d{4}$');
  static final _amountPattern = RegExp(r'^(\d{1,3}(,\d{3})*|\d+)(원)?$');

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

  /// 입력 텍스트를 날짜 기준으로 여러 줄(문장)로 분할/전처리하는 함수
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

  /// 단일 줄 텍스트를 파싱하여 Map<String, dynamic> 형태로 반환
  Map<String, dynamic> parseSingleLineToMap(String input) {
    String rawText = input.trim();
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
      // [1단계: 설정파일 기반 무시 대상 최우선 검사]
      // (시간, 일반과세자, 승인, 출금, 사업자번호, 기호 등)
      // -------------------------------------------------------------
      if (_config.isIgnored(token)) {
        continue; // 무시 대상이면 이하 검사를 건너뛰고 패스!
      }

      // 카드번호 패턴 (카드사 감지 시 payMethod 확정 후 패스)
      if (_cardNoPattern.hasMatch(token)) {
        payMethod ??= _detectCardIssuer(token);
        continue;
      }

      // -------------------------------------------------------------
      // [2단계: 주요 정보 추출 (가드 조건으로 불필요한 반복 탐색 방지)]
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
        continue;
      }

      // 결제 수단 (payMethod가 미지정일 때만 시도)
      if (payMethod == null) {
        final foundPayMethod = _matchPayMethod(token);
        if (foundPayMethod != null) {
          payMethod = foundPayMethod;
          //continue;
        }
      }

      // 카테고리 (category가 미지정일 때만 시도)
      if (category == null) {
        final foundCategory = _matchCategory(token, type: type);
        if (foundCategory != null) {
          category = foundCategory;
        }
      }

      // -------------------------------------------------------------
      // [3단계: 위 검사를 무사히 통과한 단어만 적요(Description) 후보로 수집]
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

    // 적요(Description) 조합
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
      String rawNumStr = match.group(1)!.replaceAll(',', '');
      int parsedNum = int.parse(rawNumStr);
      if (parsedNum > 0) return parsedNum;
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
    for (var entry in categories.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) return entry.key;
      }
    }
    return null;
  }
}