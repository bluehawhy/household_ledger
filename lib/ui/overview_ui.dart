import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:fl_chart/fl_chart.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';

// 서비스 및 UI 클래스 임포트
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/google_drive/google_drive_ledger_settings.dart';
import 'package:household_ledger/ui/theme/app_theme.dart';
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
  static const double overviewWideBreakpoint = 850;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final GoogleAuthManager _authManager = GoogleAuthManager();
  final HouseholdSheetService _sheetService = HouseholdSheetService();

  late String _currentSelectedEmail;
  final NumberFormat _currencyFormatter = NumberFormat('#,###');

  // [추가] 현재 선택된 연/월 상태 관리
  late int _selectedYear;
  late int _selectedMonth;

  bool _isLoading = true;
  String? _errorMessage;
  bool _hasRestoredSelectedAccount = false;

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
    _currentSelectedEmail = widget.googleUser.email;

    // 초기값으로 현재 연/월 설정
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;

    _loadMonthlyData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 이전 달로 이동
  void _previousMonth() {
    setState(() {
      if (_selectedMonth == 1) {
        _selectedYear--;
        _selectedMonth = 12;
      } else {
        _selectedMonth--;
      }
    });
    _loadMonthlyData();
  }

  /// 다음 달로 이동
  void _nextMonth() {
    setState(() {
      if (_selectedMonth == 12) {
        _selectedYear++;
        _selectedMonth = 1;
      } else {
        _selectedMonth++;
      }
    });
    _loadMonthlyData();
  }

  Future<void> _selectYearMonth() async {
    const firstYear = 2020;
    const lastYear = 2035;

    int tempYear = _selectedYear;
    int tempMonth = _selectedMonth;

    final yearController = FixedExtentScrollController(
      initialItem: _selectedYear - firstYear,
    );
    final monthController = FixedExtentScrollController(
      initialItem: _selectedMonth - 1,
    );

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Text(
                      '$tempYear년 $tempMonth월',
                      style: const TextStyle(
                        color: Color(0xFFFF6F6A),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 170,
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: yearController,
                              itemExtent: 40,
                              selectionOverlay: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onSelectedItemChanged: (index) {
                                setModalState(() {
                                  tempYear = firstYear + index;
                                });
                              },
                              children: List.generate(
                                lastYear - firstYear + 1,
                                (index) => Center(
                                  child: Text('${firstYear + index}년'),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: monthController,
                              itemExtent: 40,
                              selectionOverlay: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onSelectedItemChanged: (index) {
                                setModalState(() {
                                  tempMonth = index + 1;
                                });
                              },
                              children: List.generate(
                                12,
                                (index) => Center(
                                  child: Text('${index + 1}월'),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8179),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(bottomSheetContext);

                          if (tempYear != _selectedYear ||
                              tempMonth != _selectedMonth) {
                            setState(() {
                              _selectedYear = tempYear;
                              _selectedMonth = tempMonth;
                            });
                            _loadMonthlyData();
                          }
                        },
                        child: Text(
                          '$tempYear년 $tempMonth월 선택',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    yearController.dispose();
    monthController.dispose();
  }


  /// 선택된 연도와 월의 가계부 데이터를 구글 시트에서 불러온다.
  Future<void> _loadMonthlyData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final AuthClient client = await _authManager.getClient();
      await _restoreSelectedAccount(client);

      // 선택된 _selectedYear와 _selectedMonth 전달
      final List<LedgerItem> totalItems = await _sheetService.getMonthlyLedger(
        client: client,
        year: _selectedYear,
        month: _selectedMonth,
        accountEmail: _currentSelectedEmail,
      );

      final List<LedgerItem> expenses = [];
      final List<LedgerItem> incomes = [];

      for (final item in totalItems) {
        if (item.type == TransactionType.expense) {
          expenses.add(item);
        } else if (item.type == TransactionType.income) {
          incomes.add(item);
        }
      }

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

      int totalInc = 0;
      final Map<String, int> incCatMap = {};

      for (final item in incomes) {
        final int amount = item.amount;
        totalInc += amount;

        final String category = item.category.isNotEmpty ? item.category : '미분류';
        incCatMap[category] = (incCatMap[category] ?? 0) + amount;
      }

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
    } catch (e, stackTrace) {
      AppLogger.i('데이터 조회 에러: $e');
      AppLogger.i('데이터 조회 StackTrace: $stackTrace');

      if (mounted) {
        setState(() {
          _errorMessage = '가계부 데이터를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restoreSelectedAccount(AuthClient client) async {
    if (_hasRestoredSelectedAccount) return;

    await _sheetService.init(client);
    final cacheManager = _sheetService.sheetSetupService.cacheManager;
    final ownerEmail = widget.googleUser.email;
    final ownerFolderId = cacheManager.getFoldersByAccount(ownerEmail)?['가계부'];
    if (ownerFolderId == null) return;

    final settingsService = DriveLedgerSettingsService(drive.DriveApi(client));
    LedgerDriveSettings? savedSettings;
    try {
      savedSettings = await settingsService.load(ownerFolderId: ownerFolderId);
    } catch (e) {
      AppLogger.i('⚠️ 저장된 가계부 기준 계정 설정을 읽지 못했습니다: $e');
    }
    final selectedFolderId = savedSettings == null
        ? null
        : cacheManager
            .getFoldersByAccount(savedSettings.accountEmail)?['가계부'];

    if (savedSettings != null && selectedFolderId == savedSettings.folderId) {
      _currentSelectedEmail = savedSettings.accountEmail;
    } else {
      _currentSelectedEmail = ownerEmail;
      try {
        await settingsService.save(
          ownerFolderId: ownerFolderId,
          settings: LedgerDriveSettings(
            accountEmail: ownerEmail,
            folderId: ownerFolderId,
          ),
        );
      } catch (e) {
        AppLogger.i('⚠️ 기본 가계부 기준 계정 설정을 저장하지 못했습니다: $e');
      }
    }

    _hasRestoredSelectedAccount = true;
  }

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
          accountEmail: _currentSelectedEmail,
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
          accountEmail: _currentSelectedEmail,
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
          cacheManager: _sheetService.sheetSetupService.cacheManager,
          currentSelectedEmail: _currentSelectedEmail,
          onAccountChanged: (newEmail) {
            setState(() {
              _currentSelectedEmail = newEmail;
            });
            _loadMonthlyData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 상단 타이틀을 클릭 가능한 연/월 선택 위젯으로 변경
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '이전 달',
              onPressed: _previousMonth,
            ),
            InkWell(
              onTap: _selectYearMonth,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '$_selectedYear년 $_selectedMonth월',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '다음 달',
              onPressed: _nextMonth,
            ),
          ],
        ),
        centerTitle: true,
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
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('$_selectedYear년 $_selectedMonth월 가계부 내역을 불러오는 중...'),
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
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                        ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool showBoth =
                          constraints.maxWidth >= overviewWideBreakpoint;

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '안녕하세요, ${widget.googleUser.displayName ?? "사용자"}님!',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '기준 계정: $_currentSelectedEmail',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          if (!showBoth) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildTabButton('지출', 0),
                                const SizedBox(width: 16),
                                _buildTabButton('수입', 1),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],

                          Expanded(
                            child: showBoth
                                ? _buildWideOverview()
                                : _buildCompactOverview(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToIngestion,
        tooltip: '내역 추가',
        child: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildCompactOverview() {
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
      children: [
        _buildOverviewSection(
          title: '$_selectedMonth월 지출',
          totalAmount: _totalExpense,
          categoryData: _expenseCategories,
          methodData: _expenseMethods,
          colorScheme: AppTheme.accent,
          isExpense: true,
        ),
        _buildOverviewSection(
          title: '$_selectedMonth월 수입',
          totalAmount: _totalIncome,
          categoryData: _incomeCategories,
          methodData: null,
          colorScheme: const Color(0xFF6C9EEB),
          isExpense: false,
        ),
      ],
    );
  }

  Widget _buildWideOverview() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildOverviewSection(
            title: '$_selectedMonth월 지출',
            totalAmount: _totalExpense,
            categoryData: _expenseCategories,
            methodData: _expenseMethods,
            colorScheme: AppTheme.accent,
            isExpense: true,
          ),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
        ),
        Expanded(
          child: _buildOverviewSection(
            title: '$_selectedMonth월 수입',
            totalAmount: _totalIncome,
            categoryData: _incomeCategories,
            methodData: null,
            colorScheme: const Color(0xFF6C9EEB),
            isExpense: false,
          ),
        ),
      ],
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
          color: isSelected ? AppTheme.primary : const Color(0xFFF4EEEC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF625C5A),
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
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    '$title 차트',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D2928),
                    ),
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
            color: colorScheme.withValues(alpha: 0.10),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D2928),
                ),
              ),
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
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D2928),
            ),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D2928),
              ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECE5E2)),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(
          name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D2928),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_currencyFormatter.format(amount)} 원',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB8AEAB)),
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
