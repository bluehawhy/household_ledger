import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveFolderService extends Mock implements DriveFolderService {}

class MockDriveSheetService extends Mock implements DriveSheetService {}

void main() {
  const accountEmail = 'owner@example.com';
  const folderName = '가계부';
  const folderId = 'folder-123';

  late LedgerCacheManager cacheManager;
  late MockDriveFolderService folderService;
  late MockDriveSheetService sheetService;

  setUp(() {
    cacheManager = LedgerCacheManager();
    folderService = MockDriveFolderService();
    sheetService = MockDriveSheetService();
  });

  group('LedgerCacheManager', () {
    test('초기 상태에서는 폴더 및 연도별 시트 캐시가 비어 있다', () {
      expect(cacheManager.isInitialized, isFalse);
      expect(cacheManager.getFoldersByAccount(accountEmail), isNull);
      expect(cacheManager.getSpreadsheetId(2026), isNull);
    });

    test('연도별 시트 ID를 등록하고 조회한다', () {
      cacheManager.registerSpreadsheetId(2025, 'sheet-2025');
      cacheManager.registerSpreadsheetId(2026, 'sheet-2026');

      expect(cacheManager.getSpreadsheetId(2025), 'sheet-2025');
      expect(cacheManager.getSpreadsheetId(2026), 'sheet-2026');
      expect(cacheManager.getSpreadsheetId(2027), isNull);
    });

    test('폴더 캐시 miss 시 전체 폴더 목록을 갱신해 요청 계정의 폴더를 반환한다',
        () async {
      when(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).thenAnswer(
        (_) async => {
          accountEmail: {folderName: folderId},
          'shared@example.com': {folderName: 'shared-folder-456'},
        },
      );

      final result = await cacheManager.cachedFolderId(
        folderService,
        accountEmail: accountEmail,
        folderName: folderName,
      );

      expect(result, folderId);
      expect(
        cacheManager.getFoldersByAccount(accountEmail),
        {folderName: folderId},
      );
      verify(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).called(1);
    });

    test('폴더 캐시 hit 시 Drive 조회를 다시 수행하지 않는다', () async {
      when(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).thenAnswer((_) async => {accountEmail: {folderName: folderId}});

      await cacheManager.cachedFolderId(
        folderService,
        accountEmail: accountEmail,
        folderName: folderName,
      );
      final cachedId = await cacheManager.cachedFolderId(
        folderService,
        accountEmail: accountEmail,
        folderName: folderName,
      );

      expect(cachedId, folderId);
      verify(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).called(1);
    });

    test('폴더를 찾지 못하면 null을 반환하고 시트 초기화를 진행하지 않는다',
        () async {
      when(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).thenAnswer((_) async => {});

      await cacheManager.initializeAllSheets(
        folderRepo: folderService,
        sheetRepo: sheetService,
        accountEmail: accountEmail,
        folderName: folderName,
      );

      expect(cacheManager.isInitialized, isFalse);
      expect(cacheManager.getSpreadsheetId(2026), isNull);
      verifyNever(
        () => sheetService.getYearlySpreadsheets(
          folderId: any(named: 'folderId'),
          sheetName: any(named: 'sheetName'),
        ),
      );
    });

    test('초기화하면 해당 폴더의 연도별 스프레드시트를 캐시한다', () async {
      when(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).thenAnswer((_) async => {accountEmail: {folderName: folderId}});
      when(
        () => sheetService.getYearlySpreadsheets(
          folderId: folderId,
          sheetName: folderName,
        ),
      ).thenAnswer((_) async => {2025: 'sheet-2025', 2026: 'sheet-2026'});

      await cacheManager.initializeAllSheets(
        folderRepo: folderService,
        sheetRepo: sheetService,
        accountEmail: accountEmail,
        folderName: folderName,
      );

      expect(cacheManager.isInitialized, isTrue);
      expect(cacheManager.getSpreadsheetId(2025), 'sheet-2025');
      expect(cacheManager.getSpreadsheetId(2026), 'sheet-2026');
      verify(
        () => sheetService.getYearlySpreadsheets(
          folderId: folderId,
          sheetName: folderName,
        ),
      ).called(1);
    });

    test('clear는 폴더 캐시와 연도별 시트 캐시를 모두 비운다', () async {
      when(
        () => folderService.getAllTargetFolders(folderName: folderName),
      ).thenAnswer((_) async => {accountEmail: {folderName: folderId}});
      await cacheManager.cachedFolderId(
        folderService,
        accountEmail: accountEmail,
        folderName: folderName,
      );
      cacheManager.registerSpreadsheetId(2026, 'sheet-2026');

      cacheManager.clear();

      expect(cacheManager.isInitialized, isFalse);
      expect(cacheManager.getFoldersByAccount(accountEmail), isNull);
      expect(cacheManager.getSpreadsheetId(2026), isNull);
    });
  });
}
