import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

/// Google Drive 폴더 조회 / 생성 / 공유 관리 서비스
class DriveFolderService {
  static const _folderMimeType =
      'application/vnd.google-apps.folder';

  final drive.DriveApi _driveApi;

  DriveFolderService(this._driveApi);

  // ===========================================================================
  // Account
  // ===========================================================================

  /// 현재 인증된 Google 계정 이메일 조회
  Future<String> getUserEmail() async {
    try {
      final about = await _driveApi.about.get(
        $fields: 'user/emailAddress',
      );

      return about.user?.emailAddress ?? 'me';
    } catch (e) {
      AppLogger.e(
        '계정 이메일 정보를 가져오는 데 실패했습니다: $e',
      );

      return 'me';
    }
  }

  // ===========================================================================
  // Folder
  // ===========================================================================

  /// 내 드라이브 Root에서 특정 이름의 폴더 ID 조회
  Future<String?> getFolderId(String folderName) async {
    AppLogger.i("📁 '$folderName' 내 드라이브 폴더 확인 중...");

    final result = await _driveApi.files.list(
      q: _buildMyFolderQuery(folderName),
      $fields: 'files(id, name)',
    );

    final folder = result.files?.firstOrNull;

    if (folder?.id == null) {
      return null;
    }

    AppLogger.i(
      '  └ 💡 기존 내 드라이브 폴더 사용 '
      '(폴더 ID: ${folder!.id})',
    );

    return folder.id;
  }

  /// 신규 폴더 생성
  Future<String> createFolder(String folderName) async {
    AppLogger.i(
      "  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...",
    );

    final createdFolder = await _driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = _folderMimeType,
    );

    final folderId = createdFolder.id;

    if (folderId == null) {
      throw Exception(
        "폴더 '$folderName' 생성에는 성공했지만 ID를 받지 못했습니다.",
      );
    }

    AppLogger.i(
      '  └ ✅ 폴더 생성 성공 (ID: $folderId)',
    );

    return folderId;
  }

  /// 폴더 삭제
  Future<void> deleteFolder(String folderId) async {
    try {
      AppLogger.i(
        "  └ 🗑️ ID '$folderId' 폴더를 삭제합니다...",
      );

      await _driveApi.files.delete(folderId);

      AppLogger.i(
        '  └ ✅ 폴더 삭제 성공 (ID: $folderId)',
      );
    } catch (e) {
      AppLogger.e(
        '  └ ❌ 폴더 삭제 실패 (ID: $folderId): $e',
      );

      rethrow;
    }
  }

  /// 폴더가 있으면 조회하고 없으면 생성
  Future<String> getOrCreateFolderId(
    String folderName,
  ) async {
    final existingFolderId =
        await getFolderId(folderName);

    if (existingFolderId != null) {
      return existingFolderId;
    }

    return createFolder(folderName);
  }

  // ===========================================================================
  // Shared Folder
  // ===========================================================================

  /// 나에게 공유된 특정 이름의 폴더 목록 조회
  ///
  /// 반환:
  /// {
  ///   ownerEmail: {
  ///     folderName: folderId
  ///   }
  /// }
  Future<Map<String, Map<String, String>>> getSharedFolders({
    required String folderName,
  }) async {
    final sharedFolderMap =
        <String, Map<String, String>>{};

    final result = await _driveApi.files.list(
      q: _buildSharedFolderQuery(folderName),
      $fields:
          'files(id, name, owners/emailAddress, sharingUser/emailAddress)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );

    for (final file in result.files ?? []) {
      final folderId = file.id;

      final ownerEmail =
          file.owners?.firstOrNull?.emailAddress ??
          file.sharingUser?.emailAddress;

      if (folderId == null || ownerEmail == null) {
        continue;
      }

      final name = file.name ?? folderName;

      sharedFolderMap
          .putIfAbsent(ownerEmail, () => {})
          [name] = folderId;
    }

    AppLogger.i(
      "공유받은 '$folderName' 폴더 목록: $sharedFolderMap",
    );

    return sharedFolderMap;
  }

  // ===========================================================================
  // Permission
  // ===========================================================================

  /// 특정 이메일 사용자에게 폴더 공유
  ///
  /// 이미 동일한 권한이 있으면 API 변경 없이 기존 권한 반환.
  /// 권한이 다르면 update.
  /// 권한이 없으면 create.
  Future<drive.Permission> shareFolder({
    required String folderId,
    required String email,
    String role = 'writer',
    bool sendNotificationEmail = true,
  }) async {
    try {
      final existingPermission =
          await _findPermissionByEmail(
        folderId: folderId,
        email: email,
      );

      // 이미 권한 존재
      if (existingPermission != null) {
        // 동일 권한
        if (existingPermission.role == role) {
          AppLogger.i(
            'ℹ️ [$email] 사용자에게 이미 '
            '동일한 폴더 권한($role)이 있습니다.',
          );

          return existingPermission;
        }

        // 권한 변경
        return _updatePermission(
          folderId: folderId,
          permissionId: existingPermission.id!,
          email: email,
          role: role,
        );
      }

      // 새 권한 생성
      return _createPermission(
        folderId: folderId,
        email: email,
        role: role,
        sendNotificationEmail:
            sendNotificationEmail,
      );
    } catch (e) {
      AppLogger.e(
        '❌ 폴더 공유 작업 실패: $e',
      );

      rethrow;
    }
  }

  /// 특정 이메일 사용자의 폴더 공유 권한 제거
  Future<bool> removeSharedFolder({
    required String folderId,
    required String email,
  }) async {
    try {
      final permission =
          await _findPermissionByEmail(
        folderId: folderId,
        email: email,
      );

      if (permission?.id == null) {
        AppLogger.i(
          'ℹ️ [$email] 사용자는 '
          '기존 폴더 공유 대상에 존재하지 않습니다.',
        );

        return false;
      }

      await _driveApi.permissions.delete(
        folderId,
        permission!.id!,
      );

      AppLogger.i(
        '🗑️ [$email] 사용자의 '
        '폴더 공유 권한을 성공적으로 제거했습니다.',
      );

      return true;
    } catch (e) {
      AppLogger.e(
        '❌ 폴더 공유 권한 제거 실패: $e',
      );

      rethrow;
    }
  }

  // ===========================================================================
  // Combined / High-level API
  // ===========================================================================

  /// 내 폴더 조회 또는 생성
  ///
  /// 반환:
  /// {
  ///   userEmail: {
  ///     folderName: folderId
  ///   }
  /// }
  Future<Map<String, Map<String, String>>>
      getOrCreateFolder(
    String folderName,
  ) async {
    final userEmail = await getUserEmail();

    final folderId =
        await getOrCreateFolderId(folderName);

    return {
      userEmail: {
        folderName: folderId,
      },
    };
  }

  /// 내 드라이브 폴더 + 공유받은 폴더 전체 조회
  ///
  /// 반환:
  /// {
  ///   ownerEmail: {
  ///     folderName: folderId
  ///   }
  /// }
  Future<Map<String, Map<String, String>>>
      getAllTargetFolders({
    required String folderName,
  }) async {
    final resultMap =
        <String, Map<String, String>>{};

    final myFolderMap =
        await getOrCreateFolder(folderName);

    final sharedFolderMap =
        await getSharedFolders(
      folderName: folderName,
    );

    resultMap.addAll(myFolderMap);
    resultMap.addAll(sharedFolderMap);

    return resultMap;
  }

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  /// 내 Drive Root의 폴더 검색 Query
  String _buildMyFolderQuery(
    String folderName,
  ) {
    return "name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false '
        "and 'root' in parents";
  }

  /// 공유받은 폴더 검색 Query
  String _buildSharedFolderQuery(
    String folderName,
  ) {
    return "name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false '
        "and not 'me' in owners";
  }

  /// 이메일로 기존 Permission 조회
  Future<drive.Permission?>
      _findPermissionByEmail({
    required String folderId,
    required String email,
  }) async {
    final permissionsList =
        await _driveApi.permissions.list(
      folderId,
      $fields:
          'permissions(id, type, role, emailAddress)',
    );

    final targetEmail = email.toLowerCase();

    for (final permission
        in permissionsList.permissions ?? []) {
      if (permission.emailAddress
              ?.toLowerCase() ==
          targetEmail) {
        return permission;
      }
    }

    return null;
  }

  /// 기존 Permission 권한 변경
  Future<drive.Permission> _updatePermission({
    required String folderId,
    required String permissionId,
    required String email,
    required String role,
  }) async {
    AppLogger.i(
      '🔄 [$email] 기존 폴더 권한을 '
      '$role 권한으로 업데이트합니다.',
    );

    final result =
        await _driveApi.permissions.update(
      drive.Permission()..role = role,
      folderId,
      permissionId,
    );

    AppLogger.i(
      '✅ 폴더 권한 업데이트 성공: '
      '${result.id} ($email -> $role)',
    );

    return result;
  }

  /// 새 Permission 생성
  Future<drive.Permission> _createPermission({
    required String folderId,
    required String email,
    required String role,
    required bool sendNotificationEmail,
  }) async {
    AppLogger.i(
      '➕ [$email] 새 폴더 공유 권한($role)을 생성합니다.',
    );

    final result =
        await _driveApi.permissions.create(
      drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email,
      folderId,
      sendNotificationEmail:
          sendNotificationEmail,
    );

    AppLogger.i(
      '✅ 폴더 공유 성공: '
      '${result.id} ($email -> $role)',
    );

    return result;
  }
}