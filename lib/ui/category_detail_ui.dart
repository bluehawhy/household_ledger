import 'package:flutter/material.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:intl/intl.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/ui/an_item_detail_ui.dart';

class CategoryDetailUI extends StatefulWidget {
  final String categoryName;
  final List<LedgerItem> items; // 💡 LedgerItem 객체 리스트로 타입 명시
  final bool isExpense;
  final AuthClient client;

  const CategoryDetailUI({
    super.key,
    required this.categoryName,
    required this.items,
    required this.isExpense,
    required this.client,
  });

  @override
  State<CategoryDetailUI> createState() => _CategoryDetailUIState();
}

class _CategoryDetailUIState extends State<CategoryDetailUI> {
  final NumberFormat _currencyFormatter = NumberFormat('#,###');

  @override
  Widget build(BuildContext context) {
    // 선택된 카테고리의 총 금액 계산
    final int totalAmount = items.fold(0, (sum, item) {
      final int amount = (item.amount ?? 0).toInt();
      return sum + (amount.isNegative ? -amount : amount);
    });

    final Color themeColor = widget.isExpense ? Colors.redAccent : Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.categoryName} 상세 내역'),
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
                  widget.isExpense ? '지출 카테고리' : '수입 카테고리',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.categoryName,
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
            child: widget.items.isEmpty
                ? const Center(
                    child: Text('해당 카테고리의 내역이 없습니다.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.items.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];

                      // Google Sheet 데이터의 날짜/메모/결제수단/금액 파싱
                      final DateFormat dateFormatter = DateFormat('yyyy-MM-dd');
                      
                      final String dateStr = () {
                        if (item.date == null) return '';
                        if (item.date is DateTime) {
                          return dateFormatter.format(item.date); // DateTime 타입인 경우 포맷팅
                        }
                        return item.date.toString(); // 이미 String이거나 다른 타입인 경우
                      }();
                      
                      final String description = (item.description != null && item.description.isNotEmpty)
                          ? item.description
                          : '설명 없음';
                      final String? payMethod = item.payMethod;
                      final int amount = (item.amount ?? 0).toInt();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        
                        // 클릭 시 AnItemDetailUI 화면으로 이동
                        onTap: () async {
                          final bool? dataChanged = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AnItemDetailUI(
                                item: item,
                                isExpense: widget.isExpense,
                                onUpdate: (oldItem, updatedData) async { // 💡 oldItem의 타입이 LedgerItem으로 추론됨
                                  final service = LedgerDataService();
                                  final newItem = (oldItem as LedgerItem).copyWith(
                                    date: updatedData['date'],
                                    category: updatedData['category'],
                                    description: updatedData['description'],
                                    amount: updatedData['amount'],
                                    payMethod: updatedData['payMethod'],
                                    memo: updatedData['memo'],
                                  );
                                  await service.updateTransaction(
                                    client: widget.client,
                                    oldItem: oldItem,
                                    newItem: newItem,
                                  );
                                },
                                onDelete: (item) {
                                  // TODO: 삭제 시 구글 시트 반영 또는 State 갱신 로직
                                },
                              ),
                            ),
                          );
                          // 💡 상세 페이지에서 데이터 변경이 있었다면, 현재 화면도 닫고 Overview에 알림
                          if (dataChanged == true && mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                        
                        title: Text(
                          description,
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

extension on _CategoryDetailUIState {
  List<LedgerItem> get items => widget.items;
}