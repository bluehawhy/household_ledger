import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

void main() async {
  AppLogger.i("==================================================");
  AppLogger.i("🧪 [TextParserService] 텍스트 파싱 & 전처리 단독 테스트");
  AppLogger.i("==================================================");

  final parser = TextParserService();

  // 최상단의 ledger_ingestion_info.json 및 카드 BIN 데이터 로드
  await parser.init();

  // 단일 줄, 줄바꿈(\n), 카드 내역 복사본 등 다양한 유형의 테스트 입력 데이터
  final List<String> testInputs = [
    "2025/11/1		KB국민카드	23,030 			쿠팡-쌀",
    "2025/11/1		KB국민카드	3,950 			쿠팡-건전지",
    "2025/11/1		KB국민카드	7,990 			쿠팡-변기클리너",
    "2025/11/2		KB국민카드	3,650 			쿠팡-우신변기스위치",
    "2025/11/2		KB국민카드	11,940 			쿠팡-에어컨바람막이",
    "2025/11/2		KB국민카드	8,530 			쿠팡-뽀모도로 시계",
    "2025/11/2		KB국민카드	19,900 			쿠팡-커피원두",
    "2025/11/9		KB국민카드	9,500 			쿠팡-스파게티면",
    "2025/11/9		KB국민카드	5,200 			쿠팡-아동된장",
    "2025/11/12		KB국민카드	13,770 			쿠팡-생리대",
    "2025/11/12		KB국민카드	8,980 			쿠팡-은채양말",
    "2025/11/17		KB국민카드	8,000 			쿠팡-싱크대세정제",
    "2025/11/28		KB국민카드	1,211 			쿠팡-신선왕만두",
    "2025/11/30		KB국민카드	9,430 			쿠팡-라디오배터리",
  ];
  for (int i = 0; i < testInputs.length; i++) {
    final rawInput = testInputs[i];
    AppLogger.i("--------------------------------------------------");
    AppLogger.i("📌 [Input Case ${i + 1}] 원본 입력:");
    AppLogger.i(rawInput);

    // 1. 입력 텍스트 전처리 및 라인 분할 (엔터/날짜 기준)
    final List<String> lines = parser.parseInputLines(rawInput);
    AppLogger.i("✂️ 분할된 문장 수: ${lines.length}개");

    // 2. 각 라인별 파싱 수행
    for (int j = 0; j < lines.length; j++) {
      final line = lines[j];
      AppLogger.i(" [Line ${j + 1}] \"$line\"");

      try {
        // Map 형태 반환
        final Map<String, dynamic> resultMap = parser.parseSingleLineToMap(line);

        final DateTime date = resultMap['date'];
        final TransactionType type = resultMap['type'];
        final String? payMethod = resultMap['payMethod'];
        final String description = resultMap['description'];
        final int amount = resultMap['amount'];
        final String category = resultMap['category'];

        AppLogger.i("   ├ 📅 날짜    : ${_formatDate(date)}");
        AppLogger.i("   ├ 🔄 유형    : ${type == TransactionType.income ? '수입' : '지출'}");
        AppLogger.i("   ├ 📂 카테고리 : $category");
        AppLogger.i("   ├ 🏷️ 내역    : $description");
        AppLogger.i("   ├ 💰 금액    : ${_formatAmount(amount)}원");
        AppLogger.i("   └ 💳 결제수단 : ${payMethod ?? '미지정'}");
        AppLogger.i("   ✅ 파싱 성공!");
      } catch (e) {
        AppLogger.i("   ❌ 파싱 실패: $e");
      }
    }
  }

  AppLogger.i("==================================================");
  AppLogger.i("🎉 모든 파싱 테스트가 완료되었습니다.");
  AppLogger.i("==================================================");
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