import 'package:flutter/material.dart';

/// 광고를 사용할 수 없는 플랫폼 또는 광고 ID 미설정 상태의 공통 영역입니다.
class AppBannerAd extends StatelessWidget {
  const AppBannerAd({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '광고 배너입니다. 아직 준비중',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}
