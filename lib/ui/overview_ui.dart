import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:intl/intl.dart'; // 💡 원화 포맷팅을 위해 추가

// 서비스 클래스 임포트
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/spread_sheet/google_spreadsheet.dart';

import 'ledger_ingestion_ui.dart';
import 'setting_ui.dart';

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

  // 서비스 객체
  final GoogleAuthManager _authManager = GoogleAuthManager();
  final HouseholdSheetService _sheetService = HouseholdSheetService();

  // 통화 포맷터 (예: 1,000,000)
  final NumberFormat _currencyFormatter = NumberFormat('#,###');

  // 데이터 상태 변수
  bool _isLoading = true;
  String? _errorMessage;

  int _totalExpense = 0;
  Map<String, int> _expenseCategories = {};
  Map<String, int> _expenseMethods = {};

  int _totalIncome = 0;
  Map<String, int> _incomeCategories = {};

  @override
  void initState() {
    super.initState();
    _loadMonthlyData();
  }

  @override
  void dispose() {
    _pageController.dispose(); // 💡 메모리 누수 방지 컨트롤러 해제
    super.dispose();
  }

  /// 구글 시트에서 이번 달 데이터 불러오기 및 가공
  Future<void> _loadMonthlyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final targetYear = now.year;
      final targetMonth = now.month;

      // 1. Google OAuth 인증 클라이언트 획득 (MainUI와 동일한 세션 공유)
      final AuthClient client = await _authManager.getClient();

      // 2. 이번 달 수입 / 지출 내역 병렬 조회
      final results = await Future.wait([
        _sheetService.getMonthlyExpenses(
          client: client,
          year: targetYear,
          month: targetMonth,
        ),
        _sheetService.getMonthlyIncomes(
          client: client,
          year: targetYear,
          month: targetMonth,
        ),
      ]);

      final expenses = results[0];
      final incomes = results[1];

      // 3. 지출 데이터 집계
      int totalExp = 0;
      final Map<String, int> expCatMap = {};
      final Map<String, int> expMethodMap = {};

      for (final item in expenses) {
        final int amount = (item.amount ?? 0).toInt();
        totalExp += amount;

        final String category = (item.category != null && item.category!.isNotEmpty)
            ? item.category!
            : '미분류';
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
        final int amount = (item.amount ?? 0).toInt();
        totalInc += amount;

        final String category = (item.category != null && item.category!.isNotEmpty)
            ? item.category!
            : '미분류';
        incCatMap[category] = (incCatMap[category] ?? 0) + amount;
      }

      // 5. 상태 업데이트
      if (mounted) {
        setState(() {
          _totalExpense = totalExp;
          _expenseCategories = expCatMap;
          _expenseMethods = expMethodMap;

          _totalIncome = totalInc;
          _incomeCategories = incCatMap;

          _isLoading = false;
        });
      }
    } catch (e) {
      print("데이터 조회 에러: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "인증 세션이 만료되었거나 데이터를 불러올 수 없습니다.\n다시 로그인해 주세요.";
          _isLoading = false;
        });
      }
    }
  }




  // 내역 입력 화면 이동 (입력 후 돌아오면 자동 새로고침)
  Future<void> _navigateToIngestion() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LedgerIngestionUI(
          googleUser: widget.googleUser,
        ),
      ),
    );
    // 내역 입력 화면에서 돌아온 후 데이터 다시 로드
    _loadMonthlyData();
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingUI(
          googleUser: widget.googleUser,
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
                      // 인사말 영역
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

                      // 지출 / 수입 상단 인디케이터 탭
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTabButton('지출', 0),
                          const SizedBox(width: 16),
                          _buildTabButton('수입', 1),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // 좌우 스와이프 영역 (PageView)
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentPage = index;
                            });
                          },
                          children: [
                            // 1페이지: 지출 화면
                            _buildOverviewSection(
                              title: '이번달 지출',
                              totalAmount: _totalExpense,
                              categoryData: _expenseCategories,
                              methodData: _expenseMethods,
                              colorScheme: Colors.redAccent,
                            ),
                            // 2페이지: 수입 화면
                            _buildOverviewSection(
                              title: '이번달 수입',
                              totalAmount: _totalIncome,
                              categoryData: _incomeCategories,
                              methodData: null,
                              colorScheme: Colors.blueAccent,
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

  // 상단 탭 버튼 생성
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

  // 지출/수입 세부 구성 템플릿
  Widget _buildOverviewSection({
    required String title,
    required int totalAmount,
    required Map<String, int> categoryData,
    Map<String, int>? methodData,
    required Color colorScheme,
  }) {
    final bool hasCategoryData = categoryData.isNotEmpty;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // RefreshIndicator 작동용
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 파이 차트 Card
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

          // 2. 총 금액 표시
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

          // 3. 분류별 내역
          const Text(
            '분류별 상세',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (hasCategoryData)
            ...categoryData.entries.map((entry) {
              return _buildDetailTile(entry.key, entry.value);
            })
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('등록된 분류별 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
            ),

          // 4. 지출/수입 수단별 표시
          if (methodData != null) ...[
            const SizedBox(height: 20),
            const Text(
              '결제 수단별',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (methodData.isNotEmpty)
              ...methodData.entries.map((entry) {
                return _buildDetailTile(entry.key, entry.value);
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

  // 상세 ListTile 생성
  Widget _buildDetailTile(String name, int amount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        dense: true,
        title: Text(name, style: const TextStyle(fontSize: 15)),
        trailing: Text(
          '${_currencyFormatter.format(amount)} 원',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // 파이 차트 생성 함수 (fl_chart)
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