import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;

class GoogleAppsSpreadsheetService {
  // GoogleSignIn.standard() 또는 GoogleSignIn.initWithParams() 사용
  static final _googleSignIn = GoogleSignIn.standard(
    scopes: [
      drive.DriveApi.driveFileScope,
      sheets.SheetsApi.spreadsheetsScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  String? _spreadsheetId;

  GoogleSignInAccount? get currentUser => _currentUser;
  String? get spreadsheetId => _spreadsheetId;

  Future<bool> signInAndInitSpreadsheet() async {
    try {
      // 1. 구글 로그인
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) return false;

      // 2. AuthClient 획득
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) return false;

      // 3. 시트 확인 및 생성
      _spreadsheetId = await _getOrCreateLedgerSheet(authClient);
      return true;
    } catch (e) {
      print('Google Sign-In or Sheet Init Error: $e');
      return false;
    }
  }

  Future<String> _getOrCreateLedgerSheet(authClient) async {
    final driveApi = drive.DriveApi(authClient);

    final fileList = await driveApi.files.list(
      q: "name = '가계부' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
    );

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      print('기존 가계부 시트 발견 ID: ${fileList.files!.first.id}');
      return fileList.files!.first.id!;
    }

    final sheetsApi = sheets.SheetsApi(authClient);
    final newSheet = sheets.Spreadsheet(
      properties: sheets.SpreadsheetProperties(title: '가계부'),
    );

    final createdSheet = await sheetsApi.spreadsheets.create(newSheet);
    final newSpreadsheetId = createdSheet.spreadsheetId!;

    await sheetsApi.spreadsheets.values.append(
      sheets.ValueRange.fromJson({
        'values': [
          ['날짜', '분류', '사용처', '금액', '메모']
        ]
      }),
      newSpreadsheetId,
      'Sheet1!A1',
      valueInputOption: 'USER_ENTERED',
    );

    print('새 가계부 시트 생성 완료 ID: $newSpreadsheetId');
    return newSpreadsheetId;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _spreadsheetId = null;
  }
}
