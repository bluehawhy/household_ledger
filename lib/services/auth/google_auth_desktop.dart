import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'google_auth_stub.dart';

class GoogleAuthServiceDesktop extends GoogleAuthService {
  GoogleAuthServiceDesktop(super.scopes);

  final File _secretFile = File('client_secret.json');
  final File _tokenFile = File('credentials.json');

  Future<ClientId> _loadClientId() async {
    var file = _secretFile;
    if (!await file.exists()) {
      file = File('lib/client_secret.json');
    }
    if (!await file.exists()) {
      throw Exception("'client_secret.json' 파일을 찾을 수 없습니다!");
    }

    final jsonString = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);
    final clientData = data['installed'] ?? data['web'] ?? data;
    return ClientId(clientData['client_id'], clientData['client_secret']);
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    final clientId = await _loadClientId();

    if (await _tokenFile.exists()) {
      try {
        final jsonString = await _tokenFile.readAsString();
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        final accessTokenMap = jsonMap['accessToken'] as Map<String, dynamic>?;

        if (accessTokenMap != null) {
          final tokenType = accessTokenMap['type'] as String? ?? 'Bearer';
          final data = accessTokenMap['data'] as String;
          final expiry = DateTime.parse(accessTokenMap['expiry'] as String);

          final accessToken = AccessToken(tokenType, data, expiry);
          final refreshToken = jsonMap['refreshToken'] as String?;
          final idToken = jsonMap['idToken'] as String?;

          var credentials = AccessCredentials(
            accessToken,
            refreshToken,
            scopes,
            idToken: idToken,
          );

          final httpClient = http.Client();

          if (credentials.accessToken.hasExpired) {
            if (refreshToken != null) {
              credentials = await refreshCredentials(
                clientId,
                credentials,
                httpClient,
              );
              await _tokenFile.writeAsString(jsonEncode(credentials.toJson()));
            } else {
              throw Exception("Refresh Token이 없어 재인증이 필요합니다.");
            }
          }
          return authenticatedClient(httpClient, credentials);
        }
      } catch (e) {
        print("💡 [Desktop] 토큰 복원 실패 -> 새로 로그인 진행합니다.");
      }
    }

    final client = await clientViaUserConsent(
      clientId,
      scopes,
      (url) => _openBrowser(url),
    );

    await _tokenFile.writeAsString(jsonEncode(client.credentials.toJson()));
    return client;
  }

  // url_launcher 대신 OS 기본 프로세스로 브라우저 호출
  Future<void> _openBrowser(String url) async {
    if (Platform.isWindows) {
      await Process.run('start', [url], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  }
}

// 팩토리 함수 연동
GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    GoogleAuthServiceDesktop(scopes);