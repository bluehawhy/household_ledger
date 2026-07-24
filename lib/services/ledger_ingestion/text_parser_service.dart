import 'dart:convert';
import 'dart:io';
// 1. googleapis sheets 패키지 import (sheets Prefix 지정)
import 'package:googleapis/sheets/v4.dart' as sheets;
// 2. appendTransactionData가 작성되어 있는 파일 import
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';




/// 텍스트 입력을 분석하여 LedgerItem 객체로 변환하는 순수 파서 서비스
class TextParserService {
  // 1. sheetService 객체 선언 및 초기화
  final HouseholdSheetService sheetService = HouseholdSheetService();

  Map<String, List<String>> _incomeCategories = {};
  Map<String, List<String>> _expenseCategories = {};
  Map<String, List<String>> _payMethods = {};
  Map<String, dynamic> _binData = {};

  /// 루트에 있는 'ledger_ingestion_info.json' 파일을 로드하여 초기화합니다.
  Future<void> init([String filePath = 'ledger_ingestion_info.json']) async {
    // ➕ [추가] card_bin_data.json 파일 로드 로직
    final binFile = File('card_bin_data.json');
    if (await binFile.exists()) {
      try {
        final binJsonString = await binFile.readAsString();
        _binData = jsonDecode(binJsonString) as Map<String, dynamic>;
        print("✅ [TextParserService] BIN 데이터 로드 완료 (${_binData.length}개)");
      } catch (e) {
        print("❌ [TextParserService] BIN 데이터 로드 에러: $e");
      }
    } else {
      print("⚠️ [TextParserService] 'card_bin_data.json' 파일을 찾을 수 없습니다.");
    }

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
    // 💳 카드번호 패턴 (숫자, *, - 가 섞여 있는 12~19자리 카드번호 마스킹 형태)
    //// 예: 4987-61**-****-5083, 1234-****-****-5678, 498761******5083 등 모두 감지
    final cardNoPattern = RegExp(r'^\d{4}[-*\s]+[\d*]{2,4}[-*\s]+[\d*]{2,4}[-*\s]+\d{4}$');
    final bizNoPattern = RegExp(r'^\d{3}-\d{2}-\d{5}$');                              // 사업자번호
    final fullDatePattern = RegExp(r'^(\d{4})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$'); // YYYY-MM-DD
    final shortDatePattern = RegExp(r'^(0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])$');            // MM-DD
    final amountPattern = RegExp(r'^(\d{1,3}(,\d{3})*|\d+)(원)?$');                           // 금액 (10,600 / 10600원)

    for (String token in tokens) {
      // A. 카드번호 토큰 감지 시 결제수단 자동 바인딩 후 스킵
      if (cardNoPattern.hasMatch(token)) {
        payMethod ??= _detectCardIssuer(token); // 카드사 자동 추정 (실패 시 "신용카드")
        continue;
      }

      // 사업자번호 또는 마스킹 토큰 스킵
      if (bizNoPattern.hasMatch(token) || '*'.allMatches(token).length >= 2) {
        continue;
      }

      // B. 날짜 추출 (아직 날짜를 안 찾은 경우)
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

      // C. 금액 추출 (아직 금액을 안 찾은 경우)
      if (amount == null) {
        final amountMatch = amountPattern.firstMatch(token);
        // "일시불", "정상" 같은 단어가 금액으로 잘못 들어가는 것 방지
        if (amountMatch != null && !_isIgnoredWord(token)) {
          String rawNumStr = amountMatch.group(1)!.replaceAll(',', '');
          int parsedNum = int.parse(rawNumStr);
          if (parsedNum > 0) {
            amount = parsedNum;
            continue;
          }
        }
      }

      // D. 수입/지출 유형 판단
      if (token.contains("수입") || token.contains("입금") || token.contains("월급") || token.contains("환불")) {
        type = TransactionType.income;
        continue;
      }
      
      // E. 지출 수단 매칭 ("신한카드", "카카오페이" 등 독립된 결제수단 토큰)
      if (payMethod == null) {
        String? foundPayMethod = _matchPayMethod(token);
        if (foundPayMethod != null) {
          payMethod = foundPayMethod;
          continue; // 결제수단 토큰은 내역(description)에서 제외하고 다음 토큰으로
        }
      }

      // F. 카테고리 매칭 (💡 중요: continue를 하지 않고 아래 G로 흘려보냅니다!)
      if (category == null) {
        String? foundCategory = _matchCategory(token, type: type);
        if (foundCategory != null) {
          category = foundCategory; // continue 구문 제거
        }
      }

      // G. 무시 단어("정상", "일시불" 등)가 아니라면 무조건 내역(description) 후보에 추가!
      if (!_isIgnoredWord(token)) {
        remainingTokens.add(token);
      }
    }

    // 기본값 보정
    date ??= DateTime.now();
    amount ??= 0;

    // 카테고리가 안 잡혔다면 남은 토큰에서 카테고리 재탐색 시도
    if (category == null && remainingTokens.isNotEmpty) {
      for (String t in remainingTokens) {
        category = _matchCategory(t, type: type);
        if (category != null) break;
      }
    }

    // 내역(description) 결합
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

  /// 무시할 단어 목록 ("정상", "일시불", "승인" 등)
  bool _isIgnoredWord(String token) {
    const ignoredList = ["정상", "일시불", "승인", "취소", "완료"];
    return ignoredList.contains(token);
  }

  /// 지출 수단 매칭 헬퍼
  String? _matchPayMethod(String token) {
    for (var entry in _payMethods.entries) {
      for (var keyword in entry.value) {
        if (token.contains(keyword)) {
          return entry.key; // 예: "신용카드"
        }
      }
    }
    return null;
  }
  
// ✏️ [수정] 카드번호(또는 BIN) 기반으로 카드사를 추정하는 헬퍼 함수
  String _detectCardIssuer(String token) {
    // 1. 숫자 이외의 모든 문자 제거 (하이픈, 별표, 공백 등)
    final clean = token.replaceAll(RegExp(r'[^0-9]'), '');

    // 2. 숫자가 6자리 이상인 경우 앞 6자리 BIN으로 카드사 조회
    if (clean.length >= 6) {
      final bin6 = clean.substring(0, 6);
      final issuer = _binData[bin6]?['전표인자명'];

      // 값이 존재하면 해당 카드사 명칭 반환
      if (issuer != null && issuer.toString().isNotEmpty) {
        return issuer.toString();
      }
    }

    // 3. 6자리 미만이거나, JSON 데이터에 Matching 되는 BIN이 없는 경우 기본값 반환
    return '신용카드';
  }
  /// 카테고리 매칭 헬퍼
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

/// 텍스트 파싱 후 appendTransactionData를 호출해 시트에 삽입하는 메서드
  Future<void> appendParseSingleLine(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    String input,
  ) async {
    if (input.trim().isEmpty) return;

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
    await sheetService.appendTransactionData(
      sheetsApi,
      spreadsheetId,
      sheetName,
      existingRows,
      item,
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