import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 📊 구글 드라이브 & 스프레드시트 관리 전담 서비스
// ============================================================================
class DriveSheetService {
  final drive.DriveApi _driveApi;

  DriveSheetService(this._driveApi);

  /// 1️⃣ 특정 폴더 내의 모든 시트 목록 조회 ({파일명 : 시트 ID})
  Future<Map<String, String>> getSpreadsheetsInFolder({
    required String folderId,
  }) async {
    final sheetMap = <String, String>{};
    final query =
        "'$folderId' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false";

    final fileList = await _driveApi.files.list(
      q: query,
      $fields: "files(id, name)",
    );

    if (fileList.files != null) {
      for (var file in fileList.files!) {
        if (file.name != null && file.id != null) {
          sheetMap[file.name!] = file.id!;
        }
      }
    }

    AppLogger.i("폴더(ID: $folderId) 내 시트 목록: $sheetMap");
    return sheetMap;
  }

  /// 2️⃣ 특정 폴더 내에서 연도 패턴이 맞는 시트 목록만 파싱하여 가져오기 ({연도 : 시트 ID})
  /// 예: '가계부_2024' -> 2024 : spreadsheetId
  Future<Map<int, String>> getYearlySpreadsheets({
    required String folderId,
    required String sheetName,
  }) async {
    final sheetMap = await getSpreadsheetsInFolder(folderId: folderId);
    final yearToIdMap = <int, String>{};

    final regExp = RegExp(RegExp.escape(sheetName) + r'_(\d{4})');

    sheetMap.forEach((fileName, fileId) {
      final match = regExp.firstMatch(fileName);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        yearToIdMap[year] = fileId;
      }
    });

    return yearToIdMap;
  }

  /// 3️⃣ 특정 스프레드시트(파일)를 특정 이메일 사용자와 공유
  Future<drive.Permission> shareSpreadsheet({
    required String spreadsheetId,
    required String email,
    String role = 'writer', // 기본값: 편집자 권한
    bool sendNotificationEmail = true,
  }) async {
    try {
      // 기존 공유 권한 목록 조회
      final permissionsList = await _driveApi.permissions.list(
        spreadsheetId,
        $fields: 'permissions(id, type, role, emailAddress)',
      );

      // 입력된 이메일과 일치하는 기존 권한 찾기
      drive.Permission? existingPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            existingPermission = p;
            break;
          }
        }
      }

      if (existingPermission != null) {
        if (existingPermission.role == role) {
          AppLogger.i('ℹ️ [$email] 사용자에게 이미 동일한 시트 권한($role)이 부여되어 있습니다.');
          return existingPermission;
        }

        AppLogger.i('🔄 [$email] 기존 시트 권한(${existingPermission.role})을 새 권한($role)으로 업데이트합니다.');
        final updatedPermission = drive.Permission()..role = role;

        final result = await _driveApi.permissions.update(
          updatedPermission,
          spreadsheetId,
          existingPermission.id!,
        );

        AppLogger.i('✅ 시트 권한 업데이트 성공: ${result.id} ($email -> $role)');
        return result;
      }

      AppLogger.i('➕ [$email] 새 스프레드시트 공유 권한($role)을 생성합니다.');
      final newPermission = drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email;

      final result = await _driveApi.permissions.create(
        newPermission,
        spreadsheetId,
        sendNotificationEmail: sendNotificationEmail,
      );

      AppLogger.i('✅ 성공적으로 스프레드시트가 공유되었습니다: ${result.id} ($email -> $role)');
      return result;
    } catch (e) {
      AppLogger.e('❌ 스프레드시트 공유 작업 실패: $e');
      rethrow;
    }
  }

  /// 4️⃣ 스프레드시트 삭제
  Future<void> deleteSpreadsheet(String spreadsheetId) async {
    AppLogger.i("  └ 🗑️ ID '$spreadsheetId' 스프레드시트를 삭제합니다...");
    try {
      await _driveApi.files.delete(spreadsheetId);
      AppLogger.i("  └ ✅ 스프레드시트 삭제 성공 (ID: $spreadsheetId)");
    } catch (e) {
      AppLogger.e("  └ ❌ 스프레드시트 삭제 실패 (ID: $spreadsheetId): $e");
      rethrow;
    }
  }

  /// 5️⃣ 특정 스프레드시트에서 특정 이메일 사용자의 공유 권한 제거
  Future<bool> removeSpreadsheetShare({
    required String spreadsheetId,
    required String email,
  }) async {
    try {
      final permissionsList = await _driveApi.permissions.list(
        spreadsheetId,
        $fields: 'permissions(id, emailAddress, role)',
      );

      drive.Permission? targetPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            targetPermission = p;
            break;
          }
        }
      }

      if (targetPermission != null && targetPermission.id != null) {
        try {
          await _driveApi.permissions.delete(
            spreadsheetId,
            targetPermission.id!,
          );
          AppLogger.i('🗑️ [$email] 사용자의 스프레드시트 공유 권한을 성공적으로 제거했습니다.');
          return true;
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 403 && e.message?.contains('inherited') == true) {
            AppLogger.i('⚠️ 상속된 권한이 감지되었습니다. 상위 폴더의 공유를 해제해야 합니다.');
            return false;
          }
          rethrow;
        }
      } else {
        AppLogger.i('ℹ️ [$email] 사용자는 해당 스프레드시트의 직접 공유 대상에 존재하지 않습니다.');
        return false;
      }
    } catch (e) {
      AppLogger.e('❌ 스프레드시트 공유 권한 제거 실패: $e');
      rethrow;
    }
  }

  /// 6️⃣ 특정 파일 또는 폴더에서 특정 이메일 사용자의 공유 권한 제거
  Future<bool> removeShare({
    required String fileOrFolderId,
    required String email,
  }) async {
    try {
      final permissionsList = await _driveApi.permissions.list(
        fileOrFolderId,
        $fields: 'permissions(id, emailAddress, role)',
      );

      drive.Permission? targetPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            targetPermission = p;
            break;
          }
        }
      }

      if (targetPermission != null && targetPermission.id != null) {
        try {
          await _driveApi.permissions.delete(
            fileOrFolderId,
            targetPermission.id!,
          );
          AppLogger.i('🗑️ [$email] 사용자의 공유 권한을 성공적으로 제거했습니다.');
          return true;
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 403 && e.message?.contains('inherited') == true) {
            AppLogger.i('⚠️ 상속된 권한이 감지되었습니다. 상위 폴더의 공유를 해제해야 파일 접근 권한이 해제됩니다.');
            return false;
          }
          rethrow;
        }
      } else {
        AppLogger.i('ℹ️ [$email] 사용자는 기존 공유 대상에 존재하지 않습니다.');
        return false;
      }
    } catch (e) {
      AppLogger.e('❌ 공유 권한 제거 실패: $e');
      rethrow;
    }
  }
}
