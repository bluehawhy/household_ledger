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
    "거래일	카드구분	가맹점명	금액",
    //"2026.07.27 11:52	신한카드	네이버페이-제로맥주구매	3,000",
    //"2026.07.23 06:06	신한카드	네이버페이 - 양파구매	2,490",
    //"2026.07.22 11:09	신한카드	네이버플러스 멤버십	4,900",
    //"2026.06.22 11:07	신한카드	네이버플러스 멤버십	4,900",
    "2026-08-15 수정약국 5000원",
    //"2026.05.15 12:38	신한카드	부산시설공단	4,000	교통비",
    //"2026.07.21 16:29	신한카드	파랑약국	6,230	",
    //"카드결제 4000원 \n08/04 16:09 체크카드(1329) \n교통비  부산시설공단 잔액 1,332,695원 \n 우리2주유소 \n56000원 \n거래일 \n 2026.08.01 13:36\n 거래구분 일시불 승인번호 08387779 거래상태 승인 이용카드 본인 040*",
    //"08/04 16:09 카드 결제 4,000원 체크카드(1329) 부산시설공단 잔액 1,132,693원"
  ];
  for (int i = 0; i < testInputs.length; i++) {
    final rawInput = testInputs[i];
    AppLogger.i("--------------------------------------------------");
    AppLogger.i("📌 [Input Case ${i + 1}] 원본 입력:");
    AppLogger.i(rawInput);
    AppLogger.i("--------------------------------------------------");

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