import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http; // 👈 추가
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';

void main() async {
  final ledgerApp = HouseHoldLedgerSetup();
  await ledgerApp.run();
}

class HouseHoldLedgerSetup {
  final _scopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  // 인증 토큰을 저장할 파일 경로
  final _tokenFile = File('credentials.json');

  /// 1. client_secret.json 파일 로드
  Future<ClientId> _loadClientIdFromJson() async {
    var configFile = File('client_secret.json');
    if (!await configFile.exists()) {
      configFile = File('client_secret.json');
    }

    if (!await configFile.exists()) {
      throw Exception("❌ 'client_secret.json' 파일을 찾을 수 없습니다!");
    }

    final jsonString = await configFile.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);
    return ClientId(data['client_id'], data['client_secret']);
  }

Future<AuthClient> _getAuthenticatedClient(ClientId clientId) async {
  if (await _tokenFile.exists()) {
    try {
      final jsonString = await _tokenFile.readAsString();
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

      // 1. JSON에서 AccessToken 객체 복원 (만료 시간 명시)
      final accessTokenMap = jsonMap['accessToken'] as Map<String, dynamic>?;
      if (accessTokenMap != null) {
        final tokenType = accessTokenMap['type'] as String? ?? 'Bearer';
        final data = accessTokenMap['data'] as String;
        final expiryStr = accessTokenMap['expiry'] as String;
        final expiry = DateTime.parse(expiryStr);

        final accessToken = AccessToken(tokenType, data, expiry);
        final refreshToken = jsonMap['refreshToken'] as String?;
        final idToken = jsonMap['idToken'] as String?;
        final scopes = (jsonMap['scopes'] as List<dynamic>?)?.cast<String>() ?? _scopes;

        var credentials = AccessCredentials(
          accessToken,
          refreshToken,
          scopes,
          idToken: idToken,
        );

        final httpClient = http.Client();

        // 2. 토큰이 만료되었거나 만료 직전이면 리프레시 토큰으로 자동 갱신
        if (credentials.accessToken.hasExpired) {
          if (refreshToken != null) {
            print("🔄 토큰이 만료되어 자동으로 갱신합니다...");
            credentials = await refreshCredentials(clientId, credentials, httpClient);
            // 갱신된 새 토큰 저장
            await _tokenFile.writeAsString(jsonEncode(credentials.toJson()));
          } else {
            throw Exception("Refresh token이 없습니다.");
          }
        }

        // 3. 인증된 AuthClient 생성
        final client = authenticatedClient(httpClient, credentials);
        print("🔑 캐시된 인증 토큰(credentials.json)을 사용하여 로그인을 완료했습니다!");
        return client;
      }
    } catch (e) {
      print("⚠️ 저장된 토큰 처리 중 오류 발생 ($e). 브라우저 로그인을 재진행합니다.");
    }
  }

  // 저장된 토큰이 없거나 무효한 경우 최초 로그인
  print("\n🌐 최초 인증이 필요합니다. 브라우저를 열어 구글 로그인을 진행합니다...");
  final client = await clientViaUserConsent(
    clientId,
    _scopes,
    (url) => _openBrowser(url),
  );

  // 새로운 토큰 저장
  final credentials = client.credentials;
  await _tokenFile.writeAsString(jsonEncode(credentials.toJson()));
  print("💾 새로운 인증 토큰이 '${_tokenFile.path}' 파일에 저장되었습니다!");

  return client;
}

  Future<void> run() async {
    print("--------------------------------------------------");
    print("🚀 가계부 시스템 실행 (토큰 자동 캐싱 지원)");
    print("--------------------------------------------------");

    AuthClient? client;
    try {
      final clientId = await _loadClientIdFromJson();

      // 토큰 캐시를 활용하여 클라이언트 획득
      client = await _getAuthenticatedClient(clientId);

      final driveApi = drive.DriveApi(client);
      final sheetsApi = sheets.SheetsApi(client);

      // 1. '가계부' 폴더 확인 및 생성
      final folderId = await _getOrCreateFolder(driveApi, "가계부");

      // 2. 현재 연도 기준 파일명 생성 (예: 가계부_2026)
      final currentYear = DateTime.now().year;
      final fileName = "가계부_$currentYear";

      // 3. 폴더 내 연도별 스프레드시트 확인 및 생성
      final spreadsheetId = await _getOrCreateSpreadsheet(
        driveApi,
        sheetsApi,
        folderId,
        fileName,
      );

      print("\n--------------------------------------------------");
      print("🎉 가계부 시트 작업 완벽 완료!");
      print("📄 시트 ID: $spreadsheetId");
      print("--------------------------------------------------");
    } catch (e) {
      print("\n❌ 작업 중 에러 발생: $e");
    } finally {
      client?.close();
    }
  }

  /// 3. 구글 드라이브 폴더 생성/검색
  Future<String> _getOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
    print("\n📁 1. '$folderName' 폴더 확인 중...");

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 폴더 사용 (ID: $id)");
      return id;
    }

    print("  └ ➕ '$folderName' 폴더가 없습니다. 신규 생성 중...");
    final folderMetaData = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await driveApi.files.create(folderMetaData);
    print("  └ 🎉 폴더 생성 완료! (ID: ${createdFolder.id})");
    return createdFolder.id!;
  }

  /// 4. 연도별 스프레드시트 생성
  Future<String> _getOrCreateSpreadsheet(
    drive.DriveApi driveApi,
    sheets.SheetsApi sheetsApi,
    String folderId,
    String fileName,
  ) async {
    print("\n📊 2. '$fileName' 파일 확인 중...");

    final query =
        "name = '$fileName' and '$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 파일이 존재합니다. (ID: $id)");
      return id;
    }

    print("  └ ➕ '$fileName' 파일이 없습니다. 시트 구조를 생성합니다...");

    final List<sheets.Sheet> sheetsList = [
      sheets.Sheet(properties: sheets.SheetProperties(title: 'Overview')),
    ];

    for (int month = 1; month <= 12; month++) {
      sheetsList.add(
        sheets.Sheet(properties: sheets.SheetProperties(title: '${month}월')),
      );
    }

    final spreadsheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: fileName),
      sheets: sheetsList,
    );

    final createdSpreadsheet = await sheetsApi.spreadsheets.create(spreadsheet);
    final spreadsheetId = createdSpreadsheet.spreadsheetId!;

    await driveApi.files.update(
      drive.File(),
      spreadsheetId,
      addParents: folderId,
    );

    print("  └ 🎨 Overview 시트 및 월별 헤더 세팅 중...");
    await _initializeAllSheets(sheetsApi, spreadsheetId);

    return spreadsheetId;
  }

  /// 5. Overview 및 월별 시트 초기 세팅
  Future<void> _initializeAllSheets(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
  ) async {
    List<sheets.ValueRange> data = [];

    // Overview 안내표
    final List<List<String>> overviewGuide = [
      ["📌 [수입 분류 안내]", ""],
      ["주수입", "월급, 상여금, 사업소득"],
      ["부수입", "부업, 당근마켓/중고거래 판매, 기타 수입"],
      ["금융소득", "이자, 배당금, 주식/코인 수익"],
      ["포인트/캐시백", "네이버페이 포인트, 카드 캐시백, 기프티콘 사용"],
      ["", ""],
      ["📌 [지출 분류 안내]", ""],
      ["식비", "식재료 구매, 외식, 배달음식, 카페/디저트"],
      ["고정지출", "월세, 공과금(전기/수도/가스), 통신비, 보험료, 구독서비스 등"],
      ["생활/주거", "생필품, 가구/가전, 청소/위생용품"],
      ["교통/차량", "대중교통, 주유비, 주차비, 정비/통행료"],
      ["쇼핑/패션", "의류, 잡화, 뷰티, 미용실"],
      ["문화/여가", "영화/공연, 취미, 여행, 운동/헬스"],
      ["경조사/선물", "부조금, 축의금, 명절/생일 선물, 용돈"],
      ["의료/건강", "병원비, 약국, 영양제"],
      ["교육/자기개발", "학원비, 도서 구매, 강의/시험 응시료"],
      ["기타", "예비비, 분류 불가 지출"],
    ];

    data.add(
      sheets.ValueRange(range: "'Overview'!A1:B17", values: overviewGuide),
    );

    // 수입 요약표 수식
    final monthsHeader = [
      "수입분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];
    final incomeCategories = ["주수입", "부수입", "금융소득", "포인트/캐시백"];
    List<List<String>> incomeTable = [monthsHeader];

    for (int i = 0; i < incomeCategories.length; i++) {
      final category = incomeCategories[i];
      final rowNum = 21 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIF('${m}월'!\$B:\$B, \$A$rowNum, '${m}월'!\$D:\$D)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      incomeTable.add(row);
    }
    List<String> incomeTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      incomeTotalRow.add("=SUM(${colLetter}21:${colLetter}24)");
    }
    incomeTable.add(incomeTotalRow);

    data.add(
      sheets.ValueRange(range: "'Overview'!A20:N25", values: incomeTable),
    );

    // 지출 요약표 수식
    final expenseCategories = [
      "식비", "고정지출", "생활/주거", "교통/차량", "쇼핑/패션",
      "문화/여가", "경조사/선물", "의료/건강", "교육/자기개발", "기타"
    ];
    final expenseMonthsHeader = [
      "지출분류", "1월", "2월", "3월", "4월", "5월", "6월",
      "7월", "8월", "9월", "10월", "11월", "12월", "연간 합계"
    ];
    List<List<String>> expenseTable = [expenseMonthsHeader];

    for (int i = 0; i < expenseCategories.length; i++) {
      final category = expenseCategories[i];
      final rowNum = 29 + i;
      List<String> row = [category];
      for (int m = 1; m <= 12; m++) {
        row.add("=SUMIF('${m}월'!\$H:\$H, \$A$rowNum, '${m}월'!\$J:\$J)");
      }
      row.add("=SUM(B$rowNum:M$rowNum)");
      expenseTable.add(row);
    }
    List<String> expenseTotalRow = ["합계"];
    for (int colIdx = 0; colIdx < 13; colIdx++) {
      final colLetter = String.fromCharCode(66 + colIdx);
      expenseTotalRow.add("=SUM(${colLetter}29:${colLetter}38)");
    }
    expenseTable.add(expenseTotalRow);

    data.add(
      sheets.ValueRange(range: "'Overview'!A28:N39", values: expenseTable),
    );

    // 1~12월 헤더
    for (int month = 1; month <= 12; month++) {
      final sheetName = '${month}월';
      data.add(
        sheets.ValueRange(
          range: "'$sheetName'!A1:J1",
          values: [
            [
              "날짜", "수입 분류", "내용", "금액", "",
              "날짜", "지출 수단", "지출 분류", "내용", "금액"
            ]
          ],
        ),
      );
    }

    final request = sheets.BatchUpdateValuesRequest(
      valueInputOption: "USER_ENTERED",
      data: data,
    );

    await sheetsApi.spreadsheets.values.batchUpdate(request, spreadsheetId);
    print("  └ ✅ Overview 종합 통계표 및 1~12월 헤더 세팅 완료!");
  }

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