import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'ledger_ingestion_ui.dart'; // 같은 폴더(lib/ui)에 있는 경우
import 'setting_ui.dart';          // 설정 화면 import 추가

class OverviewPage extends StatefulWidget {
  final GoogleSignInAccount googleUser;

  const OverviewPage({super.key, required this.googleUser});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  // 내역 입력 화면으로 이동하는 함수 (구글 계정 정보 전달)
  void _navigateToIngestion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LedgerIngestionUI(
          googleUser: widget.googleUser, // 계정 정보만 전달
        ),
      ),
    );
  }

  // 설정 화면으로 이동하는 함수
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('우리 가계부 Overview'),
        actions: [
          // 1. AppBar 우측 상단 설정 아이콘
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '안녕하세요, ${widget.googleUser.displayName ?? "사용자"}님!',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Card(
              child: ListTile(
                title: Text('이번 달 총 지출'),
                subtitle: Text('₩ 0'),
              ),
            ),
          ],
        ),
      ),
      // 2. 우측 하단 플로팅 버튼 (메인 입력 버튼)
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToIngestion,
        tooltip: '내역 추가',
        child: const Icon(Icons.edit),
      ),
    );
  }
}