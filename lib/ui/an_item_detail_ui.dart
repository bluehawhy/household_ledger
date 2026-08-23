import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AnItemDetailUI extends StatefulWidget {
  final dynamic item;
  final bool isExpense;

  // 데이터 변경 발생 시 상위로 알리기 위한 콜백
  final Function(dynamic item, Map<String, dynamic> updatedData)? onUpdate;
  final Function(dynamic item)? onDelete;

  const AnItemDetailUI({
    super.key,
    required this.item,
    required this.isExpense,
    this.onUpdate,
    this.onDelete,
  });

  @override
  State<AnItemDetailUI> createState() => _AnItemDetailUIState();
}

class _AnItemDetailUIState extends State<AnItemDetailUI> {
  final NumberFormat _currencyFormatter = NumberFormat('#,###');
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  bool _isEditing = false;

  // 상태 관리 변수
  late bool _isExpense;
  late String? _selectedPayMethod;
  late String? _selectedCategory;

  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late TextEditingController _memoController;
  late DateTime _selectedDate;

  // --- [JSON 기반 카테고리/거래수단 데이터] ---
  final List<String> _typeOptions = ['지출', '수입'];

  // 지출 수단
  final List<String> _expensePayMethods = [
    '현금',
    '신용카드',
    '체크카드',
    '페이/간편결제',
  ];

  // 수입 수단 (기본 옵션)
  final List<String> _incomePayMethods = [
    '현금/계좌이체',
    '신용카드',
    '체크카드',
    '페이/간편결제',
    '기타',
  ];

  // 지출 분류 목록
  final List<String> _expenseCategories = [
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

  // 수입 분류 목록
  final List<String> _incomeCategories = [
    '주수입',
    '부수입',
    '금융소득',
    '포인트/캐시백',
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    // item 객체의 type 필드가 존재하면 우선적으로 확인 (income/expense String 또는 bool)
    if (widget.item.type != null) {
      if (widget.item.type is String) {
        _isExpense = (widget.item.type as String).toLowerCase() == 'expense';
      } else if (widget.item.type is bool) {
        _isExpense = widget.item.type as bool;
      } else {
        _isExpense = widget.isExpense;
      }
    } else {
      _isExpense = widget.isExpense;
    }

    _descriptionController = TextEditingController(text: widget.item.description ?? '');
    _amountController = TextEditingController(text: (widget.item.amount ?? 0).toInt().toString());
    _memoController = TextEditingController(text: widget.item.memo ?? '');

    // 결제 수단 초기화
    final currentPayMethod = widget.item.payMethod ?? '';
    final validMethods = _isExpense ? _expensePayMethods : _incomePayMethods;
    _selectedPayMethod = validMethods.contains(currentPayMethod) ? currentPayMethod : null;

    // 카테고리 초기화
    final currentCategory = widget.item.category ?? '';
    final validCategories = _isExpense ? _expenseCategories : _incomeCategories;
    _selectedCategory = validCategories.contains(currentCategory) ? currentCategory : null;

    _selectedDate = () {
      if (widget.item.date is DateTime) return widget.item.date as DateTime;
      if (widget.item.date is String) return DateTime.tryParse(widget.item.date) ?? DateTime.now();
      return DateTime.now();
    }();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('내역 삭제'),
        content: const Text('정말 이 내역을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              widget.onDelete?.call(widget.item);
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('내역이 삭제되었습니다.')),
              );
            },
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = _isExpense ? Colors.redAccent : Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '내역 수정' : '상세 내역'),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _showDeleteConfirmDialog,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _initData();
                setState(() => _isEditing = false);
              },
            ),
          ]
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _isEditing ? _buildEditForm(themeColor) : _buildDetailView(themeColor),
      ),
    );
  }

  // --- [조회 화면] ---
  Widget _buildDetailView(Color themeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoCard(themeColor),
        const SizedBox(height: 24),
        _buildDetailRow('날짜', _dateFormatter.format(_selectedDate)),
        const Divider(height: 32),
        _buildDetailRow('거래 유형', _isExpense ? '지출' : '수입'),
        const Divider(height: 32),
        _buildDetailRow('분류', widget.item.category ?? '미지정'),
        const Divider(height: 32),
        _buildDetailRow('내용/설명', widget.item.description ?? '설명 없음'),
        const Divider(height: 32),
        _buildDetailRow('거래 수단', widget.item.payMethod ?? '-'),
        const Divider(height: 32),
        _buildDetailRow('메모', widget.item.memo ?? ''),
      ],
    );
  }

  Widget _buildInfoCard(Color themeColor) {
    final int amount = (widget.item.amount ?? 0).toInt();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isExpense ? '지출 금액' : '수입 금액',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Text(
            '${_currencyFormatter.format(amount)} 원',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: themeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // --- [수정 폼 화면] ---
  Widget _buildEditForm(Color themeColor) {
    final payMethodList = _isExpense ? _expensePayMethods : _incomePayMethods;
    final categoryList = _isExpense ? _expenseCategories : _incomeCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 날짜 선택 (Material로 감싸 터치 잉크 튐 예외 방지)
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '날짜',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(_dateFormatter.format(_selectedDate)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. 거래 유형 선택 (수입 / 지출)
        DropdownButtonFormField<String>(
          value: _isExpense ? '지출' : '수입',
          decoration: const InputDecoration(
            labelText: '거래 유형',
            border: OutlineInputBorder(),
          ),
          items: _typeOptions.map((type) {
            return DropdownMenuItem(value: type, child: Text(type));
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _isExpense = (val == '지출');
                _selectedPayMethod = null;
                _selectedCategory = null;
              });
            }
          },
        ),
        const SizedBox(height: 16),

        // 3. 거래 수단 선택
        DropdownButtonFormField<String>(
          value: payMethodList.contains(_selectedPayMethod) ? _selectedPayMethod : null,
          decoration: const InputDecoration(
            labelText: '거래 수단',
            border: OutlineInputBorder(),
          ),
          hint: const Text('거래 수단을 선택하세요'),
          items: payMethodList.map((method) {
            return DropdownMenuItem(value: method, child: Text(method));
          }).toList(),
          onChanged: (val) => setState(() => _selectedPayMethod = val),
        ),
        const SizedBox(height: 16),

        // 4. 분류 (카테고리) 선택
        DropdownButtonFormField<String>(
          value: categoryList.contains(_selectedCategory) ? _selectedCategory : null,
          decoration: const InputDecoration(
            labelText: '분류',
            border: OutlineInputBorder(),
          ),
          hint: const Text('분류를 선택하세요'),
          items: categoryList.map((cat) {
            return DropdownMenuItem(value: cat, child: Text(cat));
          }).toList(),
          onChanged: (val) => setState(() => _selectedCategory = val),
        ),
        const SizedBox(height: 16),

        // 5. 내용/설명 입력
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: '내용', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),

        // 6. 금액 입력
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '금액', suffixText: '원', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),

        // 7. 메모 입력
        TextField(
          controller: _memoController,
          decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),

        // 저장 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final updatedData = {
                'date': _selectedDate,
                'isExpense': _isExpense,
                // 모델 객체 업데이트를 위해 'type'과 'typeString' 모두 전달
                'type': _isExpense ? 'expense' : 'income',
                'typeString': _isExpense ? '지출' : '수입',
                'category': _selectedCategory ?? '미분류',
                'description': _descriptionController.text,
                'amount': int.tryParse(_amountController.text) ?? 0,
                'payMethod': _selectedPayMethod ?? '기타',
                'memo': _memoController.text,
              };

              await widget.onUpdate?.call(widget.item, updatedData);

              setState(() => _isEditing = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수정이 완료되었습니다.')),
                );
                Navigator.of(context).pop(true);
              }
            },
            child: const Text(
              '저장하기',
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}