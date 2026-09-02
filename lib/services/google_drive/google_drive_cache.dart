import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 가계부 관련 Google Drive/Spreadsheet ID 캐시를 관리합니다.
// ============================================================================
class LedgerCacheManager {
  final Map<String, String?> _folderIdMap = {};
  final Map<int, String?> _yearToSpreadsheetIdMap = {};

  String? getFolderId(String folderName) => _folderIdMap[folderName];

  void setFolderId(String folderName, String? folderId) {
    _folderIdMap[folderName] = folderId;
  }

  String? getSpreadsheetId(int year) => _yearToSpreadsheetIdMap[year];

  void setSpreadsheetId(int year, String? spreadsheetId) {
    _yearToSpreadsheetIdMap[year] = spreadsheetId;
  }

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
