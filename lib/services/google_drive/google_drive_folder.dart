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
    if (folder?.id == null) return null;

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
    if (existingFolderId != null) return existingFolderId;
    return createFolder(folderName);
  }

  // ===========================================================================
  // Shared Folder
  // ===========================================================================

  /// 나에게 공유된 특정 이름의 폴더 목록 조회
  ///
  /// 현재 단계에서는 실제 결과를 변경하지 않고, 먼저 현재 Drive API 인증
  /// 범위에서 조회 가능한 전체 폴더를 로그로 확인한다.
  Future<Map<String, Map<String, String>>> getSharedFolders({
    required String folderName,
  }) async {
    final sharedFolderMap = <String, Map<String, String>>{};

    AppLogger.i("🔎 [공유 폴더 전체 진단 시작] '$folderName'");
    await _logAllVisibleFolders();

    final query = _buildSharedFolderQuery(folderName);
    AppLogger.i("🔎 [공유 폴더 검색 시작] 폴더명: '$folderName'");
    AppLogger.i('🔎 [공유 폴더 검색 Query] $query');

    try {
      final result = await _driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields:
            'files(id, name, mimeType, owners(emailAddress), sharingUser(emailAddress), driveId, parents, shared)',
        includeItemsFromAllDrives: true,
        supportsAllDrives: true,
      );

      final files = result.files ?? <drive.File>[];
      AppLogger.i('🔎 [sharedWithMe 검색 결과] 총 ${files.length}개');

      for (final file in files) {
        AppLogger.i(
          '   ├─ name=${file.name}, id=${file.id}, '
          'owners=${file.owners?.map((o) => o.emailAddress).toList()}, '
          'sharingUser=${file.sharingUser?.emailAddress}, '
          'driveId=${file.driveId}, shared=${file.shared}, parents=${file.parents}',
        );

        final folderId = file.id;
        final ownerEmail =
            file.owners?.firstOrNull?.emailAddress ??
            file.sharingUser?.emailAddress;

        if (folderId == null || ownerEmail == null) continue;

        final name = file.name ?? folderName;
        sharedFolderMap.putIfAbsent(ownerEmail, () => {})[name] = folderId;
      }

      AppLogger.i("📁 [공유 폴더 최종 결과] '$folderName': $sharedFolderMap");
      return sharedFolderMap;
    } catch (e, stackTrace) {
      AppLogger.e("❌ [공유 폴더 검색 실패] '$folderName': $e");
      AppLogger.e('❌ [공유 폴더 검색 StackTrace] $stackTrace');
      rethrow;
    }
  }

  /// 현재 인증된 Drive API 세션에서 조회 가능한 모든 폴더를 페이지 단위로
  /// 조회하여 로그에 남긴다. 실제 서비스 결과에는 영향을 주지 않는 진단용이다.
  Future<void> _logAllVisibleFolders() async {
    const query = "mimeType = 'application/vnd.google-apps.folder' and trashed = false";

    AppLogger.i('🔎 [전체 폴더 진단 Query] $query');
    AppLogger.i(
      '🔎 [전체 폴더 진단 옵션] corpora=user, spaces=drive, '
      'includeItemsFromAllDrives=true',
    );

    var pageToken;
    var page = 0;
    var total = 0;

    try {
      do {
        page++;
        final result = await _driveApi.files.list(
          q: query,
          corpora: 'user',
          spaces: 'drive',
          pageSize: 1000,
          pageToken: pageToken,
          includeItemsFromAllDrives: true,
          supportsAllDrives: true,
          $fields:
              'nextPageToken, incompleteSearch, files(id, name, mimeType, owners(emailAddress), sharingUser(emailAddress), driveId, parents, shared)',
        );

        final files = result.files ?? <drive.File>[];
        total += files.length;

        AppLogger.i(
          '🔎 [전체 폴더 진단 Page $page] ${files.length}개, '
          'incompleteSearch=${result.incompleteSearch}, '
          'nextPage=${result.nextPageToken != null}',
        );

        for (final file in files) {
          AppLogger.i(
            '   ├─ name=${file.name}, id=${file.id}, '
            'owners=${file.owners?.map((o) => o.emailAddress).toList()}, '
            'sharingUser=${file.sharingUser?.emailAddress}, '
            'driveId=${file.driveId}, shared=${file.shared}, parents=${file.parents}',
          );
        }

        pageToken = result.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      AppLogger.i('🔎 [전체 폴더 진단 완료] 총 ${total}개');
    } catch (e, stackTrace) {
      AppLogger.e('❌ [전체 폴더 진단 실패] $e');
      AppLogger.e('❌ [전체 폴더 진단 StackTrace] $stackTrace');
    }
  }

  // ===========================================================================
  // Permission
  // ===========================================================================

  /// 특정 이메일 사용자에게 폴더 공유
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
          AppLogger.i('ℹ️ [$email] 사용자에게 이미 동일한 폴더 권한($role)이 있습니다.');
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
        AppLogger.i('ℹ️ [$email] 사용자는 기존 폴더 공유 대상에 존재하지 않습니다.');
        return false;
      }

      await _driveApi.permissions.delete(folderId, permission!.id!);
      AppLogger.i('🗑️ [$email] 사용자의 폴더 공유 권한을 성공적으로 제거했습니다.');
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
  Future<Map<String, Map<String, String>>> getOrCreateFolder(
    String folderName,
  ) async {
    final userEmail = await getUserEmail();
    final folderId = await getOrCreateFolderId(folderName);
    return {userEmail: {folderName: folderId}};
  }

  /// 내 드라이브 폴더 + 공유받은 폴더 전체 조회
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

  String _buildMyFolderQuery(String folderName) {
    return "name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false '
        "and 'root' in parents";
  }

  String _buildSharedFolderQuery(String folderName) {
    return "sharedWithMe "
        "and name = '$folderName' "
        "and mimeType = '$_folderMimeType' "
        'and trashed = false';
  }

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

  Future<drive.Permission> _updatePermission({
    required String folderId,
    required String permissionId,
    required String email,
    required String role,
  }) async {
    AppLogger.i('🔄 [$email] 기존 폴더 권한을 $role 권한으로 업데이트합니다.');

    final result = await _driveApi.permissions.update(
      drive.Permission()..role = role,
      folderId,
      permissionId,
    );

    AppLogger.i('✅ 폴더 권한 업데이트 성공: ${result.id} ($email -> $role)');
    return result;
  }

  Future<drive.Permission> _createPermission({
    required String folderId,
    required String email,
    required String role,
    required bool sendNotificationEmail,
  }) async {
    AppLogger.i('➕ [$email] 새 폴더 공유 권한($role)을 생성합니다.');

    final result = await _driveApi.permissions.create(
      drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email,
      folderId,
      sendNotificationEmail: sendNotificationEmail,
    );

    AppLogger.i('✅ 폴더 공유 성공: ${result.id} ($email -> $role)');
    return result;
  }
}
