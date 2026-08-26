import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:mocktail/mocktail.dart';

// Your LedgerCacheManager & Repositories file import
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';

// DriveApi Mocking 클래스 정의
class MockDriveApi extends Mock implements drive.DriveApi {}
class MockFilesResource extends Mock implements drive.FilesResource {}

void main() {
  late LedgerCacheManager cacheManager;
  late MockDriveApi mockDriveApi;
  late MockFilesResource mockFilesResource;
  late DriveFolderRepository folderRepo;
  late DriveSheetRepository sheetRepo;

  setUp(() {
    cacheManager = LedgerCacheManager();
    mockDriveApi = MockDriveApi();
    mockFilesResource = MockFilesResource();

    // driveApi.files 호출 시 mockFilesResource를 반환하도록 설정
    when(() => mockDriveApi.files).thenReturn(mockFilesResource);

    // mockDriveApi를 사용하는 Repository 인스턴스 초기화
    folderRepo = DriveFolderRepository(mockDriveApi);
    sheetRepo = DriveSheetRepository(mockDriveApi);
  });

  group('LedgerCacheManager 단위 테스트', () {

    test('초기 상태 및 clear() 테스트', () {
      expect(cacheManager.isInitialized, isFalse);
      expect(cacheManager.getSpreadsheetId(2026), isNull);

      // 캐시 수동 등록
      cacheManager.registerSpreadsheetId(2026, 'sheet_2026_id');
      expect(cacheManager.getSpreadsheetId(2026), 'sheet_2026_id');

      // clear 후 확인
      cacheManager.clear();
      expect(cacheManager.isInitialized, isFalse);
      expect(cacheManager.getSpreadsheetId(2026), isNull);
    });

    test('registerSpreadsheetId 및 getSpreadsheetId 동작 확인', () {
      cacheManager.registerSpreadsheetId(2025, 'sheet_id_2025');
      cacheManager.registerSpreadsheetId(2026, 'sheet_id_2026');

      expect(cacheManager.getSpreadsheetId(2025), 'sheet_id_2025');
      expect(cacheManager.getSpreadsheetId(2026), 'sheet_id_2026');
      expect(cacheManager.getSpreadsheetId(2027), isNull);
    });

    test('initializeAllSheets - 구글 드라이브 파일 목록을 파싱하여 캐시에 연도별 ID를 정확히 저장하는지 테스트', () async {
      // 1. '가계부' 폴더 검색 결과 Mocking
      final mockFolderList = drive.FileList(
        files: [
          drive.File(id: 'folder_123', name: '가계부'),
        ],
      );

      // 2. '가계부' 폴더 내 연도별 시트 파일 목록 Mocking
      final mockSheetList = drive.FileList(
        files: [
          drive.File(id: 'sheet_2025_id', name: '가계부_2025'),
          drive.File(id: 'sheet_2026_id', name: '가계부_2026'),
          drive.File(id: 'random_id', name: '기타문서'), // 정규식에 안 맞는 파일
        ],
      );

      // driveApi.files.list 호출에 대한 행위 정의 (폴더 조회 -> 시트 조회 2회 호출)
      when(() => mockFilesResource.list(
        q: any(named: 'q'),
        $fields: any(named: '\$fields'),
      )).thenAnswer((invocation) async {
        final query = invocation.namedArguments[#q] as String;
        if (query.contains("mimeType = 'application/vnd.google-apps.folder'")) {
          return mockFolderList;
        } else {
          return mockSheetList;
        }
      });

      // initializeAllSheets 실행 (setUp에서 생성한 folderRepo, sheetRepo 전달)
      await cacheManager.initializeAllSheets(
        folderRepo: folderRepo,
        sheetRepo: sheetRepo,
      );

      // Verify: 결과 검증
      expect(cacheManager.isInitialized, isTrue);
      expect(cacheManager.getSpreadsheetId(2025), 'sheet_2025_id');
      expect(cacheManager.getSpreadsheetId(2026), 'sheet_2026_id');
      expect(cacheManager.getSpreadsheetId(2024), isNull); // 파싱 안 된 연도
    });

    test('getFolderId - 폴더가 존재하지 않을 때 새로 생성하는지 테스트', () async {
      // 폴더 조회 시 빈 리스트 반환
      final emptyFolderList = drive.FileList(files: []);
      final createdFolder = drive.File(id: 'new_folder_999', name: '가계부');

      when(() => mockFilesResource.list(q: any(named: 'q')))
          .thenAnswer((_) async => emptyFolderList);

      when(() => mockFilesResource.create(any()))
          .thenAnswer((_) async => createdFolder);

      // mockDriveApi 대신 folderRepo 객체를 전달
      final folderId = await cacheManager.getFolderId(folderRepo);

      expect(folderId, 'new_folder_999');
      expect(cacheManager.isInitialized, isTrue);
      
      // create 함수가 1번 호출되었는지 검증
      verify(() => mockFilesResource.create(any())).called(1);
    });
  });
}