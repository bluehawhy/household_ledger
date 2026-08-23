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

  // 우분투 서버 전용 저장 경로
  final File _tokenFile = File('.data/credentials.json');

  // 사용자 프로필 및 토큰 상태를 담을 객체
  AccessCredentials? _credentials;

  @override
  Object? get currentUser {
    // credentials가 존재하면 null이 아닌 유저 정보(IdToken 기반 또는 더미 인증 객체)를 반환
    if (_credentials != null) {
      return _credentials?.idToken ?? 'authenticated_user';
    }
    return null;
  }

  /// client_secret.json 읽기
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

    final Map<String, dynamic> config =
        data['installed'] ?? data['web'] ?? data;

    final clientId = config['client_id'];
    final clientSecret = config['client_secret'];

    if (clientId == null || clientSecret == null) {
      throw Exception("client_secret.json 형식이 올바르지 않습니다.");
    }

    return ClientId(clientId, clientSecret);
  }

  /// AccessCredentials -> Map 변환
  Map<String, dynamic> _credentialsToJson(AccessCredentials credentials) {
    return {
      'accessToken': {
        'type': credentials.accessToken.type,
        'data': credentials.accessToken.data,
        'expiry': credentials.accessToken.expiry.toIso8601String(),
      },
      'refreshToken': credentials.refreshToken,
      'scopes': credentials.scopes,
      'idToken': credentials.idToken,
    };
  }

  /// .data 디렉터리가 없을 경우 자동 생성 및 저장
  Future<void> _saveTokenFile(AccessCredentials credentials) async {
    final directory = Directory('.data');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    await _tokenFile.writeAsString(
      jsonEncode(_credentialsToJson(credentials)),
    );
  }

  @override
  Future<AuthClient> getAuthenticatedClient() async {
    final clientId = await _loadClientIdFromJson();

    // 1. .data/credentials.json 파일이 존재하면 읽어서 인증 재사용
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
            (jsonMap['scopes'] as List<dynamic>?)?.cast<String>() ?? scopes,
            idToken: jsonMap['idToken'],
          );

          final httpClient = http.Client();

          // AccessToken 만료 시 Refresh Token으로 자동 갱신 후 파일 재저장
          if (credentials.accessToken.hasExpired) {
            if (credentials.refreshToken == null) {
              throw Exception("Refresh Token이 없습니다.");
            }

            print("🔄 AccessToken 만료됨. 서버에서 자동 갱신 중...");

            credentials = await refreshCredentials(
              clientId,
              credentials,
              httpClient,
            );

            await _saveTokenFile(credentials);
            print("💾 갱신된 .data/credentials.json 저장 완료");
          }

          _credentials = credentials; // currentUser용 내부 상태 업데이트
          print("✅ 저장된 .data/credentials.json 인증 정보를 사용합니다.");

          return autoRefreshingClient(
            clientId,
            credentials,
            httpClient,
          );
        }
      } catch (e) {
        print("⚠ 기존 .data/credentials.json 사용 실패 (새로 로그인 시도): $e");
      }
    }

    // 2. 파일이 없거나 유효하지 않으면 사용자 인증 진행
    print("🌐 브라우저/콘솔 인증을 시작합니다...");

    // 우분투 Headless(GUI 없음) 환경 및 모바일 수동 접속을 고려하여 콘솔 프롬프트 인증 지원
    final client = await clientViaUserConsent(
      clientId,
      scopes,
      _openBrowser,
    );

    _credentials = client.credentials; // currentUser용 내부 상태 업데이트

    // .data/credentials.json 에 저장
    await _saveTokenFile(client.credentials);

    print("💾 최초 .data/credentials.json 저장 완료!");

    return client;
  }

  void _openBrowser(String url) {
    print("\n====================================================");
    print("🔗 스마트폰이나 PC 브라우저에서 아래 URL에 접속해 인증을 완료해주세요:");
    print(url);
    print("====================================================\n");

    if (Platform.isWindows) {
      Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isLinux) {
      // 우분투 GUI 환경일 때만 실행 (실패해도 콘솔 URL 출력으로 대체 가능)
      Process.run('xdg-open', [url]).catchError((_) {});
    }
  }
}

GoogleAuthService getGoogleAuthService(List<String> scopes) {
  return DesktopGoogleAuthService(scopes);
}