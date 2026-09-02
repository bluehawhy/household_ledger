//google_drive_cache.dart

import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 연도별 시트 ID 캐싱/관리 클래스
// ============================================================================
class LedgerCacheManager {
  /// 구조 변경: Map<이메일 계정, Map<폴더 이름, 폴더 ID>>
  final Map<String, Map<String, String>> _folderIdMap = {};
  
  /// 연도별 시트 Map (필요 시 accountEmail별 관리이 필요하다면 확장 가능)
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  bool get isInitialized => _folderIdMap.isNotEmpty;

  /// 1️⃣ 특정 계정의 특정 폴더 ID 조회 (없으면 드라이브에서 가져와서 캐싱)
  /// [accountEmail]을 필수로 전달받아 'me' 기본값 사용으로 인한 Key 불일치 버그를 방지합니다.
  Future<String?> cachedFolderId(
    DriveFolderService folderRepo, {
    required String accountEmail,
    String folderName = "가계부",
  }) async {
    AppLogger.i("📁 [캐시 확인 시작] 계정: $accountEmail, 폴더명: $folderName");
    AppLogger.i(" ├ 📦 현재 전체 캐시 상태: $_folderIdMap");

    if (_folderIdMap.containsKey(accountEmail) &&
        _folderIdMap[accountEmail]!.containsKey(folderName)) {
      final folderId = _folderIdMap[accountEmail]![folderName];
      AppLogger.i(" └ ⚡ [캐시 HIT] 메모리에서 폴더 ID 즉시 반환 ($accountEmail -> $folderName: $folderId)");
      return folderId;
    }

    AppLogger.i(" ├ 🔄 [캐시 MISS] 캐시에 정보가 없어 드라이브에서 전체 폴더 ID를 갱신합니다.");

    await refreshAllFolderIds(folderRepo, folderName: folderName);

    final updatedFolderId = _folderIdMap[accountEmail]?[folderName];

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

  /// 3️⃣ 모든 계정의 연도별 시트 목록 스캔 및 캐싱
  ///
  /// 폴더 캐시는 내 계정뿐 아니라 공유받은 계정까지 통합되어 있으므로,
  /// 초기화 시 모든 계정의 '$folderName' 폴더를 순회하여
  /// {계정: {시트명: 시트ID}} 형태로 전체 공유 시트 정보를 로그로 남긴다.
  ///
  /// 기존의 _yearToSpreadsheetIdMap은 현재 로그인 계정의 폴더만 대상으로
  /// 유지하여, 공유 계정의 동일 연도 시트가 현재 계정 캐시를 덮어쓰지 않도록 한다.
  Future<void> initializeAllSheets({
    required DriveFolderService folderRepo,
    required DriveSheetService sheetRepo,
    required String accountEmail,
    String folderName = "가계부",
  }) async {
    // 먼저 내 계정 + 공유받은 계정의 폴더를 모두 확보한다.
    final currentFolderId = await cachedFolderId(
      folderRepo,
      accountEmail: accountEmail,
      folderName: folderName,
    );

    if (currentFolderId == null) {
      AppLogger.w("계정 '$accountEmail'의 '$folderName' 폴더를 찾을 수 없습니다.");
    }

    // 전체 계정의 폴더별 스프레드시트를 조회한다.
    final allSpreadsheetMaps = <String, Map<String, String>>{};

    for (final entry in _folderIdMap.entries) {
      final email = entry.key;
      final folderMap = entry.value;

      for (final folderEntry in folderMap.entries) {
        final targetFolderName = folderEntry.key;
        final folderId = folderEntry.value;

        try {
          final sheetMap = await sheetRepo.getSpreadsheetsInFolder(
            folderId: folderId,
          );

          final accountSheetKey = '$email / $targetFolderName';
          allSpreadsheetMaps[accountSheetKey] = sheetMap;

          AppLogger.i(
            "📊 [$email] '$targetFolderName' 폴더(ID: $folderId) 내 전체 시트: $sheetMap",
          );
        } catch (e) {
          AppLogger.e(
            "❌ [$email] '$targetFolderName' 폴더(ID: $folderId) 내 시트 조회 실패: $e",
          );
        }
      }
    }

    AppLogger.i("📊 전체 공유 스프레드시트 통합 목록: $allSpreadsheetMaps");

    // 기존 기능 유지: 현재 로그인 계정의 연도별 시트만 기존 캐시에 저장한다.
    if (currentFolderId == null) {
      return;
    }

    final yearSheets = await sheetRepo.getYearlySpreadsheets(
      folderId: currentFolderId,
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

  /// 캐시된 전체 계정 이메일 목록 반환 (내 계정 + 공유받은 계정들)
  List<String> get cachedAccountEmails => _folderIdMap.keys.toList();

  /// 특정 계정(내 계정 또는 공유 계정)의 가계부 폴더 ID가 캐시에 있는지 확인
  bool hasFolderForAccount(String accountEmail, {String folderName = "가계부"}) {
    return _folderIdMap[accountEmail]?.containsKey(folderName) ?? false;
  }

  /// 특정 계정의 모든 폴더 맵 조회
  Map<String, String>? getFoldersByAccount(String accountEmail) =>
      _folderIdMap[accountEmail];

  /// 캐시 전체 초기화
  void clear() {
    _folderIdMap.clear();
    _yearToSpreadsheetIdMap.clear();
  }

  /// 기존 UI 호출과의 호환성을 위한 캐시 초기화 메서드
  Future<void> clearCache() async {
    clear();
  }
}
