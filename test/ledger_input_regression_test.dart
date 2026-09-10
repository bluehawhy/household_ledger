import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final parser = TextParserService();
  final mapper = CategoryMapper();

  setUpAll(() async {
    await parser.init();
    await mapper.loadCategoryJson();
  });

  test('입력 분류와 조회 분류가 일치하고 기존 분류를 보존한다', () {
    final item = parser.parseSingleLineToMap('2026/9/10 10,600원 점심');
    expect(item['category'], '식비 > 식당/외식');
    expect(mapper.expenseCategories.containsKey(item['category']), isTrue);
    expect(mapper.normalizeCategory('식당/외식', isIncome: false), '식비 > 식당/외식');
    expect(mapper.normalizeCategory('식비', isIncome: false), '식비');
    expect(mapper.normalizeCategory('', isIncome: false), '미분류');
  });

  test('날짜와 금액 누락을 구분하여 안내한다', () {
    for (final sample in {'점심 10,600원': '날짜', '2026/9/10 점심': '금액', '점심': '날짜'}.entries) {
      expect(parser.parseInputLines(sample.key), isNotEmpty);
      expect(() => parser.parseSingleLineToMap(sample.key),
          throwsA(isA<FormatException>().having((e) => e.message, 'reason', contains(sample.value))));
    }
  });

  test('정상 내역 뒤의 금액 누락 내역도 버리지 않는다', () {
    final lines = parser.parseInputLines('2026/9/10 5000원 점심\n2026/9/11 저녁');
    expect(lines, hasLength(2));
    expect(parser.parseSingleLineToMap(lines.first)['amount'], 5000);
    expect(() => parser.parseSingleLineToMap(lines.last), throwsFormatException);
  });

  test('존재하지 않는 날짜를 다음 달로 자동 저장하지 않는다', () {
    expect(() => parser.parseSingleLineToMap('2026/2/30 5000원 점심'), throwsFormatException);
  });
}
