import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveApi extends Mock implements drive.DriveApi {}

class MockPermissionsResource extends Mock implements drive.PermissionsResource {}

void main() {
  const spreadsheetId = 'spreadsheet-123';
  const email = 'member@example.com';

  late MockDriveApi driveApi;
  late MockPermissionsResource permissions;
  late DriveSheetService service;

  setUpAll(() {
    registerFallbackValue(drive.Permission());
  });

  setUp(() {
    driveApi = MockDriveApi();
    permissions = MockPermissionsResource();
    when(() => driveApi.permissions).thenReturn(permissions);
    service = DriveSheetService(driveApi);
  });

  drive.Permission permission({
    String? id,
    String? emailAddress,
    String? role,
  }) {
    return drive.Permission()
      ..id = id
      ..emailAddress = emailAddress
      ..role = role;
  }

  group('DriveSheetService.shareSpreadsheet', () {
    test('기존 권한이 없으면 writer 권한을 새로 생성한다', () async {
      when(
        () => permissions.list(
          spreadsheetId,
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => drive.PermissionList(permissions: []));
      final created = permission(id: 'permission-1', emailAddress: email, role: 'writer');
      when(
        () => permissions.create(
          any(),
          spreadsheetId,
          sendNotificationEmail: true,
        ),
      ).thenAnswer((_) async => created);

      final result = await service.shareSpreadsheet(
        spreadsheetId: spreadsheetId,
        email: email,
      );

      expect(result.id, 'permission-1');
      final captured = verify(
        () => permissions.create(
          any(),
          spreadsheetId,
          sendNotificationEmail: true,
        ),
      ).captured.single as drive.Permission;
      expect(captured.type, 'user');
      expect(captured.role, 'writer');
      expect(captured.emailAddress, email);
    });

    test('동일한 기존 권한이 있으면 API 변경 없이 그대로 반환한다', () async {
      final existing = permission(id: 'permission-1', emailAddress: email, role: 'writer');
      when(
        () => permissions.list(
          spreadsheetId,
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => drive.PermissionList(permissions: [existing]));

      final result = await service.shareSpreadsheet(
        spreadsheetId: spreadsheetId,
        email: email.toUpperCase(),
      );

      expect(result, same(existing));
      verifyNever(
        () => permissions.create(any(), any(), sendNotificationEmail: any(named: 'sendNotificationEmail')),
      );
      verifyNever(() => permissions.update(any(), any(), any()));
    });

    test('기존 권한의 역할이 다르면 역할을 업데이트한다', () async {
      final existing = permission(id: 'permission-1', emailAddress: email, role: 'reader');
      when(
        () => permissions.list(
          spreadsheetId,
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => drive.PermissionList(permissions: [existing]));
      final updated = permission(id: 'permission-1', emailAddress: email, role: 'writer');
      when(
        () => permissions.update(any(), spreadsheetId, 'permission-1'),
      ).thenAnswer((_) async => updated);

      final result = await service.shareSpreadsheet(
        spreadsheetId: spreadsheetId,
        email: email,
        role: 'writer',
      );

      expect(result.role, 'writer');
      final captured = verify(
        () => permissions.update(any(), spreadsheetId, 'permission-1'),
      ).captured.single as drive.Permission;
      expect(captured.role, 'writer');
    });
  });

  group('DriveSheetService.removeSpreadsheetShare', () {
    test('대상 사용자의 직접 공유 권한을 삭제한다', () async {
      final target = permission(id: 'permission-1', emailAddress: email, role: 'writer');
      when(
        () => permissions.list(
          spreadsheetId,
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => drive.PermissionList(permissions: [target]));
      when(() => permissions.delete(spreadsheetId, 'permission-1'))
          .thenAnswer((_) async {});

      final removed = await service.removeSpreadsheetShare(
        spreadsheetId: spreadsheetId,
        email: email,
      );

      expect(removed, isTrue);
      verify(() => permissions.delete(spreadsheetId, 'permission-1')).called(1);
    });

    test('대상 사용자의 직접 권한이 없으면 삭제하지 않고 false를 반환한다', () async {
      when(
        () => permissions.list(
          spreadsheetId,
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => drive.PermissionList(permissions: []));

      final removed = await service.removeSpreadsheetShare(
        spreadsheetId: spreadsheetId,
        email: email,
      );

      expect(removed, isFalse);
      verifyNever(() => permissions.delete(any(), any()));
    });
  });
}
