import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

/// 웹 게시용 HTML을 그대로 읽되, 설정값은 JavaScript 실행 없이 적용합니다.
class PrivacyPolicyUI extends StatefulWidget {
  const PrivacyPolicyUI({super.key});

  @override
  State<PrivacyPolicyUI> createState() => _PrivacyPolicyUIState();
}

class _PrivacyPolicyUIState extends State<PrivacyPolicyUI> {
  final _scrollController = ScrollController();
  Future<String>? _policy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _policy ??= _loadPolicy();
  }

  Future<String> _loadPolicy() async {
    final bundle = DefaultAssetBundle.of(context);
    final source = await bundle.loadString('assets/privacy/privacy_policy.html');
    final document = html_parser.parse(source);
    final config = jsonDecode(
      await bundle.loadString('assets/privacy/privacy_policy_config.json'),
    ) as Map<String, dynamic>;
    for (final element in document.querySelectorAll('[data-policy]')) {
      final value = config[element.attributes['data-policy']];
      if (value is String && value.trim().isNotEmpty) {
        element.text = value.trim();
      }
    }
    final article = document.querySelector('article');
    if (article == null) {
      throw const FormatException('개인정보처리방침 본문이 없습니다.');
    }
    return article.outerHtml;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !{'https', 'mailto'}.contains(uri.scheme)) {
      return false;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } on PlatformException {
      // 외부 앱을 열지 못하면 현재 화면에서 안내합니다.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열지 못했습니다. 다시 시도해 주세요.')),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보처리방침')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _policy,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('개인정보처리방침을 불러오지 못했습니다.'),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _policy = _loadPolicy();
                        });
                      },
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: HtmlWidget(
                      snapshot.data!,
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 15, height: 1.7),
                      onTapUrl: _openLink,
                      customStylesBuilder: (element) => switch (element
                          .localName) {
                        'h1' => {'font-size': '24px', 'margin': '12px 0 24px'},
                        'h2' => {'font-size': '19px', 'margin': '32px 0 12px'},
                        'table' => {'border-collapse': 'collapse'},
                        'th' => {
                          'background-color': '#f8eeec',
                          'border': '1px solid #ded8d6',
                          'padding': '10px',
                          'min-width': '100px',
                        },
                        'td' => {
                          'border': '1px solid #ded8d6',
                          'padding': '10px',
                          'min-width': '100px',
                        },
                        _ => null,
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
