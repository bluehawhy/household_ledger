import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

/// Google Drive 폴더 조회 / 생성 / 공유 관리 서비스
class DriveFolderService {
  static const _folderMimeType = 'application/vnd.google-apps.folder';

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
      AppLogger.e('계정 이메일 정보를 가져오는 데 실패했습니다: $e');
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
      '  └ 💡 기존 내 드라이브 폴더 사용 (폴더 ID: ${folder!.id})',
    );

    return folder.id;
  }

  /// 신규 폴더 생성
  Future<String> createFolder(String folderName) async {
    AppLogger.i("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");

    final createdFolder = await _driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = _folderMimeType,
    );

    final folderId = createdFolder.id;

    if (folderId == null) {
      throw Exception("폴더 '$folderName' 생성에는 성공했지만 ID를 받지 못했습니다.");
    }

    AppLogger.i('  └ ✅ 폴더 생성 성공 (폴더 ID: $folderId)');
    return folderId;
  }

  /// 폴더 삭제
  Future<void> deleteFolder(String folderId) async {
    try {
      AppLogger.i("  └ 🗑️ ID '$folderId' 폴더를 삭제합니다...");
      await _driveApi.files.delete(folderId);
      AppLogger.i('  └ ✅ 폴더 삭제 성공 (ID: $folderId)');
    } catch (e) {
      AppLogger.e('  └ ❌ 폴더 삭제 실패 (ID: $folderId): $e');
      rethrow;
    }
  }

  /// 폴더가 있으면 조회하고 없으면 생성
  Future<String> getOrCreateFolderId(String folderName) async {
    final existingFolderId = await getFolderId(folderName);

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
  /// Drive API의 `sharedWithMe` 조건을 사용하여
  /// 현재 로그인 계정의 '나에게 공유됨' 컬렉션에서 검색한다.
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
    final sharedFolderMap = <String, Map<String, String>>{};
    final query = _buildSharedFolderQuery(folderName);

    AppLogger.i("🔎 [공유 폴더 검색 시작] 폴더명: '$folderName'");
    AppLogger.i('🔎 [공유 폴더 검색 Query] $query');
    AppLogger.i(
      '🔎 [공유 폴더 검색 옵션] spaces=drive, sharedWithMe=true',
    );

    try {
      final result = await _driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields:
            'files(id, name, mimeType, owners/emailAddress, sharingUser/emailAddress)',
      );

      final files = result.files ?? <drive.File>[];

      AppLogger.i('🔎 [sharedWithMe 검색 결과] 총 ${files.length}개');

      if (files.isEmpty) {
        AppLogger.w(
          "⚠️ [sharedWithMe 검색 결과 없음] '$folderName' 폴더를 찾지 못했습니다.",
        );

        // 공유된 폴더 자체가 검색되는지 확인하기 위한 진단 검색.
        final diagnosticQuery = _buildSharedFolderDiagnosticQuery();
        AppLogger.i('🔎 [공유 폴더 진단 Query] $diagnosticQuery');

        final diagnosticResult = await _driveApi.files.list(
          q: diagnosticQuery,
          spaces: 'drive',
          $fields:
              'files(id, name, mimeType, owners/emailAddress, sharingUser/emailAddress)',
        );

        final diagnosticFiles = diagnosticResult.files ?? <drive.File>[];
        AppLogger.i(
          '🔎 [sharedWithMe 전체 폴더 진단 결과] 총 ${diagnosticFiles.length}개',
        );

        for (final file in diagnosticFiles) {
          AppLogger.i(
            '   ├─ name=${file.name}, id=${file.id}, '
            'mimeType=${file.mimeType}, '
            'owners=${file.owners?.map((owner) => owner.emailAddress).toList()}, '
            'sharingUser=${file.sharingUser?.emailAddress}',
          );
        }
      } else {
        for (final file in files) {
          AppLogger.i(
            '   ├─ 검색 파일: name=${file.name}, id=${file.id}, '
            'mimeType=${file.mimeType}, '
            'owners=${file.owners?.map((owner) => owner.emailAddress).toList()}, '
            'sharingUser=${file.sharingUser?.emailAddress}',
          );
        }
      }

      for (final file in files) {
        final folderId = file.id;

        final ownerEmail =
            file.owners?.firstOrNull?.emailAddress ??
            file.sharingUser?.emailAddress;

        if (folderId == null || ownerEmail == null) {
          AppLogger.w(
            '   └ ⚠️ 공유 폴더 결과에서 ID 또는 소유자 이메일을 확인할 수 없습니다: '
            'name=${file.name}, id=$folderId, '
            'owners=${file.owners?.map((owner) => owner.emailAddress).toList()}, '
            'sharingUser=${file.sharingUser?.emailAddress}',
          );
          continue;
        }

        final name = file.name ?? folderName;

        sharedFolderMap
            .putIfAbsent(ownerEmail, () => {})[name] = folderId;
      }

      AppLogger.i("📁 [공유 폴더 최종 결과] '$folderName': $sharedFolderMap");
      return sharedFolderMap;
    } catch (e, stackTrace) {
      AppLogger.e("❌ [공유 폴더 검색 실패] '$folderName': $e");
      AppLogger.e('❌ [공유 폴더 검색 StackTrace] $stackTrace');
      rethrow;
    }
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
      final existingPermission = await _findPermissionByEmail(
        folderId: folderId,
        email: email,
      );

      if (existingPermission != null) {
        if (existingPermission.role == role) {
          AppLogger.i(
            'ℹ️ [$email] 사용자에게 이미 동일한 폴더 권한($role)이 있습니다.',
          );
          return existingPermission;
        }

        return _updatePermission(
          folderId: folderId,
          permissionId: existingPermission.id!,
          email: email,
          role: role,
        );
      }

      return _createPermission(
        folderId: folderId,
        email: email,
        role: role,
        sendNotificationEmail: sendNotificationEmail,
      );
    } catch (e) {
      AppLogger.e('❌ 폴더 공유 작업 실패: $e');
      rethrow;
    }
  }

  /// 특정 이메일 사용자의 폴더 공유 권한 제거
  Future<bool> removeSharedFolder({
    required String folderId,
    required String email,
  }) async {
    try {
      final permission = await _findPermissionByEmail(
        folderId: folderId,
        email: email,
      );

      if (permission?.id == null) {
        AppLogger.i(
          'ℹ️ [$email] 사용자는 기존 폴더 공유 대상에 존재하지 않습니다.',
        );
        return false;
      }

      await _driveApi.permissions.delete(folderId, permission!.id!);

      AppLogger.i(
        '🗑️ [$email] 사용자의 폴더 공유 권한을 성공적으로 제거했습니다.',
      );
      return true;
    } catch (e) {
      AppLogger.e('❌ 폴더 공유 권한 제거 실패: $e');
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
  Future<Map<String, Map<String, String>>> getOrCreateFolder(
    String folderName,
  ) async {
    final userEmail = await getUserEmail();
    final folderId = await getOrCreateFolderId(folderName);

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
  Future<Map<String, Map<String, String>>> getAllTargetFolders({
    required String folderName,
  }) async {
    AppLogger.i("📁 [전체 가계부 폴더 검색 시작] '$folderName'");

    final resultMap = <String, Map<String, String>>{};

    final myFolderMap = await getOrCreateFolder(folderName);
    AppLogger.i('📁 [내 드라이브 폴더 검색 결과] $myFolderMap');

    final sharedFolderMap = await getSharedFolders(folderName: folderName);
    AppLogger.i('📁 [공유 폴더 검색 결과] $sharedFolderMap');

    resultMap.addAll(myFolderMap);
    resultMap.addAll(sharedFolderMap);

    AppLogger.i('📁 [전체 가계부 폴더 최종 결과] $resultMap');
    return resultMap;
  }

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  /// 내 Drive Root의 폴더 검색 Query
  String _buildMyFolderQuery(String folderName) {
    return "name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false '
        "and 'root' in parents";
  }

  /// 나에게 공유된 폴더 검색 Query
  ///
  /// Google Drive API에서 sharedWithMe는 현재 로그인 사용자에게
  /// 공유된 파일/폴더를 명시적으로 검색할 수 있는 조건이다.
  String _buildSharedFolderQuery(String folderName) {
    return "sharedWithMe "
        "and name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false';
  }

  /// 나에게 공유된 폴더 전체를 조회하는 진단용 Query
  String _buildSharedFolderDiagnosticQuery() {
    return "sharedWithMe "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false';
  }

  /// 이메일로 기존 Permission 조회
  Future<drive.Permission?> _findPermissionByEmail({
    required String folderId,
    required String email,
  }) async {
    final permissionsList = await _driveApi.permissions.list(
      folderId,
      $fields: 'permissions(id, type, role, emailAddress)',
    );

    final targetEmail = email.toLowerCase();

    for (final permission in permissionsList.permissions ?? []) {
      if (permission.emailAddress?.toLowerCase() == targetEmail) {
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
      '🔄 [$email] 기존 폴더 권한을 $role 권한으로 업데이트합니다.',
    );

    final result = await _driveApi.permissions.update(
      drive.Permission()..role = role,
      folderId,
      permissionId,
    );

    AppLogger.i(
      '✅ 폴더 권한 업데이트 성공: ${result.id} ($email -> $role)',
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

    final result = await _driveApi.permissions.create(
      drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email,
      folderId,
      sendNotificationEmail: sendNotificationEmail,
    );

    AppLogger.i(
      '✅ 폴더 공유 성공: ${result.id} ($email -> $role)',
    );

    return result;
  }
}
