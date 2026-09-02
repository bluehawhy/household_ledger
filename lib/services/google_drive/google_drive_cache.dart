//google_drive_cache.dart

import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 가계부 구글 드라이브 폴더 및 스프레드시트 ID 캐싱/관리 클래스
// ============================================================================
class LedgerCacheManager {
  /// 구조: Map<이메일 계정, Map<폴더 이름, 폴더 ID>>
  final Map<String, Map<String, String>> _folderIdMap = {};

  /// 현재 로그인 계정의 연도별 시트 ID 캐시
  final Map<int, String> _yearToSpreadsheetIdMap = {};

  /// 전체 계정의 스프레드시트 캐시
  /// 구조: Map<이메일 계정, Map<스프레드시트 이름, 스프레드시트 ID>>
  final Map<String, Map<String, String>> _spreadsheetIdMap = {};

  bool get isInitialized => _folderIdMap.isNotEmpty;

  /// 1️⃣ 특정 계정의 특정 폴더 ID 조회
  /// 없으면 내 드라이브 + 공유 폴더 전체를 다시 스캔한다.
  Future<String?> cachedFolderId(
    DriveFolderService folderRepo, {
    required String accountEmail,
    String folderName = "가계부",
  }) async {
    AppLogger.i("📁 [캐시 확인 시작] 계정: $accountEmail, 폴더명: $folderName");
    AppLogger.i(" ├ 📦 현재 전체 폴더 캐시: $_folderIdMap");

    if (_folderIdMap.containsKey(accountEmail) &&
        _folderIdMap[accountEmail]!.containsKey(folderName)) {
      final folderId = _folderIdMap[accountEmail]![folderName];
      AppLogger.i(
        " └ ⚡ [캐시 HIT] $accountEmail -> $folderName: $folderId",
      );
      return folderId;
    }

    AppLogger.i(" ├ 🔄 [캐시 MISS] 전체 폴더 목록을 다시 조회합니다.");

    await refreshAllFolderIds(folderRepo, folderName: folderName);

    final updatedFolderId = _folderIdMap[accountEmail]?[folderName];

    AppLogger.i(" ├ 📦 갱신 후 전체 폴더 캐시: $_folderIdMap");
    if (updatedFolderId != null) {
      AppLogger.i(
        " └ ✅ [갱신 완료] $accountEmail -> $folderName: $updatedFolderId",
      );
    } else {
      AppLogger.w(
        " └ ⚠️ [갱신 완료] $accountEmail 계정의 '$folderName' 폴더를 찾지 못했습니다.",
      );
    }

    return updatedFolderId;
  }

  /// 2️⃣ 내 드라이브 + 공유된 폴더 전체 스캔 및 캐시 저장
  Future<void> refreshAllFolderIds(
    DriveFolderService folderRepo, {
    String folderName = "가계부",
  }) async {
    final allFolders = await folderRepo.getAllTargetFolders(
      folderName: folderName,
    );

    _folderIdMap.clear();
    allFolders.forEach((email, folderMap) {
      _folderIdMap[email] = Map<String, String>.from(folderMap);
    });

    AppLogger.i("📁 전체 가계부 폴더 캐시 갱신 완료: $_folderIdMap");
  }

  /// 3️⃣ 모든 계정의 스프레드시트 목록 스캔 및 캐싱
  ///
  /// 결과 구조:
  /// {
  ///   accountA@gmail.com: {
  ///     가계부_2026: SHEET_ID_A,
  ///     가계부_2025: SHEET_ID_B,
  ///   },
  ///   accountB@gmail.com: {
  ///     가계부_2026: SHEET_ID_C,
  ///   },
  /// }
  Future<void> initializeAllSheets({
    required DriveFolderService folderRepo,
    required DriveSheetService sheetRepo,
    required String accountEmail,
    String folderName = "가계부",
  }) async {
    AppLogger.i("📁 전체 가계부 폴더/스프레드시트 초기 스캔 시작");

    // 내 계정 + 공유 계정의 폴더를 먼저 확보한다.
    final currentFolderId = await cachedFolderId(
      folderRepo,
      accountEmail: accountEmail,
      folderName: folderName,
    );

    if (currentFolderId == null) {
      AppLogger.w(
        "⚠️ 계정 '$accountEmail'의 '$folderName' 폴더를 찾지 못했습니다.",
      );
    }

    _spreadsheetIdMap.clear();

    // 각 계정의 가계부 폴더에 들어 있는 스프레드시트를 모두 조회한다.
    for (final entry in _folderIdMap.entries) {
      final email = entry.key;
      final folderMap = entry.value;
      final accountSheetMap = <String, String>{};

      for (final folderEntry in folderMap.entries) {
        final targetFolderName = folderEntry.key;
        final folderId = folderEntry.value;

        try {
          final sheetMap = await sheetRepo.getSpreadsheetsInFolder(
            folderId: folderId,
          );

          accountSheetMap.addAll(sheetMap);

          AppLogger.i(
            "📊 [$email] '$targetFolderName' 폴더(ID: $folderId) 내 전체 시트: $sheetMap",
          );
        } catch (e) {
          AppLogger.e(
            "❌ [$email] '$targetFolderName' 폴더(ID: $folderId) 내 시트 조회 실패: $e",
          );
        }
      }

      _spreadsheetIdMap[email] = accountSheetMap;
    }

    AppLogger.i("📊 전체 가계부 스프레드시트 캐시 갱신 완료: $_spreadsheetIdMap");

    // 기존 기능 유지: 현재 로그인 계정의 연도별 시트만 별도 캐시한다.
    if (currentFolderId == null) {
      _yearToSpreadsheetIdMap.clear();
      return;
    }

    final yearSheets = await sheetRepo.getYearlySpreadsheets(
      folderId: currentFolderId,
      sheetName: folderName,
    );

    _yearToSpreadsheetIdMap.clear();
    _yearToSpreadsheetIdMap.addAll(yearSheets);

    AppLogger.i(
      "[$accountEmail / $folderName] 현재 계정 연도별 시트 캐시 완료: $_yearToSpreadsheetIdMap",
    );
  }

  /// 전체 계정의 폴더 ID 캐시 반환
  Map<String, Map<String, String>> get allFolderIds =>
      Map<String, Map<String, String>>.fromEntries(
        _folderIdMap.entries.map(
          (entry) => MapEntry(
            entry.key,
            Map<String, String>.from(entry.value),
          ),
        ),
      );

  /// 특정 연도의 현재 계정 시트 ID 가져오기
  String? getSpreadsheetId(int year) => _yearToSpreadsheetIdMap[year];

  /// 신규 생성된 현재 계정 연도 시트 ID 등록
  void registerSpreadsheetId(int year, String spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

  /// 전체 계정의 스프레드시트 캐시 반환
  Map<String, Map<String, String>> get allSpreadsheetIds =>
      Map<String, Map<String, String>>.fromEntries(
        _spreadsheetIdMap.entries.map(
          (entry) => MapEntry(
            entry.key,
            Map<String, String>.from(entry.value),
          ),
        ),
      );

  /// 특정 계정의 스프레드시트 목록 반환
  Map<String, String> getSpreadsheetsByAccount(String accountEmail) =>
      Map<String, String>.from(_spreadsheetIdMap[accountEmail] ?? {});

  /// 캐시된 전체 계정 이메일 목록 반환
  List<String> get cachedAccountEmails => _folderIdMap.keys.toList();

  /// 특정 계정의 가계부 폴더가 캐시에 있는지 확인
  bool hasFolderForAccount(
    String accountEmail, {
    String folderName = "가계부",
  }) {
    return _folderIdMap[accountEmail]?.containsKey(folderName) ?? false;
  }

  /// 특정 계정의 모든 폴더 맵 조회
  Map<String, String>? getFoldersByAccount(String accountEmail) =>
      _folderIdMap[accountEmail];

  /// 캐시 전체 초기화
  void clear() {
    _folderIdMap.clear();
    _yearToSpreadsheetIdMap.clear();
    _spreadsheetIdMap.clear();
  }

  /// 기존 UI 호출과의 호환성을 위한 캐시 초기화 메서드
  Future<void> clearCache() async {
    clear();
  }
}
