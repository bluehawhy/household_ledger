//ledger_item.dart

import 'dart:convert';
import 'package:household_ledger/services/utils/asset_loader.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


/// 거래 유형 (수입 / 지출)
enum TransactionType {
  income,
  expense;

  String toJson() => name;
  static TransactionType fromString(String? typeStr) {
    if (typeStr == 'income') return TransactionType.income;
    return TransactionType.expense;
  }
}

/// 가계부 거래 항목 모델
class LedgerItem {
  final DateTime date;        // 입력 날짜
  final TransactionType type; // 수입 or 지출
  final String? payMethod;    // 결제/지출 수단
  final String category;      // 분류
  final String description;   // 내용
  final int amount;           // 금액
  final String memo;          // 기타 메모
  final String rawTxt;        // 사용자 입력 원문

  const LedgerItem({
    required this.date,
    required this.type,
    this.category = '미입력',
    required this.description,
    required this.amount,
    this.payMethod,
    this.memo = '',
    this.rawTxt = '',
  });

  /// YYYY-MM-DD 형식의 날짜 문자열 반환 게터
  String get formattedDate {
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Map 데이터를 받아 LedgerItem 객체를 생성하는 팩토리 생성자
  factory LedgerItem.fromMap(Map<String, dynamic> map) {
    // DateTime 파싱 처리 (DateTime 객체 또는 ISO8601 String 지원)
    DateTime parsedDate;
    if (map['date'] is DateTime) {
      parsedDate = map['date'] as DateTime;
    } else if (map['date'] is String) {
      parsedDate = DateTime.tryParse(map['date'] as String) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    // TransactionType 파싱 처리
    TransactionType parsedType;
    if (map['type'] is TransactionType) {
      parsedType = map['type'] as TransactionType;
    } else {
      parsedType = TransactionType.fromString(map['type'] as String?);
    }

    return LedgerItem(
      date: parsedDate,
      type: parsedType,
      category: map['category'] as String? ?? '미입력',
      payMethod: map['payMethod'] as String?,
      description: map['description'] as String? ?? '미지정 내역',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      memo: map['memo'] as String? ?? '',
      rawTxt: map['raw_txt'] as String? ?? map['rawTxt'] as String? ?? '',
    );
  }

  /// LedgerItem 객체를 Map 형태로 변환
  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'type': type.toJson(),
      'category': category,
      'payMethod': payMethod,
      'description': description,
      'amount': amount,
      'memo': memo,
      'raw_txt': rawTxt,
    };
  }

  /// JSON 문자열로부터 생성
  factory LedgerItem.fromJson(String source) =>
      LedgerItem.fromMap(json.decode(source) as Map<String, dynamic>);

  /// JSON 문자열로 변환
  String toJson() => json.encode(toMap());

  /// 불변 객체 값 변경용 copyWith
  LedgerItem copyWith({
    DateTime? date,
    TransactionType? type,
    String? category,
    String? payMethod,
    String? description,
    int? amount,
    String? memo,
    String? rawTxt,
  }) {
    return LedgerItem(
      date: date ?? this.date,
      type: type ?? this.type,
      category: category ?? this.category,
      payMethod: payMethod ?? this.payMethod,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      memo: memo ?? this.memo,
      rawTxt: rawTxt ?? this.rawTxt,
    );
  }

  @override
  String toString() {
    return 'LedgerItem(date: $formattedDate, type: ${type.name}, category: $category, description: $description, amount: $amount, payMethod: $payMethod, memo: $memo, rawTxt: $rawTxt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LedgerItem &&
        other.date == date &&
        other.type == type &&
        other.category == category &&
        other.payMethod == payMethod &&
        other.description == description &&
        other.amount == amount &&
        other.memo == memo &&
        other.rawTxt == rawTxt;
  }

  @override
  int get hashCode {
    return Object.hash(
      date,
      type,
      category,
      payMethod,
      description,
      amount,
      memo,
      rawTxt,
    );
  }
}

// ============================================================================
// JSON 기반 카테고리 자동 매퍼
// ============================================================================
class CategoryMapper {
  // 💡 싱글톤 인스턴스 생성
  static final CategoryMapper _instance = CategoryMapper._internal();
  factory CategoryMapper() => _instance;
  CategoryMapper._internal();

  // 카테고리명 -> 키워드 리스트 매핑
  Map<String, List<String>> incomeCategories = {};
  Map<String, List<String>> expenseCategories = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> loadCategoryJson([String filePath = 'assets/ledger_ingestion_info.json']) async {
    if (_isLoaded) return;
    try {
      final jsonString = await JsonAssetManager.loadJson(filePath);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // 단일 리스트 or 중첩 Map 구조에 관계없이 모든 키워드를 Flatten(평탄화) 추출하는 헬퍼 함수
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
      AppLogger.i("카테고리 JSON 데이터 로드 완료! (수입: ${incomeCategories.length}개, 지출: ${expenseCategories.length}개 항목)");
      _isLoaded = true;
    } catch (e) {
      AppLogger.i("JSON 로드/파싱 에러 ($filePath): $e");
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
