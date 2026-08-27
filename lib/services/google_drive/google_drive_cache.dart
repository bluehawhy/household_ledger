import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 연도별 시트 ID 캐싱/관리 클래스
// ============================================================================
class LedgerCacheManager {
  /// 구조 변경: Map<이메일 계정, Map<폴더 이름, 폴더 ID>>
  final Map<String, Map<String, String>> _folderIdMap = {};
  
  /// 연도별 시트 Map (필요 시 accountEmail별 관리가 필요하다면 확장 가능)
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  bool get isInitialized => _folderIdMap.isNotEmpty;

  /// 1️⃣ 특정 계정의 특정 폴더 ID 조회 (없으면 드라이브에서 가져와서 캐싱)
  /// [accountEmail]을 필수로 전달받아 'me' 기본값 사용으로 인한 Key 불일치 버그를 방지합니다.
  Future<String?> cachedFolderId(
    DriveFolderService folderRepo, {
    required String accountEmail, // 'me' 기본값을 제거하고 필수 파라미터로 변경
    String folderName = "가계부",
  }) async {
    AppLogger.i("📁 [캐시 확인 시작] 계정: $accountEmail, 폴더명: $folderName");
    AppLogger.i(" ├ 📦 현재 전체 캐시 상태: $_folderIdMap");

    // 1. 캐시에 존재하면 캐시값 반환
    if (_folderIdMap.containsKey(accountEmail) &&
        _folderIdMap[accountEmail]!.containsKey(folderName)) {
      final folderId = _folderIdMap[accountEmail]![folderName];
      AppLogger.i(" └ ⚡ [캐시 HIT] 메모리에서 폴더 ID 즉시 반환 ($accountEmail -> $folderName: $folderId)");
      return folderId;
    }

    AppLogger.i(" ├ 🔄 [캐시 MISS] 캐시에 정보가 없어 드라이브에서 전체 폴더 ID를 갱신합니다.");

    // 2. 캐시에 없으면 내 드라이브/공유 폴더 전체 조회 수행 후 캐시 갱신
    await refreshAllFolderIds(folderRepo, folderName: folderName);

    final updatedFolderId = _folderIdMap[accountEmail]?[folderName];

    // 3. 갱신 후 캐시값 확인 및 반환
    AppLogger.i(" ├ 📦 갱신 후 전체 캐시 상태: $_folderIdMap");
    if (updatedFolderId != null) {
      AppLogger.i(" └ ✅ [갱신 완료] 갱신된 캐시에서 폴더 ID 조회 성공 ($accountEmail -> $folderName: $updatedFolderId)");
    } else {
      AppLogger.w(" └ ⚠️ [갱신 완료] 갱신 후에도 계정($accountEmail)의 '$folderName' 폴더 ID를 찾지 못했습니다.");
    }

    return updatedFolderId;
  }

  /// 2️⃣ 내 드라이브 + 공유된 폴더 전체 스캔 및 캐시 저장
  Future<void> refreshAllFolderIds(
    DriveFolderService folderRepo, {
    String folderName = "가계부",
  }) async {
    final allFolders = await folderRepo.getAllTargetFolders(folderName: folderName);

    allFolders.forEach((email, folderMap) {
      _folderIdMap.putIfAbsent(email, () => {}).addAll(folderMap);
    });

    AppLogger.i("📁 전체 폴더 캐시 갱신 완료: $_folderIdMap");
  }

  /// 3️⃣ 모든 연도별 시트 목록 스캔 및 캐싱 (Folder & Sheet Repository 이용)
  Future<void> initializeAllSheets({
    required DriveFolderService folderRepo,
    required DriveSheerService sheetRepo,
    required String accountEmail, // accountEmail을 필수 인자로 수정하여 'me' 기본값 제거
    String folderName = "가계부",
  }) async {
    final folderId = await cachedFolderId(
      folderRepo,
      accountEmail: accountEmail,
      folderName: folderName,
    );

    if (folderId == null) {
      AppLogger.w("계정 '$accountEmail'의 '$folderName' 폴더를 찾을 수 없습니다.");
      return;
    }

    final yearSheets = await sheetRepo.getYearlySpreadsheets(
      folderId: folderId,
      sheetName: folderName,
    );

    _yearToSpreadsheetIdMap.clear();
    _yearToSpreadsheetIdMap.addAll(yearSheets);

    AppLogger.i("[$accountEmail / $folderName] 연도별 시트 캐시 완료: $_yearToSpreadsheetIdMap");
  }

  /// 특정 연도의 시트 ID 가져오기 (캐시에서 읽기)
  String? getSpreadsheetId(int year) => _yearToSpreadsheetIdMap[year];

  /// 신규 생성된 연도 시트 ID 수동 등록
  void registerSpreadsheetId(int year, String spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

  /// 특정 계정의 모든 폴더 맵 조회
  Map<String, String>? getFoldersByAccount(String accountEmail) =>
      _folderIdMap[accountEmail];

  /// 캐시 전체 초기화
  void clear() {
    _folderIdMap.clear();
    _yearToSpreadsheetIdMap.clear();
  }
}