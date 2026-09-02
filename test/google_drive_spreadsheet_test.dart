import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveApi extends Mock implements drive.DriveApi {}

class MockFilesResource extends Mock implements drive.FilesResource {}

void main() {
  late MockDriveApi driveApi;
  late MockFilesResource filesResource;
  late DriveSheetService service;

  setUp(() {
    driveApi = MockDriveApi();
    filesResource = MockFilesResource();
    service = DriveSheetService(driveApi);

    when(() => driveApi.files).thenReturn(filesResource);
  });

  group('DriveSheetService Mock 테스트', () {
    test('특정 폴더의 스프레드시트 목록을 정상적으로 가져온다', () async {
      const folderId = 'mock-folder-id';

      final response = drive.FileList()
        ..files = [
          drive.File()
            ..id = 'sheet-2024'
            ..name = '가계부_2024'
            ..mimeType = 'application/vnd.google-apps.spreadsheet',
          drive.File()
            ..id = 'sheet-2025'
            ..name = '가계부_2025'
            ..mimeType = 'application/vnd.google-apps.spreadsheet',
          drive.File()
            ..id = 'sheet-2026'
            ..name = '가계부_2026'
            ..mimeType = 'application/vnd.google-apps.spreadsheet',
          drive.File()
            ..id = 'other-sheet'
            ..name = '다른문서'
            ..mimeType = 'application/vnd.google-apps.spreadsheet',
        ];

      when(
        () => filesResource.list(
          q: any(named: 'q'),
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => response);

      final result = await service.getSpreadsheetsInFolder(folderId: folderId);

      expect(result, {
        '가계부_2024': 'sheet-2024',
        '가계부_2025': 'sheet-2025',
        '가계부_2026': 'sheet-2026',
        '다른문서': 'other-sheet',
      });

      verify(
        () => filesResource.list(
          q: "'$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
          $fields: 'files(id, name)',
        ),
      ).called(1);
    });

    test('폴더에 시트가 없으면 빈 Map을 반환한다', () async {
      final response = drive.FileList()..files = [];

      when(
        () => filesResource.list(
          q: any(named: 'q'),
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => response);

      final result = await service.getSpreadsheetsInFolder(
        folderId: 'empty-folder',
      );

      expect(result, isEmpty);
    });

    test('연도 패턴에 맞는 가계부 시트만 연도별 ID로 변환한다', () async {
      final response = drive.FileList()
        ..files = [
          drive.File()
            ..id = 'sheet-2024'
            ..name = '가계부_2024',
          drive.File()
            ..id = 'sheet-2025'
            ..name = '가계부_2025',
          drive.File()
            ..id = 'sheet-2026'
            ..name = '가계부_2026',
          drive.File()
            ..id = 'not-year'
            ..name = '가계부_2026_backup',
          drive.File()
            ..id = 'other'
            ..name = '생활비_2026',
        ];

      when(
        () => filesResource.list(
          q: any(named: 'q'),
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => response);

      final result = await service.getYearlySpreadsheets(
        folderId: 'mock-folder-id',
        sheetName: '가계부',
      );

      expect(result, {
        2024: 'sheet-2024',
        2025: 'sheet-2025',
        2026: 'not-year',
      });
    });

    test('ID가 없는 파일은 결과에서 제외한다', () async {
      final response = drive.FileList()
        ..files = [
          drive.File()..name = '가계부_2026',
          drive.File()..id = 'valid-id',
        ];

      when(
        () => filesResource.list(
          q: any(named: 'q'),
          $fields: any(named: r'$fields'),
        ),
      ).thenAnswer((_) async => response);

      final result = await service.getSpreadsheetsInFolder(
        folderId: 'mock-folder-id',
      );

      expect(result, isEmpty);
    });
  });
}
