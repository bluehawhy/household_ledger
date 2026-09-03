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
    'raw_txt',
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
      item.rawTxt,
    ];
  }

  /// 헤더 이름에 해당하는 [LedgerItem] 값을 반환한다.
  static Object? valueForHeader(LedgerItem item, Object? header) {
    final targetHeader = _normalizeHeader(header);
    final defaultIndex = defaultHeader.indexWhere(
      (value) => _normalizeHeader(value) == targetHeader,
    );
    if (defaultIndex == -1) return null;
    return toRow(item)[defaultIndex];
  }

  /// 헤더 행에서 지정한 헤더의 실제 열 위치를 찾는다.
  static int? indexOfHeader(List<dynamic> headers, String header) {
    final targetHeader = _normalizeHeader(header);
    final index = headers.indexWhere(
      (value) => _normalizeHeader(value) == targetHeader,
    );
    return index == -1 ? null : index;
  }

  /// 0부터 시작하는 열 번호를 Google Sheets 열 이름으로 변환한다.
  static String columnName(int columnIndex) {
    var value = columnIndex + 1;
    final buffer = StringBuffer();
    while (value > 0) {
      value--;
      buffer.writeCharCode(65 + (value % 26));
      value ~/= 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  /// Google Sheets 한 행을 [LedgerItem]으로 변환한다.
  ///
  /// 유효하지 않은 행은 null을 반환한다.
  static LedgerItem? fromRow(
    List<dynamic> row, {
    List<dynamic>? headers,
  }) {
    String readValue(String header) {
      final index = headers == null
          ? defaultHeader.indexOf(header)
          : indexOfHeader(headers, header);
      if (index == null || index < 0 || index >= row.length) return '';
      return row[index].toString().trim();
    }

    final rawDate = readValue('날짜');
    final rawType = readValue('거래유형');
    final rawPayMethod = readValue('거래 수단');
    final rawCategory = readValue('분류');
    final rawDescription = readValue('내용');
    final rawAmount = readValue('금액').replaceAll(',', '');
    final rawMemo = readValue('메모');
    final rawTxt = readValue('raw_txt');

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
      rawTxt: rawTxt,
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

  static String _normalizeHeader(Object? value) {
    return value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]'), '');
  }
}
