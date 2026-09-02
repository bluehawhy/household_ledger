import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';

/// Google Sheets의 거래 행과 [LedgerItem] 사이의 변환을 담당한다.
class LedgerRowMapper {
  static const List<String> defaultHeader = [
    '날짜',
    '거래유형',
    '거래 수단',
    '분류',
    '내용',
    '금액',
    '메모',
  ];

  /// [LedgerItem]을 Google Sheets 한 행으로 변환한다.
  static List<Object?> toRow(LedgerItem item) {
    final isIncome = item.type == TransactionType.income;

    return [
      item.formattedDate,
      isIncome ? '수입' : '지출',
      item.payMethod ?? '-',
      item.category,
      item.description,
      item.amount,
      item.memo,
    ];
  }

  /// Google Sheets 한 행을 [LedgerItem]으로 변환한다.
  ///
  /// 유효하지 않은 행은 null을 반환한다.
  static LedgerItem? fromRow(List<dynamic> row) {
    if (row.length <= 5) return null;

    final rawDate = row[0].toString().trim();
    final rawType = row[1].toString().trim();
    final rawPayMethod = row[2].toString().trim();
    final rawCategory = row[3].toString().trim();
    final rawDescription = row[4].toString().trim();
    final rawAmount = row[5].toString().replaceAll(',', '').trim();
    final rawMemo = row.length > 6 ? row[6].toString().trim() : '';

    if (rawDate.isEmpty || rawAmount.isEmpty || rawDescription.isEmpty) {
      return null;
    }

    final parsedDate = DateTime.tryParse(rawDate);
    final parsedAmount = int.tryParse(rawAmount);

    if (parsedDate == null || parsedAmount == null) return null;

    return LedgerItem(
      date: parsedDate,
      type: rawType == '수입'
          ? TransactionType.income
          : TransactionType.expense,
      description: rawDescription,
      amount: parsedAmount,
      category: rawCategory.isNotEmpty ? rawCategory : '미분류',
      payMethod: rawPayMethod.isNotEmpty && rawPayMethod != '-'
          ? rawPayMethod
          : null,
      memo: rawMemo,
    );
  }

  /// 거래 목록을 Sheets [ValueRange]의 행 목록으로 변환한다.
  static List<List<Object?>> toRows(Iterable<LedgerItem> items) {
    return items.map(toRow).toList();
  }

  /// 단일 행을 Sheets [ValueRange]로 생성한다.
  static sheets.ValueRange toValueRange({
    required String range,
    required LedgerItem item,
  }) {
    return sheets.ValueRange(
      range: range,
      values: [toRow(item)],
    );
  }
}
