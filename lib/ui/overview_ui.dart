//overview_ui.dart
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:intl/intl.dart';

// 서비스 및 UI 클래스 임포트
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart'; // 💡 캐시 매니저 임포트 추가
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_transaction_service.dart';

import 'package:household_ledger/ui/ledger_ingestion_ui.dart';
import 'package:household_ledger/ui/setting_ui.dart';
import 'package:household_ledger/ui/category_detail_ui.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


class OverviewPage extends StatefulWidget {
  final GoogleSignInAccount googleUser;

  const OverviewPage({super.key, required this.googleUser});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  // PageView 제어를 위한 컨트롤러 및 현재 페이지 인덱스
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 서비스 및 캐시 객체
  final GoogleAuthManager _authManager = GoogleAuthManager();
  final HouseholdSheetService _sheetService = HouseholdSheetService();
  final LedgerCacheManager _cacheManager = LedgerCacheManager(); // 💡 캐시 매니저 선언

  // 현재 기준 계정 이메일 (기본값: 로그인된 구글 계정 이메일)
  late String _currentSelectedEmail;

  // 통화 포맷터
  final NumberFormat _currencyFormatter = NumberFormat('#,###');

  // 데이터 상태 변수
  bool _isLoading = true;
  String? _errorMessage;

  // 원본 아이템 리스트 저장용 변수
  List<LedgerItem> _rawExpenses = [];
  List<LedgerItem> _rawIncomes = [];

  int _totalExpense = 0;
  Map<String, int> _expenseCategories = {};
  Map<String, int> _expenseMethods = {};

  int _totalIncome = 0;
  Map<String, int> _incomeCategories = {};

  @override
  void initState() {
    super.initState();
    _currentSelectedEmail = widget.googleUser.email; // 💡 기본 계정으로 초기화
    _loadMonthlyData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 구글 시트에서 이번 달 통합 데이터 불러오기 및 가공
  Future<void> _loadMonthlyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final targetYear = now.year;
      final targetMonth = now.month;

      final AuthClient client = await _authManager.getClient();

      // 1. 통합 시트 데이터 1회 불러오기
      final List<LedgerItem> totalItems = await _sheetService.getMonthlyLedger(
        client: client,
        year: targetYear,
        month: targetMonth,
      );

      // 2. TransactionType에 따라 지출 / 수입 리스트로 분리
      final List<LedgerItem> expenses = [];
      final List<LedgerItem> incomes = [];

      for (final item in totalItems) {
        if (item.type == TransactionType.expense) {
          expenses.add(item);
        } else if (item.type == TransactionType.income) {
          incomes.add(item);
        }
      }

      // 3. 지출 데이터 집계
      int totalExp = 0;
      final Map<String, int> expCatMap = {};
      final Map<String, int> expMethodMap = {};

      for (final item in expenses) {
        final int amount = item.amount;
        totalExp += amount;

        final String category = item.category.isNotEmpty ? item.category : '미분류';
        expCatMap[category] = (expCatMap[category] ?? 0) + amount;

        if (item.payMethod != null && item.payMethod!.isNotEmpty) {
          final String method = item.payMethod!;
          expMethodMap[method] = (expMethodMap[method] ?? 0) + amount;
        }
      }

      // 4. 수입 데이터 집계
      int totalInc = 0;
      final Map<String, int> incCatMap = {};

      for (final item in incomes) {
        final int amount = item.amount;
        totalInc += amount;

        final String category = item.category.isNotEmpty ? item.category : '미분류';
        incCatMap[category] = (incCatMap[category] ?? 0) + amount;
      }

      // 5. 기존 상태 변수(setState)에 반영
      if (mounted) {
        setState(() {
          _rawExpenses = expenses;
          _rawIncomes = incomes;

          _totalExpense = totalExp;
          _expenseCategories = expCatMap;
          _expenseMethods = expMethodMap;

          _totalIncome = totalInc;
          _incomeCategories = incCatMap;

          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.i("데이터 조회 에러: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "인증 세션이 만료되었거나 데이터를 불러올 수 없습니다.\n다시 로그인해 주세요.";
          _isLoading = false;
        });
      }
    }
  }

  // 선택한 카테고리 상세 페이지로 이동
  Future<void> _navigateToCategoryDetail({
    required String categoryName,
    required bool isExpense,
    bool isPayMethod = false,
  }) async {
    List<LedgerItem> filteredItems = [];

    if (isExpense) {
      if (isPayMethod) {
        filteredItems = _rawExpenses.where((item) {
          return (item.payMethod ?? '') == categoryName;
        }).toList();
      } else {
        filteredItems = _rawExpenses.where((item) {
          final cat = (item.category != null && item.category!.isNotEmpty)
              ? item.category!
              : '미분류';
          return cat == categoryName;
        }).toList();
      }
    } else {
      filteredItems = _rawIncomes.where((item) {
        final cat = (item.category != null && item.category!.isNotEmpty)
            ? item.category!
            : '미분류';
        return cat == categoryName;
      }).toList();
    }

    final AuthClient client = await _authManager.getClient();

    final bool? dataChanged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CategoryDetailUI(
          categoryName: categoryName,
          items: filteredItems,
          isExpense: isExpense,
          client: client,
        ),
      ),
    );
    if (dataChanged == true) _loadMonthlyData();
  }

  Future<void> _navigateToIngestion() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LedgerIngestionUI(
          googleUser: widget.googleUser,
        ),
      ),
    );
    _loadMonthlyData();
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingUI(
          googleUser: widget.googleUser,
          cacheManager: _cacheManager, // 💡 선언된 cacheManager 전달
          currentSelectedEmail: _currentSelectedEmail, // 💡 선언된 currentSelectedEmail 전달
          onAccountChanged: (newEmail) {
            setState(() {
              _currentSelectedEmail = newEmail;
            });
            // 기준 계정이 바뀌었으므로 데이터 재로드
            _loadMonthlyData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text('우리 가계부 (${now.year}년 ${now.month}월)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _loadMonthlyData,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('이번 달 가계부 내역을 불러오는 중...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadMonthlyData,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMonthlyData,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '안녕하세요, ${widget.googleUser.displayName ?? "사용자"}님!',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTabButton('지출', 0),
                          const SizedBox(width: 16),
                          _buildTabButton('수입', 1),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          children: [
                            _buildOverviewSection(
                              title: '이번달 지출',
                              totalAmount: _totalExpense,
                              categoryData: _expenseCategories,
                              methodData: _expenseMethods,
                              colorScheme: Colors.redAccent,
                              isExpense: true,
                            ),
                            _buildOverviewSection(
                              title: '이번달 수입',
                              totalAmount: _totalIncome,
                              categoryData: _incomeCategories,
                              methodData: null,
                              colorScheme: Colors.blueAccent,
                              isExpense: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToIngestion,
        tooltip: '내역 추가',
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildTabButton(String title, int pageIndex) {
    final isSelected = _currentPage == pageIndex;
    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          pageIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewSection({
    required String title,
    required int totalAmount,
    required Map<String, int> categoryData,
    Map<String, int>? methodData,
    required Color colorScheme,
    required bool isExpense,
  }) {
    final bool hasCategoryData = categoryData.isNotEmpty;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    '$title 차트',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: hasCategoryData
                        ? _buildPieChart(categoryData, colorScheme)
                        : const Center(
                            child: Text(
                              '내역이 없습니다.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: colorScheme.withOpacity(0.1),
            elevation: 0,
            child: ListTile(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(
                '${_currencyFormatter.format(totalAmount)} 원',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '분류별 상세 (클릭시 세부 내역 이동)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (hasCategoryData)
            ...categoryData.entries.map((entry) {
              return _buildDetailTile(
                name: entry.key,
                amount: entry.value,
                onTap: () => _navigateToCategoryDetail(
                  categoryName: entry.key,
                  isExpense: isExpense,
                ),
              );
            })
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('등록된 분류별 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
            ),
          if (methodData != null) ...[
            const SizedBox(height: 20),
            const Text(
              '결제 수단별',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (methodData.isNotEmpty)
              ...methodData.entries.map((entry) {
                return _buildDetailTile(
                  name: entry.key,
                  amount: entry.value,
                  onTap: () => _navigateToCategoryDetail(
                    categoryName: entry.key,
                    isExpense: true,
                    isPayMethod: true,
                  ),
                );
              })
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('등록된 결제 수단 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required String name,
    required int amount,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(name, style: const TextStyle(fontSize: 15)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_currencyFormatter.format(amount)} 원',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, int> data, Color baseColor) {
    final total = data.values.fold(0, (sum, item) => sum + item);
    if (total == 0) return const Center(child: Text('금액이 0원입니다.'));

    final colors = [
      baseColor,
      baseColor.withOpacity(0.7),
      baseColor.withOpacity(0.5),
      baseColor.withOpacity(0.3),
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.teal,
      Colors.grey,
    ];

    int index = 0;
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: data.entries.map((entry) {
          final double percentage = (entry.value / total) * 100;
          final color = colors[index % colors.length];
          index++;

          return PieChartSectionData(
            color: color,
            value: entry.value.toDouble(),
            title: '${percentage.toStringAsFixed(0)}%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
      ),
    );
  }
}