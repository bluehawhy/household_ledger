import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:household_ledger/services/auth/google_auth.dart';

void main() {
  group('GoogleAuthManager', () {
    late GoogleAuthManager authManager;

    setUp(() {
      authManager = GoogleAuthManager();
    });

    test('기본 OAuth scope가 Drive와 Sheets를 포함한다', () {
      expect(
        GoogleAuthManager.defaultScopes,
        contains(drive.DriveApi.driveFileScope),
      );
      expect(
        GoogleAuthManager.defaultScopes,
        contains(sheets.SheetsApi.spreadsheetsScope),
      );
    });

    test('현재 로그인 계정 상태를 조회할 수 있다', () {
      expect(() => authManager.currentUser, returnsNormally);
    });

    test('signInSilently가 예외를 외부로 전파하지 않는다', () async {
      final result = await authManager.signInSilently();

      // 로그인 세션이 없으면 null이고, 세션이 있으면 currentUser와 동일하다.
      expect(result, same(authManager.currentUser));
    });
  });
}
