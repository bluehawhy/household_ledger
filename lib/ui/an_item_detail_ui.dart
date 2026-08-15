// an_item_detail_ui.dart


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

  late TextEditingController _descriptionController;
  late TextEditingController _amountController;
  late TextEditingController _payMethodController;
  late TextEditingController _categoryController;
  late TextEditingController _memoController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    _descriptionController = TextEditingController(text: widget.item.description ?? '');
    _amountController = TextEditingController(text: (widget.item.amount ?? 0).toInt().toString());
    _payMethodController = TextEditingController(text: widget.item.payMethod ?? '');
    _categoryController = TextEditingController(text: widget.item.category ?? '');
    _memoController = TextEditingController(text: widget.item.memo ?? '');

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
    _payMethodController.dispose();
    _categoryController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // 삭제 확인 다이얼로그
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
              Navigator.pop(ctx); // 다이얼로그 닫기
              Navigator.pop(context); // 상세 화면 닫고 이전 화면으로 복귀
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
    final Color themeColor = widget.isExpense ? Colors.redAccent : Colors.blueAccent;

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
                _initData(); // 입력 취소 시 초기 데이터 복원
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
        _buildDetailRow('분류', widget.item.category ?? '미지정'),
        const Divider(height: 32),
        _buildDetailRow('내용/설명', widget.item.description ?? '설명 없음'),
        const Divider(height: 32),
        _buildDetailRow('결제 수단', widget.item.payMethod ?? '-'),
        const Divider(height: 32),
        _buildDetailRow('메모', widget.item.memo ?? ''),
      ],
    );
  }

  // 상단 큰 금액 카드
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
            widget.isExpense ? '지출 금액' : '수입 금액',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 날짜 선택
        InkWell(
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
        const SizedBox(height: 16),
        TextField(
          controller: _categoryController,
          decoration: const InputDecoration(labelText: '분류 (카테고리)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: '설명', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '금액', suffixText: '원', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _payMethodController,
          decoration: const InputDecoration(labelText: '결제 수단 (예: 카드, 현금)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _memoController,
          decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
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
                'category': _categoryController.text,
                'description': _descriptionController.text,
                'amount': int.tryParse(_amountController.text) ?? 0,
                'payMethod': _payMethodController.text,
                'memo': _memoController.text,
              };

              await widget.onUpdate?.call(widget.item, updatedData);

              setState(() => _isEditing = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('수정이 완료되었습니다.')),
              );
              // 💡 수정 완료 후 상세 페이지 닫고 이전 화면(카테고리 목록)으로 복귀
              Navigator.of(context).pop(true);
            },
            child: const Text('저장하기', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
