import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

void main() async {
  print("==================================================");
  print("🧪 [TextParserService] 텍스트 파싱 & 전처리 단독 테스트");
  print("==================================================");

  final parser = TextParserService();

  // 최상단의 ledger_ingestion_info.json 및 카드 BIN 데이터 로드
  await parser.init();

  // 단일 줄, 줄바꿈(\n), 카드 내역 복사본 등 다양한 유형의 테스트 입력 데이터
  final List<String> testInputs = [
  // 케이스 2: 엔터(\n)가 포함된 여러 건의 카드/통장 알림 문자 복사본
  "2026-1-3\t\t4987-61**-****-5083\t정상\t일시불\t10,600 \t\t\t쿠팡(쿠페이)-쿠팡(쿠페이)\t\t\t220-81-15770 2026/1/2\t\t4579-72**-****-3087\t정상\t일시불\t6,000 \t\t\t어오케이커피 센텀점\t\t\t235-48-01188\t일반과세자\n07/25 15:04\n 출금 \n\n88,220원 입출금통장(1483) → 메가마트\n02-10 15,000원 택시비 지출",
  
  // 케이스 3: 자연어 형태의 단일 내역
  "어제 12,500원 스타 벅스 신한카드"
];
  for (int i = 0; i < testInputs.length; i++) {
    final rawInput = testInputs[i];
    print("\n--------------------------------------------------");
    print("📌 [Input Case ${i + 1}] 원본 입력:");
    print(rawInput);
    print("--------------------------------------------------");

    // 1. 입력 텍스트 전처리 및 라인 분할 (엔터/날짜 기준)
    final List<String> lines = parser.parseInputLines(rawInput);
    print("✂️ 분할된 문장 수: ${lines.length}개");

    // 2. 각 라인별 파싱 수행
    for (int j = 0; j < lines.length; j++) {
      final line = lines[j];
      print("\n  [Line ${j + 1}] \"$line\"");

      try {
        // Map 형태 반환
        final Map<String, dynamic> resultMap = parser.parseSingleLineToMap(line);

        final DateTime date = resultMap['date'];
        final TransactionType type = resultMap['type'];
        final String? payMethod = resultMap['payMethod'];
        final String description = resultMap['description'];
        final int amount = resultMap['amount'];
        final String category = resultMap['category'];

        print("   ├ 📅 날짜    : ${_formatDate(date)}");
        print("   ├ 🔄 유형    : ${type == TransactionType.income ? '수입' : '지출'}");
        print("   ├ 📂 카테고리 : $category");
        print("   ├ 🏷️ 내역    : $description");
        print("   ├ 💰 금액    : ${_formatAmount(amount)}원");
        print("   └ 💳 결제수단 : ${payMethod ?? '미지정'}");
        print("   ✅ 파싱 성공!");
      } catch (e) {
        print("   ❌ 파싱 실패: $e");
      }
    }
  }

  print("\n==================================================");
  print("🎉 모든 파싱 테스트가 완료되었습니다.");
  print("==================================================");
}

String _formatDate(DateTime date) {
  final year = date.year;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return "$year-$month-$day";
}

String _formatAmount(int amount) {
  return amount.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
}