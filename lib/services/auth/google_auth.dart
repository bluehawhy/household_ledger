import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import '../spread_sheet/google_spreadsheet.dart';

// 1. 공통 타입(GoogleAuthService)만 가져오고, 스텁 함수는 숨깁니다 (hide).
import 'google_auth_stub.dart' hide getGoogleAuthService;

// 2. 조건부 임포트로 상황에 맞는 팩토리 함수(getGoogleAuthService)만 가져옵니다.
import 'google_auth_stub.dart'
    if (dart.library.ui) 'google_auth_mobile.dart'
    if (dart.library.io) 'google_auth_desktop.dart'
    show getGoogleAuthService;

export 'google_auth_stub.dart';

class GoogleSheetManager {
  static final List<String> defaultScopes = [
    drive.DriveApi.driveFileScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  final GoogleAuthService _authService = getGoogleAuthService(defaultScopes);
  final HouseholdSheetService _sheetService = HouseholdSheetService();

  Future<String> runHouseholdLedgerSetup() async {
    final client = await _authService.getAuthenticatedClient();
    try {
      final spreadsheetId = await _sheetService.setupLedgerSpreadsheet(client);
      return spreadsheetId;
    } finally {
      client.close();
    }
  }
}