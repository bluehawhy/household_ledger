// lib/services/ledger_ingestion/ledger_item.dart

/// 거래 유형 (수입 / 지출)
enum TransactionType { income, expense }

/// 가계부 거래 항목 모델
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

  /// 🚀 [추가] YYYY-MM-DD 형식의 날짜 문자열 반환 게터
  String get formattedDate {
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Map 데이터를 받아 LedgerItem 객체를 생성하는 팩토리 생성자
  factory LedgerItem.fromMap(Map<String, dynamic> map) {
    return LedgerItem(
      date: map['date'] as DateTime? ?? DateTime.now(),
      type: map['type'] as TransactionType? ?? TransactionType.expense,
      payMethod: map['payMethod'] as String?,
      description: map['description'] as String? ?? '미지정 내역',
      amount: map['amount'] as int? ?? 0,
      category: map['category'] as String? ?? '미입력',
    );
  }
}