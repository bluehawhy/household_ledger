import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'google_auth_stub.dart';

class DesktopGoogleAuthService implements GoogleAuthService {
  final List<String> scopes;
  final File _tokenFile = File('credentials.json');

  DesktopGoogleAuthService(this.scopes);

  /// 1. client_secret.json 로드
  Future<ClientId> _loadClientIdFromJson() async {
    final configFile = File('client_secret.json');

    if (!await configFile.exists()) {
      throw Exception("❌ 'client_secret.json' 파일을 찾을 수 없습니다!");
    }

    final jsonString = await configFile.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);

    // 최상위 키가 있든 없든 안전하게 client_id / client_secret 추출
    final String? clientId = data['client_id'] ?? data['installed']?['client_id'];
    final String? clientSecret = data['client_secret'] ?? data['installed']?['client_secret'];

    if (clientId == null || clientSecret == null) {
      throw Exception("❌ client_secret.json 파일 형식이 올바르지 않습니다.");
    }

    return ClientId(clientId, clientSecret);
  }

  /// 2. 인증 클라이언트 가져오기 (토큰 캐싱 & 자동 갱신 포함)
  @override
  Future<AuthClient> getAuthenticatedClient() async {
    final clientId = await _loadClientIdFromJson();

    // 저장된 토큰이 존재하는 경우
    if (await _tokenFile.exists()) {
      try {
        final jsonString = await _tokenFile.readAsString();
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

        final accessTokenMap = jsonMap['accessToken'] as Map<String, dynamic>?;
        if (accessTokenMap != null) {
          final tokenType = accessTokenMap['type'] as String? ?? 'Bearer';
          final data = accessTokenMap['data'] as String;
          final expiryStr = accessTokenMap['expiry'] as String;
          final expiry = DateTime.parse(expiryStr);

          final accessToken = AccessToken(tokenType, data, expiry);
          final refreshToken = jsonMap['refreshToken'] as String?;
          final idToken = jsonMap['idToken'] as String?;
          final savedScopes = (jsonMap['scopes'] as List<dynamic>?)?.cast<String>() ?? scopes;

          var credentials = AccessCredentials(
            accessToken,
            refreshToken,
            savedScopes,
            idToken: idToken,
          );

          final httpClient = http.Client();

          // 토큰 만료 시 자동 갱신
          if (credentials.accessToken.hasExpired) {
            if (refreshToken != null) {
              print("🔄 토큰이 만료되어 자동으로 갱신합니다...");
              credentials = await refreshCredentials(clientId, credentials, httpClient);
              await _tokenFile.writeAsString(jsonEncode(credentials.toJson()));
            } else {
              throw Exception("Refresh token이 없습니다.");
            }
          }

          print("🔑 캐시된 인증 토큰(credentials.json)을 사용하여 로그인을 완료했습니다!");
          return authenticatedClient(httpClient, credentials);
        }
      } catch (e) {
        print("⚠️ 저장된 토큰 처리 중 오류 발생 ($e). 브라우저 로그인을 재진행합니다.");
      }
    }

    // 최초 로그인 시 브라우저 호출
    print("\n🌐 최초 인증이 필요합니다. 브라우저를 열어 구글 로그인을 진행합니다...");
    final client = await clientViaUserConsent(
      clientId,
      scopes,
      (url) => _openBrowser(url),
    );

    // 새 토큰 파일로 저장
    final credentials = client.credentials;
    await _tokenFile.writeAsString(jsonEncode(credentials.toJson()));
    print("💾 새로운 인증 토큰이 '${_tokenFile.path}' 파일에 저장되었습니다!");

    return client;
  }

  /// 3. 운영체제별 브라우저 열기
  void _openBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    }
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) =>
    DesktopGoogleAuthService(scopes);