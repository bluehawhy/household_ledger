import 'package:flutter/material.dart';

/// 브라우저에서도 Google 프로필 사진을 표시한다.
class AccountAvatar extends StatelessWidget {
  final String? photoUrl;

  const AccountAvatar({super.key, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    const placeholder = Center(child: Icon(Icons.person, size: 40));
    return CircleAvatar(
      child: ClipOval(
        child: SizedBox.expand(
          child: url == null || url.isEmpty
              ? placeholder
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  // Google 이미지의 CORS 응답에 의존하지 않는 웹 표시 방식.
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (context, error, stackTrace) => placeholder,
                ),
        ),
      ),
    );
  }
}
