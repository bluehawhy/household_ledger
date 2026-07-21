import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

void main() async {
  print("--------------------------------------------------");
  print("🚀 가계부 시스템 실행 (클래스 분리 구조)");
  print("--------------------------------------------------");

  final authService = GoogleAuthService();
  final sheetService = HouseholdSheetService();

  AuthClient? client;
  try {
    // 1. 구글 인증 진행 (캐시 토큰 활용)
    client = await authService.getAuthenticatedClient();

    // 2. 가계부 폴더 및 스프레드시트 초기화 진행
    final spreadsheetId = await sheetService.setupLedgerSpreadsheet(client);

    print("\n--------------------------------------------------");
    print("🎉 모든 가계부 시트 설정이 완료되었습니다!");
    print("📄 시트 ID: $spreadsheetId");
    print("--------------------------------------------------");
  } catch (e) {
    print("\n❌ 작업 중 에러 발생: $e");
  } finally {
    client?.close();
  }
}

// ============================================================================
// 🔑 1. 구글 OAuth2 인증 전담 서비스 클래스
// ============================================================================
class GoogleAuthService {
  final List<String> _scopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  // 최상위 루트 디렉터리에 보안 파일 위치
  final File _secretFile = File('client_secret.json');
  final File _tokenFile = File('credentials.json');

  /// client_secret.json 읽기
  Future<ClientId> _loadClientId() async {
    var file = _secretFile;
    if (!await file.exists()) {
      file = File('lib/client_secret.json');
    }

    if (!await file.exists()) {
      throw Exception("❌ 'client_secret.json' 파일을 찾을 수 없습니다!");
    }

    final jsonString = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(jsonString);
    return ClientId(data['client_id'], data['client_secret']);
  }

  /// 인증된 AuthClient 가져오기 (캐시 토큰 우선 사용)
  Future<AuthClient> getAuthenticatedClient() async {
    final clientId = await _loadClientId();

    // A. 저장된 토큰(credentials.json)이 존재하는 경우
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
          final scopes =
              (jsonMap['scopes'] as List<dynamic>?)?.cast<String>() ?? _scopes;

          var credentials = AccessCredentials(
            accessToken,
            refreshToken,
            scopes,
            idToken: idToken,
          );

          final httpClient = http.Client();

          // Access Token 만료 시 Refresh Token으로 자동 갱신
          if (credentials.accessToken.hasExpired) {
            if (refreshToken != null) {
              print("🔄 Access Token이 만료되어 자동으로 갱신합니다...");
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

          final client = authenticatedClient(httpClient, credentials);
          print("🔑 저장된 인증 토큰(credentials.json)으로 로그인 성공!");
          return client;
        }
      } catch (e) {
        print("⚠️ 토큰 복원 중 오류 발생 ($e). 다시 브라우저 로그인을 진행합니다.");
      }
    }

    // B. 최초 로그인 (브라우저 승인)
    print("\n🌐 최초 인증이 필요합니다. 브라우저를 열어 로그인해 주세요...");
    final client = await clientViaUserConsent(
      clientId,
      _scopes,
      (url) => _openBrowser(url),
    );

    // 신규 토큰 저장
    await _tokenFile.writeAsString(jsonEncode(client.credentials.toJson()));
    print("💾 새로운 인증 토큰이 'credentials.json'에 저장되었습니다!");

    return client;
  }

  /// OS별 브라우저 오픈
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

// ============================================================================
// 📊 2. 가계부 구글 드라이브 및 스프레드시트 관리 서비스 클래스
// ============================================================================
class HouseholdSheetService {
  /// 가계부 폴더 및 연도별 시트 전체 설정 진행
  Future<String> setupLedgerSpreadsheet(AuthClient client) async {
    final driveApi = drive.DriveApi(client);
    final sheetsApi = sheets.SheetsApi(client);

    // 1. '가계부' 폴더 확인/생성
    final folderId = await _getOrCreateFolder(driveApi, "가계부");

    // 2. 현재 연도 기준 파일 생성 (예: 가계부_2026)
    final currentYear = DateTime.now().year;
    final fileName = "가계부_$currentYear";

    // 3. 스프레드시트 확인/생성 및 초기화
    return await _getOrCreateSpreadsheet(
      driveApi,
      sheetsApi,
      folderId,
      fileName,
    );
  }

  /// 구글 드라이브 폴더 검색 및 생성
  Future<String> _getOrCreateFolder(
    drive.DriveApi driveApi,
    String folderName,
  ) async {
    print("\n📁 1. '$folderName' 폴더 확인 중...");

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final result = await driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      print("  └ 💡 기존 폴더 사용 (ID: $id)");
      return id;
    }

    print("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final folderMetaData = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await driveApi.files.create(folderMetaData);
    print("  └ 🎉 폴더 생성 완료! (ID: ${createdFolder.id})");
    return createdFolder.id!;
  }

  /// 연도별 스프레드시트 검색 및 구조화 생성
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
      print("  └ 💡 기존 파일이 이미 존재합니다. (ID: $id)");
      return id;
    }

    print("  └ ➕ '$fileName' 파일이 없어 새 시트를 생성합니다...");

    // Overview + 1월~12월 시트 구성
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

    // 지정 폴더로 이동
    await driveApi.files.update(
      drive.File(),
      spreadsheetId,
      addParents: folderId,
    );

    print("  └ 🎨 Overview 안내표, 월별 수식 및 헤더를 입력하는 중...");
    await _initializeAllSheets(sheetsApi, spreadsheetId);

    return spreadsheetId;
  }

  /// Overview 및 1~12월 시트 초기 데이터 및 수식 입력
  Future<void> _initializeAllSheets(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
  ) async {
    List<sheets.ValueRange> data = [];

    // [A] Overview 안내표
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

    // [B] Overview 수입 요약표 (SUMIF 수식)
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

    // [C] Overview 지출 요약표 (SUMIF 수식)
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

    // [D] 1~12월 헤더 입력
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
    print("  └ ✅ Overview 종합 통계표 및 1~12월 헤더 입력 세팅 완벽 완료!");
  }
}