import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/text_parser_service.dart';

void main() async {
  print("==================================================");
  print("🧪 [TextParserService] ledger_ingestion_info.json 연동 테스트");
  print("==================================================");

  final parser = TextParserService();
  
  // 최상단의 ledger_ingestion_info.json 비동기 로드
  await parser.init();

  // 테스트에 사용할 다양한 유형의 입력 텍스트 샘플
  final List<String> testInputs = [
    "2026-07-20 점심 김치찌개 11000원 신용카드",
    "어제 택시비 14,500원 카카오페이",
    "07/22 7월 월급 3500000 계좌이체 수입",
    "오늘 스타벅스 자바칩 6500",
    "편의점 삼각김밥 1500 체크카드",
    "환불 처리 25000원 계좌이체",
    "7 25 민수신한카드 17000 커피타운구매"
  ];

  for (int i = 0; i < testInputs.length; i++) {
    final input = testInputs[i];
    print("\n[Case ${i + 1}] 입력: \"$input\"");

    try {
      final LedgerItem item = parser.parseSingleLine(input);

      print("  ├ 📅 날짜    : ${_formatDate(item.date)}");
      print("  ├ 🔄 유형    : ${item.type == TransactionType.income ? '수입' : '지출'}");
      print("  ├ 📂 카테고리 : ${item.category}");
      print("  ├ 🏷️ 내역    : ${item.description}");
      print("  ├ 💰 금액    : ${item.amount}원");
      print("  └ 💳 결제수단 : ${item.payMethod ?? '미지정'}");
      print("  ✅ 변환 성공!");
    } catch (e) {
      print("  ❌ 변환 실패: $e");
    }
  }

  print("\n==================================================");
}

String _formatDate(DateTime date) {
  final year = date.year;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return "$year-$month-$day";
}