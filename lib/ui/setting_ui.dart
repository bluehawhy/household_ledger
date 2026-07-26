import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SettingUI extends StatelessWidget {
  final GoogleSignInAccount googleUser;

  const SettingUI({super.key, required this.googleUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(googleUser.displayName ?? '사용자'),
            accountEmail: Text(googleUser.email),
            currentAccountPicture: CircleAvatar(
              backgroundImage: googleUser.photoUrl != null
                  ? NetworkImage(googleUser.photoUrl!)
                  : null,
              child: googleUser.photoUrl == null
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('계정 정보'),
            subtitle: Text(googleUser.email),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
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