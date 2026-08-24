// lib/services/auth/google_auth_dart.dart

import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'google_auth_stub.dart';

class DesktopGoogleAuthService implements GoogleAuthService {
  @override
  final List<String> scopes;

  DesktopGoogleAuthService(this.scopes);

  final File _tokenFile = File('./data/credentials.json');

  /// 저장할 디렉터리가 없으면 자동 생성
  Future<void> _ensureDirectoryExists(File file) async {
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
  }

  @override
  Object? get currentUser => null;

  /// client_secret.json 읽기
  ///
  /// Pure Dart에서는 File로 직접 읽는다.
  Future<ClientId> _loadClientIdFromJson() async {
    final file = File('assets/client_secret.json');

    if (!await file.exists()) {
      throw Exception(
        "assets/client_secret.json 파일을 찾을 수 없습니다.\n"
        "현재 작업 폴더: ${Directory.current.path}",
      );
    }

    final jsonString = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);

    final clientId =
        data['client_id'] ?? data['installed']?['client_id'];

    final clientSecret =
        data['client_secret'] ?? data['installed']?['client_secret'];

    if (clientId == null || clientSecret == null) {
      throw Exception("client_secret.json 형식이 올바르지 않습니다.");
    }

    return ClientId(clientId, clientSecret);
  }


@override
  Future<AuthClient> getAuthenticatedClient() async {
    final clientId = await _loadClientIdFromJson();

    if (await _tokenFile.exists()) {
      try {
        final jsonMap = jsonDecode(await _tokenFile.readAsString())
            as Map<String, dynamic>;

        final accessTokenMap =
            jsonMap['accessToken'] as Map<String, dynamic>?;

        if (accessTokenMap != null) {
          var credentials = AccessCredentials(
            AccessToken(
              accessTokenMap['type'] ?? 'Bearer',
              accessTokenMap['data'],
              DateTime.parse(accessTokenMap['expiry']),
            ),
            jsonMap['refreshToken'],
            (jsonMap['scopes'] as List<dynamic>?)
                    ?.cast<String>() ??
                scopes,
            idToken: jsonMap['idToken'],
          );

          final httpClient = http.Client();

          if (credentials.accessToken.hasExpired) {
            if (credentials.refreshToken == null) {
              throw Exception("Refresh Token이 없습니다.");
            }

            print("🔄 AccessToken 갱신 중...");

            credentials = await refreshCredentials(
              clientId,
              credentials,
              httpClient,
            );

            // 디렉터리 존재 확인 후 저장
            await _ensureDirectoryExists(_tokenFile);
            await _tokenFile.writeAsString(
              jsonEncode(credentials.toJson()),
            );
          }

          print("✅ 저장된 인증 정보를 사용합니다.");

          return authenticatedClient(
            httpClient,
            credentials,
          );
        }
      } catch (e) {
        print("⚠ 기존 ./data/credentials.json 사용 실패");
        print(e);
      }
    }

    // 최초 로그인
    print("🌐 브라우저 인증을 시작합니다...");

    final client = await clientViaUserConsent(
      clientId,
      scopes,
      _openBrowser,
    );

    // 디렉터리 존재 확인 후 저장
    await _ensureDirectoryExists(_tokenFile);
    await _tokenFile.writeAsString(
      jsonEncode(client.credentials.toJson()),
    );

    print("💾 ./data/credentials.json 저장 완료");

    return client;
  }





  void _openBrowser(String url) {
    if (Platform.isWindows) {
      Process.run(
        'rundll32',
        ['url.dll,FileProtocolHandler', url],
      );
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    } else {
      print(url);
    }
  }
}

GoogleAuthService getGoogleAuthService(
  List<String> scopes,
) {
  return DesktopGoogleAuthService(scopes);
}