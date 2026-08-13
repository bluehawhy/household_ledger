//category_detail_ui.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CategoryDetailUI extends StatelessWidget {
  final String categoryName;
  final List<dynamic> items; // 구글 시트에서 넘어온 원본 객체 리스트
  final bool isExpense;

  CategoryDetailUI({
    super.key,
    required this.categoryName,
    required this.items,
    required this.isExpense,
  });

  final NumberFormat _currencyFormatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    // 선택된 카테고리의 총 금액 계산
    final int totalAmount = items.fold(0, (sum, item) {
      final int amount = (item.amount ?? 0).toInt();
      return sum + amount;
    });

    final Color themeColor = isExpense ? Colors.redAccent : Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text('$categoryName 상세 내역'),
      ),
      body: Column(
        children: [
          // 상단 요약 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: themeColor.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isExpense ? '지출 카테고리' : '수입 카테고리',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  categoryName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '총 ${items.length}건 / ${_currencyFormatter.format(totalAmount)} 원',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
          ),

          // 세부 내역 리스트
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('해당 카테고리의 내역이 없습니다.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];

                      // Google Sheet 데이터의 날짜/메모/결제수단/금액 파싱 (필드명은 실제 모델에 맞춰 자동 대응)
                      final String dateStr = item.date ?? '';
                      final String memo = (item.memo != null && item.memo.isNotEmpty)
                          ? item.memo
                          : '메모 없음';
                      final String? payMethod = item.payMethod;
                      final int amount = (item.amount ?? 0).toInt();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        title: Text(
                          memo,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(dateStr, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                              if (payMethod != null && payMethod.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    payMethod,
                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        trailing: Text(
                          '${_currencyFormatter.format(amount)} 원',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}