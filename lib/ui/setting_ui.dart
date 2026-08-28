import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart';

class SettingUI extends StatefulWidget {
  final GoogleSignInAccount googleUser;
  final LedgerCacheManager cacheManager;
  final String currentSelectedEmail;
  final ValueChanged<String> onAccountChanged;

  const SettingUI({
    super.key,
    required this.googleUser,
    required this.cacheManager,
    required this.currentSelectedEmail,
    required this.onAccountChanged,
  });

  @override
  State<SettingUI> createState() => _SettingUIState();
}

class _SettingUIState extends State<SettingUI> {
  late String _selectedEmail;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _selectedEmail = widget.currentSelectedEmail;
  }

  /// 계정 선택 다이얼로그 표시
  void _showAccountSelectionDialog() {
    // LedgerCacheManager에 추가된 cachedAccountEmails getter 활용
    final List<String> availableEmails = widget.cacheManager.cachedAccountEmails;

    // 캐시된 계정이 내 계정 1개뿐이거나 없는 경우
    if (availableEmails.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('공유된 다른 가계부 계정이 없습니다.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 공유 계정이 존재하는 경우 선택 다이얼로그 표시
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('가계부 기준 계정 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableEmails.map((email) {
              final isMyAccount = (email == widget.googleUser.email);
              final isSelected = (email == _selectedEmail);

              return RadioListTile<String>(
                title: Text(
                  isMyAccount ? '$email (내 계정)' : '$email (공유 계정)',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Theme.of(context).primaryColor : null,
                  ),
                ),
                value: email,
                groupValue: _selectedEmail,
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() {
                      _selectedEmail = value;
                    });

                    // 콜백을 통해 부모 위젯에 상태 전달
                    widget.onAccountChanged(value);

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('기준 계정이 $value (으)로 변경되었습니다.')),
                    );
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  /// 로컬 캐시 데이터 초기화
  Future<void> _clearCache() async {
    setState(() {
      _isClearing = true;
    });

    try {
      await widget.cacheManager.clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로컬 캐시가 정상적으로 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('캐시 삭제 중 오류 발생: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMyAccountSelected = (_selectedEmail == widget.googleUser.email);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          // 구글 프로필 헤더
          UserAccountsDrawerHeader(
            accountName: Text(widget.googleUser.displayName ?? '사용자'),
            accountEmail: Text(widget.googleUser.email),
            currentAccountPicture: CircleAvatar(
              backgroundImage: widget.googleUser.photoUrl != null
                  ? NetworkImage(widget.googleUser.photoUrl!)
                  : null,
              child: widget.googleUser.photoUrl == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
          ),

          // 가계부 기준 계정 선택
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('가계부 기준 계정'),
            subtitle: Text(
              isMyAccountSelected
                  ? '$_selectedEmail (내 계정)'
                  : '$_selectedEmail (공유 계정)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAccountSelectionDialog,
          ),

          const Divider(),

          // 로컬 캐시 초기화
          ListTile(
            leading: const Icon(Icons.cleaning_services, color: Colors.orange),
            title: const Text('로컬 캐시 초기화'),
            subtitle: const Text('저장된 임시 데이터 및 캐시를 삭제합니다.'),
            trailing: _isClearing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('캐시 삭제'),
                  content: const Text('저장된 로컬 캐시 데이터를 모두 삭제하시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearCache();
                      },
                      child: const Text('삭제', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),

          const Divider(),

          // 기타 설정 항목
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('알림 설정'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 정보'),
            subtitle: const Text('버전 1.0.0'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}