import 'dart:convert';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/utils/asset_loader.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


/// JSON 설정 기반 무시 대상 관리 클래스
class TransactionParserConfig {
  List<String> ignoredWords = [];
  List<RegExp> ignoredPatterns = [];
  // 💡 보정 대상 Mapping 저장 (Key: 치환될 표준 키워드, Value: 보정할 정규식 리스트)
  Map<String, List<RegExp>> replacementRules = {};

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
    // 💡 [추가] "보정 대상" 읽어오기
    final replacementConfig = json["보정 대상"] as Map<String, dynamic>?;
    if (replacementConfig != null) {
      replacementConfig.forEach((targetKey, patterns) {
        if (patterns is List) {
          replacementRules[targetKey] = patterns
              .map((p) => RegExp(p.toString(), caseSensitive: false))
              .toList();
        }
      });
    }
  }

  /// 보정 처리 함수: 정규식 패턴 발견 시 key 값으로 치환/중복 제거
  String normalizeText(String rawText) {
    if (rawText.isEmpty) return rawText;

    String normalized = rawText;

    replacementRules.forEach((targetKey, patterns) {
      for (final pattern in patterns) {
        // 문장 내 해당 정규식 패턴이 매칭되는 동안 반복 처리
        while (pattern.hasMatch(normalized)) {
          final match = pattern.firstMatch(normalized);
          if (match == null) break;

          final matchedText = match.group(0)!;

          // 1. 매칭된 텍스트(예: "체크카드(1329)") 부분을 제외한 나머지 문장 추출
          final remainingText = normalized.replaceFirst(matchedText, '');

          // 2. '나머지 문장'에 이미 targetKey("체크카드")가 존재하는지 검토 💡
          if (remainingText.contains(targetKey)) {
            // 나머지 항목에 이미 키가 있으면 매칭된 패턴 부분은 삭제
            normalized = normalized.replaceFirst(matchedText, ' ');
          } else {
            // 나머지 항목에 없으면 targetKey("체크카드")로 변경
            normalized = normalized.replaceFirst(matchedText, ' $targetKey ');
          }
        }
      }
    });

    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }




  /// 토큰 단위 검사
  bool isIgnored(String token) {
    if (ignoredWords.any((word) => token == word)) {
      return true;
    }
    if (ignoredPatterns.any((pattern) => pattern.hasMatch(token))) {
      return true;
    }
    return false;
  }

  /// 문장 전체 덩어리 정제 (JSON 정규식 및 무시 키워드 활용)
  String cleanText(String rawText) {
    if (rawText.isEmpty) return rawText;

    String cleaned = rawText;

    // 1. [정규식 패턴 제거] ignoredPatterns
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

    // 2. [무시 키워드 제거] ignoredWords 💡
    // 긴 단어가 짧은 단어보다 먼저 제거되도록 정렬 (예: '일반과세'가 '과세'보다 먼저 제거)
    final sortedWords = List<String>.from(ignoredWords)
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final word in sortedWords) {
      final trimmedWord = word.trim();
      if (trimmedWord.isNotEmpty) {
        cleaned = cleaned.replaceAll(trimmedWord, ' ');
      }
    }

    // 3. [연속 공백 정리]
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

enum InputType { excel, csv, txt }

/// 텍스트 입력을 분석하여 Map 형태의 가계부 데이터로 변환하는 서비스
class TextParserService {
  // 💡 싱글톤 인스턴스 생성
  static final TextParserService _instance = TextParserService._internal();
  factory TextParserService() => _instance;
  TextParserService._internal();

  bool _isInitialized = false;

  static final _fullDatePattern = RegExp(r'\b(?:(\d{4})[./\-])?(\d{1,2})[./\-](\d{1,2})(?:\s+(\d{1,2}):(\d{1,2})(?::\d{1,2})?)?',);
  static final _cardNoPattern = RegExp(r'^\d{4}[-*\s]+[\d*]{2,4}[-*\s]+[\d*]{2,4}[-*\s]+\d{4}$');
  static final _amountPattern = RegExp(r'(\d{1,3}(?:,\d{3})+|\d+)\s*원');

  // Config 객체 선언
  TransactionParserConfig _config = TransactionParserConfig();

  // 수입/지출/결제수단 카테고리 매핑
  //Map<String, List<String>> _incomeCategories = {};
  //Map<String, List<String>> _expenseCategories = {};
  Map<String, dynamic> _incomeCategories = {};
  Map<String, dynamic> _expenseCategories = {};
  Map<String, List<String>> _payMethods = {};
  Map<String, dynamic> _binData = {};

  /// JSON 리소스 로드 및 초기화
  Future<void> init([String filePath = 'assets/ledger_ingestion_info.json']) async {
    if (_isInitialized) return;
    try {
      final binJsonString = await JsonAssetManager.loadJson('assets/card_bin_data.json');
      _binData = jsonDecode(binJsonString) as Map<String, dynamic>;
      AppLogger.i("BIN 데이터 로드 완료 (${_binData.length}개)");
      _isInitialized = true;
    } catch (e) {
      AppLogger.i("BIN 데이터 로드 실패: $e");
    }

    try {
      final jsonString = await JsonAssetManager.loadJson(filePath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // 1. 무시 대상 Config 데이터 로드
      _config = TransactionParserConfig.fromJson(data);

      // 2. 수입/지출/결제수단 카테고리 로드

      if (data.containsKey("수입 분류")) {
        _incomeCategories = Map<String, dynamic>.from(data["수입 분류"]);
      }

      if (data.containsKey("지출 분류")) {
        _expenseCategories = Map<String, dynamic>.from(data["지출 분류"]);
      }

      if (data.containsKey("지출 수단")) {
        _payMethods = (data["지출 수단"] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, List<String>.from(v)),
        );
      }

      AppLogger.i("✅ '$filePath' 카테고리 매핑 로드 완료");
    } catch (e) {
      AppLogger.i("⚠️ '$filePath' 로드 실패: $e");
    }
  }

  /// [메인] 입력 텍스트를 인식된 타입에 따라 파싱하는 함수
  List<String> parseInputLines(String rawInput) {
    if (rawInput.trim().isEmpty) return [];

    // 1단계: 원본(rawInput) 상태에서 입력 데이터 타입부터 먼저 감지
    final inputType = _detectInputType(rawInput);
    AppLogger.i(" 감지된 입력 타입: $inputType");

    // 2단계: 타입별 파싱 분기
    switch (inputType) {
      case InputType.excel:
      case InputType.csv:
        // Excel/CSV: 원본 줄바꿈(\n) 기준으로 분할 후, 각 줄에 대해 전처리(Pre-clean) 적용
        return rawInput
            .replaceAll('\r', '')
            .split('\n')
            .map((line) => _preCleanInput(line).trim())
            .where((line) => line.isNotEmpty)
            .toList();

      case InputType.txt:
        // TXT: 앵커 기반으로 문장 분할 진행
        return _parseTxtLinesByAnchors(rawInput);
    }
  }

  /// 단일 줄 텍스트를 파싱하여 Map<String, dynamic> 형태로 반환
  Map<String, dynamic> parseSingleLineToMap(
    String input, {
    InputType inputType = InputType.txt,
  }) {
    // -------------------------------------------------------------
    // [1단계: 사전 보정 (Normalize) - 체크카드(1329) -> 체크카드]
    // -------------------------------------------------------------
    String normalizedText = _config.normalizeText(input);
    AppLogger.i("🔹 1차 보정 완료 라인 : $normalizedText");

    // -------------------------------------------------------------
    // [2단계: 사전 정제 (_preCleanInput)]
    // -------------------------------------------------------------
    String workingText = _preCleanInput(normalizedText);
    AppLogger.i("🔹 _preCleanInput 완료 라인 : $workingText");

    if (workingText.isEmpty) {
      throw FormatException("입력된 텍스트가 비어있습니다.");
    }

  DateTime? date;
  int? amount;
  TransactionType type = TransactionType.expense;
  String? payMethod;
  String? category;

  // -------------------------------------------------------------
  // [1단계: 날짜 추출 & 제거]
  // -------------------------------------------------------------
  final parsedResult = _parseDate(workingText);
  if (parsedResult != null) {
    date = parsedResult.date;
    // _parseDate 내부에서 실제로 찾은 날짜 문자열만 문장에서 삭제
    workingText = workingText.replaceFirst(parsedResult.matchedText, ' ').trim();
  }


  // -------------------------------------------------------------
  // [2단계: 금액 추출 & 제거]
  // -------------------------------------------------------------
  final amountResult = _parseAmount(workingText);
  if (amountResult != null) {
    amount = amountResult.amount;
    // 문장에서 찾은 금액 문자열만 제거
    workingText = workingText.replaceFirst(amountResult.matchedText, ' ').trim();
  }

  // -------------------------------------------------------------
  // [3단계: 결제수단 추출 & 제거]
  // -------------------------------------------------------------
  final payMethodResult = _matchPayMethod(workingText);
  if (payMethodResult != null) {
    payMethod = payMethodResult.payMethod; // 예: "신용카드" 또는 "체크카드"
    // 실제로 문장에서 발견된 키워드 또는 카드번호 문자열 제거
    workingText = workingText.replaceFirst(payMethodResult.matchedText, ' ').trim();
  }

  // -------------------------------------------------------------
  // [4단계: 거래 유형 및 카테고리 추출 & 제거]
  // -------------------------------------------------------------
  if (_isIncomeType(workingText)) {
    type = TransactionType.income;
  }

  final foundCategory = _matchCategory(workingText, type: type);
  if (foundCategory != null) {
    category = foundCategory;
  }

  // -------------------------------------------------------------
  // [5단계: 적요(Description) 최종 정제]
  // -------------------------------------------------------------
  // 설정 파일의 불필요 키워드 제거 + 불필요한 공백 정리
  String description = _cleanRemainingDescription(workingText);

  if (description.isEmpty) {
    description = category ?? "미지정 내역";
  }

  // 기본값 보정
  date ??= DateTime.now();
  amount ??= 0;

  final result = {
    'date': date,
    'type': type,
    'payMethod': payMethod,
    'description': description,
    'amount': amount,
    'category': category ?? "미입력",
  };

  AppLogger.i("✅ [파싱 결과 Map]: $result");
  return result;
}


/// 남은 텍스트에서 노이즈/카테고리명 등을 제거하고 적요로 다듬는 헬퍼
String _cleanRemainingDescription(String text) {
  String cleaned = text;

  // 카테고리명, 결제수단명 등이 적요에 남아있다면 제거
  final groupHeaderKeys = {
    ..._incomeCategories.keys,
    ..._payMethods.keys,
    ..._expenseCategories.keys,
  };

  for (final key in groupHeaderKeys) {
    cleaned = cleaned.replaceAll(key, ' ');
  }

  // 특수문자 정제 및 연속 공백을 하나로 압축
  return cleaned
      .replaceAll(RegExp(r'(?<=\s|^)[^\w\s가-힣]+(?=\s|$)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}



  // ==========================================
  // Private 헬퍼 함수들
  // ==========================================
  /// 💡 [완전 자동화 전처리] JSON Config에만 의존하여 사전 정제 수행
  String _preCleanInput(String rawInput) {
    if (rawInput.trim().isEmpty) return '';
    return _config.cleanText(rawInput);
  }

  /// 입력된 텍스트의 타입을 자동 감지하는 헬퍼 함수
  InputType _detectInputType(String rawInput) {
    // \r 제거 후 줄 단위 분리
    final lines = rawInput.replaceAll('\r', '').trim().split('\n');
    if (lines.isEmpty) return InputType.txt;

    // 빈 줄을 제외한 실제 데이터 줄 검사 (최대 5줄 샘플링)
    final nonEmplyLines = lines.where((l) => l.trim().isNotEmpty).take(5).toList();
    if (nonEmplyLines.isEmpty) return InputType.txt;

    // 1. Excel (Tab 구분) 규칙성 검사
    final tabCounts = nonEmplyLines.map((l) => '\t'.allMatches(l).length).toList();
    final firstTabCount = tabCounts.first;
    if (nonEmplyLines.length > 1 && firstTabCount > 0 && tabCounts.every((count) => count == firstTabCount)) {
      return InputType.excel;
    }

    // 2. CSV (Comma 구분) 규칙성 검사
    final csvCounts = nonEmplyLines.map((l) => ','.allMatches(l).length).toList();
    final firstCsvCount = csvCounts.first;
    if (nonEmplyLines.length > 1 && firstCsvCount > 0 && csvCounts.every((count) => count == firstCsvCount)) {
      return InputType.csv;
    }

    // 3. 규칙이 없으면 일반 TXT
    return InputType.txt;
  }


  /// [TXT 전용] config 정규식 + 줄바꿈 기반 완성도(날짜+금액) 분할 함수
  List<String> _parseTxtLinesByAnchors(
    String text, {
    TransactionParserConfig? config,
  }) {
    if (text.trim().isEmpty) return [];
  
    final List<String> resultLines = [];
    String remainingText = text.replaceAll('\n', ' ').replaceAll('\r', ' ');
  
    while (remainingText.trim().isNotEmpty) {
      String originalTextForLoop = remainingText;
  
      // 1. 날짜와 금액 파싱 시도
      final dateResult = _parseDate(remainingText);
      final amountResult = _parseAmount(remainingText);
  
      // 2. 날짜와 금액이 모두 있어야 유효한 거래로 간주
      if (dateResult == null || amountResult == null) {
        break; // 더 이상 파싱할 거래가 없으면 루프 종료
      }
  
      // 3. 현재 루프에서 처리할 텍스트의 끝 지점(boundary) 찾기
      // 다음 거래의 시작 날짜 바로 앞까지를 현재 거래의 범위로 설정
      String tempText = remainingText.replaceFirst(dateResult.matchedText, 'DATE_HOLDER');
      final nextDateMatch = _fullDatePattern.firstMatch(tempText);
      
      int endBoundary = originalTextForLoop.length;
      if (nextDateMatch != null) {
        // 원본 텍스트에서 다음 날짜의 시작 인덱스를 찾음
        final nextDateStartIndex = originalTextForLoop.indexOf(nextDateMatch.group(0)!, dateResult.matchedText.length);
        if(nextDateStartIndex != -1) {
          endBoundary = nextDateStartIndex;
        }
      }
  
      // 4. 현재 거래 라인 추출 및 남은 텍스트 업데이트
      String currentLine = originalTextForLoop.substring(0, endBoundary);
      remainingText = originalTextForLoop.substring(endBoundary);
  
      // 5. 추출된 라인 추가
      resultLines.add(currentLine.trim());
    }

    AppLogger.i("🔹 [TXT 전용] 완성도 기반 분할 결과 (${resultLines.length}개):");
    for (int idx = 0; idx < resultLines.length; idx++) {
      AppLogger.i("   Line ${idx + 1}: \"${resultLines[idx]}\"");
    }
    return resultLines;
  }



  /// 💡 [날짜 단독 파싱 함수]
  ({DateTime date, String matchedText})? _parseDate(dynamic input) {
    if (input is! String) return null;

    final text = input.trim();
    if (text.isEmpty) return null;

    // 1. 통합 정규식 패턴 파싱 (_fullDatePattern)
    final match = _fullDatePattern.firstMatch(text);
    if (match != null) {
      final matchedText = match.group(0)!; // 문장에서 실제 찾아낸 날짜 텍스트 전체
      final yearStr = match.group(1);
      final monthStr = match.group(2)!;
      final dayStr = match.group(3)!;
      final hourStr = match.group(4);
      final minuteStr = match.group(5);

      final now = DateTime.now();
      final year = yearStr != null ? int.parse(yearStr) : now.year;
      final month = int.parse(monthStr);
      final day = int.parse(dayStr);
      final hour = hourStr != null ? int.parse(hourStr) : 0;
      final minute = minuteStr != null ? int.parse(minuteStr) : 0;

      return (
        date: DateTime(year, month, day, hour, minute),
        matchedText: matchedText,
      );
    }

    // 2. 상대 날짜 키워드 처리
    if (text.contains("오늘")) {
      return (date: DateTime.now(), matchedText: "오늘");
    }
    if (text.contains("어제")) {
      return (
        date: DateTime.now().subtract(const Duration(days: 1)),
        matchedText: "어제"
      );
    }
    return null;
  }


  /// 문장에서 금액을 감지하여 파싱된 금액(int)과 매칭된 문자열을 함께 반환
  ({int amount, String matchedText})? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;

    // 1. '원'이 포함된 금액 우선 탐색 (천 단위 쉼표 허용)
    // 💡 [수정] 음수(-) 기호를 포함하도록 정규식 수정
    final wonPattern = RegExp(r'(-?\d{1,3}(?:,\d{3})+|-?\d+)\s*원');
    final wonMatches = wonPattern.allMatches(text);

    for (final match in wonMatches) {
      final matchedText = match.group(0)!;
      final numStr = match.group(1)!.replaceAll(',', '');

      if (numStr.length > 1 && (numStr.startsWith('0') || numStr.startsWith('-0'))) continue;

      final parsedNum = int.tryParse(numStr);
      if (parsedNum != null && parsedNum != 0) {
        return (amount: parsedNum, matchedText: matchedText);
      }
    }

    // 2. '원'이 없는 일반 숫자들 수집 및 조건 필터링
    final rawNumRegExp = RegExp(r'\b\d+(?:,\d{3})*\b');
    final rawMatches = rawNumRegExp.allMatches(text);
    // 💡 [추가] 음수 기호가 붙은 숫자 탐색
    final negNumRegExp = RegExp(r'-\d+(?:,\d{3})*');
    final List<({int amount, String matchedText})> candidates = [];

    for (final match in rawMatches) {
      final matchedText = match.group(0)!;
      final numStr = matchedText.replaceAll(',', '');

      // 조건 2-1: 0으로 시작하는 숫자 제외 (승인번호, 카드번호, 단일 0 제외)
      if (numStr.length > 1 && numStr.startsWith('0')) continue;

      final parsed = int.tryParse(numStr);
      if (parsed == null || parsed == 0) continue;

      // 연도 범위(2020~2030) 숫자는 기본 제외
      if (parsed >= 2020 && parsed <= 2030) continue;

      candidates.add((amount: parsed, matchedText: matchedText));
    }

    // 음수 숫자 후보 추가
    for (final match in negNumRegExp.allMatches(text)) {
      final matchedText = match.group(0)!;
      final numStr = matchedText.replaceAll(',', '');
      final parsed = int.tryParse(numStr);
      if (parsed != null && parsed != 0) {
        candidates.add((amount: parsed, matchedText: matchedText));
      }
    }


    if (candidates.isEmpty) return null;

    // 조건 2-2: 뒷자리가 0으로 끝나는 숫자 필터링 (결제금액 우대)
    final endsWithZero = candidates.where((c) => c.amount % 10 == 0).toList();

    if (endsWithZero.isNotEmpty) {
      // 조건 2-3: 0으로 끝나는 후보가 여럿(누적금액 등)이면 더 작은 금액 선택
      endsWithZero.sort((a, b) => a.amount.compareTo(b.amount));
      return endsWithZero.first;
    }

    // 0으로 끝나는 후보가 없다면 잔여 후보 중 가장 작은 숫자 선택
    candidates.sort((a, b) => a.amount.compareTo(b.amount));
    return candidates.first;
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

/// 문장에서 결제수단(카드번호 BIN 식별 또는 키워드 매칭)을 감지하여
/// 최종 결제수단 Key와 문장에서 지울 매칭 텍스트를 함께 반환
({String payMethod, String matchedText})? _matchPayMethod(String text) {
  if (text.trim().isEmpty) return null;

  // -------------------------------------------------------------
  // [A] 카드번호 패턴 감지 시 BIN 조회 처리
  // -------------------------------------------------------------
  final cardMatch = _cardNoPattern.firstMatch(text);
  if (cardMatch != null) {
    final cardStr = cardMatch.group(0)!;
    final cleanDigits = cardStr.replaceAll(RegExp(r'[^0-9]'), '');

    String? issuer;
    if (cleanDigits.length >= 6) {
      final bin6 = cleanDigits.substring(0, 6);
      issuer = _binData[bin6]?['전표인자명']?.toString();
    }

    // BIN 조회가 성공한 경우 해당 발급사명이 속한 대표 Key("신용카드" 등) 탐색
    if (issuer != null && issuer.isNotEmpty) {
      for (var entry in _payMethods.entries) {
        final mainKey = entry.key;
        final keywords = entry.value;

        if (keywords is List && keywords.contains(issuer)) {
          return (payMethod: mainKey, matchedText: cardStr);
        }
      }
      // 매칭되는 대표 Key가 없으면 전표인자명 또는 기본값 사용
      return (payMethod: issuer, matchedText: cardStr);
    }

    // BIN 조회 실패 시 기본 "신용카드"로 분류하고 카드번호 제거
    return (payMethod: "신용카드", matchedText: cardStr);
  }

  // -------------------------------------------------------------
  // [B] 텍스트 키워드 매칭 (Key 및 Value 순회)
  // -------------------------------------------------------------
  // 키워드가 긴 순서대로 정렬하여 "KB국민카드"가 "카드"보다 먼저 매칭되도록 처리
  final List<({String mainKey, String keyword})> searchList = [];

  for (var entry in _payMethods.entries) {
    final String mainKey = entry.key; // 예: "체크카드", "신용카드"

    // Key 자체도 검색 대상으로 추가
    searchList.add((mainKey: mainKey, keyword: mainKey));

    // Value 리스트 단어 추가
    if (entry.value is List) {
      for (var kw in (entry.value as List)) {
        final keywordStr = kw.toString().trim();
        if (keywordStr.isNotEmpty) {

          searchList.add((mainKey: mainKey, keyword: keywordStr));
        }
      }
    }
  }

  // 매칭 우선순위를 위해 키워드 길이가 긴 순으로 정렬
  searchList.sort((a, b) => b.keyword.length.compareTo(a.keyword.length));

  for (var item in searchList) {
    if (text.contains(item.keyword)) {
      return (
        payMethod: item.mainKey,      // 최종 리턴되는 Key ("신용카드", "체크카드" 등)
        matchedText: item.keyword,    // 문장에서 삭제할 단어 ("신한카드", "카카오뱅크" 등)
      );
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

    // 1. 대분류 키(예: 교통비) 직접 포함 여부 체크
    for (var categoryKey in categories.keys) {
      if (token.contains(categoryKey)) {
        return categoryKey;
      }
    }

    // 2. 카테고리 구조 순회
    for (var entry in categories.entries) {
      final dynamic subContent = entry.value;

      // A. 하위 구조가 Map인 경우 (2계층: 교통비 -> 차량/주유 -> [키워드들])
      if (subContent is Map) {
        for (var subEntry in subContent.entries) {
          //final subCategoryKey = subEntry.key.toString();
          final keywords = subEntry.value;

          if (keywords is List) {
            for (var keyword in keywords) {
              if (token.contains(keyword.toString())) {
                return entry.key; // "차량/주유" 반환 (대분류를 원하시면 entry.key 반환)
              }
            }
          }
        }
      }
      // B. 하위 구조가 List인 경우 (1계층: 식비 -> [키워드들])
      else if (subContent is List) {
        for (var keyword in subContent) {
          if (token.contains(keyword.toString())) {
            return entry.key;
          }
        }
      }
    }

    return null;
  }



}
