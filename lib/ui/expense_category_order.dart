/// 지출분류 선택 목록과 Overview가 공유하는 표시 순서입니다.
const expenseCategoryOrder = <String>[
    '식비 > 식당/외식',
    '식비 > 카페/디저트',
    '식비 > 배달',
    '식비 > 장보기/식재료',
    '식비 > 편의점',
    '고정지출 > 주거/공과금',
    '고정지출 > 통신비',
    '고정지출 > 보험',
    '고정지출 > 구독/멤버십',
    '생활비 > 생필품/위생',
    '생활비 > 가구/가전',
    '생활비 > 잡화/생활',
    '교통비 > 대중교통',
    '교통비 > 차량/주유',
    '교통비 > 주차/통행료',
    '쇼핑/패션 > 의류/잡화',
    '쇼핑/패션 > 뷰티/미용',
    '문화/여가 > 문화/공연',
    '문화/여가 > 여행/숙박',
    '문화/여가 > 운동/취미',
    '경조사 > 경조사/선물',
    '의료비 > 병원/의원',
    '의료비 > 약국/약품',
    '교육/자기개발 > 학원/강의',
    '교육/자기개발 > 도서/시험',
    '기타 > 기타/예비비',
  ];

/// 대분류가 포함된 이름과 기존 소분류 이름을 같은 순위로 처리합니다.
List<MapEntry<String, int>> orderedExpenseCategories(Map<String, int> totals) {
  final ranks = <String, int>{};
  for (var index = 0; index < expenseCategoryOrder.length; index++) {
    final name = expenseCategoryOrder[index];
    ranks[name] = index;
    ranks[name.split(' > ').last] = index;
  }
  final entries = totals.entries.toList();
  entries.sort((a, b) {
    final rankA = ranks[a.key.trim()] ?? expenseCategoryOrder.length;
    final rankB = ranks[b.key.trim()] ?? expenseCategoryOrder.length;
    final order = rankA.compareTo(rankB);
    return order != 0 ? order : a.key.compareTo(b.key);
  });
  return entries;
}
