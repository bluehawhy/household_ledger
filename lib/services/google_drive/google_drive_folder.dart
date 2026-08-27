import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 구글 드라이브 폴더 조회 및 생성 전담 클래스
// ============================================================================
class DriveFolderService {
  final drive.DriveApi _driveApi;

  DriveFolderService(this._driveApi);

  /// 📧 현재 인증된 계정의 이메일 주소 조회
  Future<String> _getUserEmail() async {
    try {
      final about = await _driveApi.about.get($fields: 'user/emailAddress');
      return about.user?.emailAddress ?? 'me';
    } catch (e) {
      AppLogger.e("계정 이메일 정보를 가져오는 데 실패했습니다: $e");
      return 'me'; // 예외 시 fallback
    }
  }

  /// 특정 이름의 폴더 ID 조회
  Future<String?> getFolderId(String folderName) async {
    AppLogger.i("📁 '$folderName' 내 드라이브 폴더 확인 중...");
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and 'root' in parents";

    final result = await _driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final folderId = result.files!.first.id!;
      AppLogger.i("  └ 💡 기존 내 드라이브 폴더 사용 (폴더 ID: $folderId)");
      return folderId;
    }

    return null;
  }

  /// 신규 폴더 생성
  Future<String> createFolder(String folderName) async {
    AppLogger.i("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final createdFolder = await _driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return createdFolder.id!;
  }

  /// 폴더 삭제
  Future<void> deleteFolder(String folderId) async {
    AppLogger.i("  └ 🗑️ ID '$folderId' 폴더를 삭제합니다...");
    try {
      await _driveApi.files.delete(folderId);
      AppLogger.i("  └ ✅ 폴더 삭제 성공 (ID: $folderId)");
    } catch (e) {
      AppLogger.e("  └ ❌ 폴더 삭제 실패 (ID: $folderId): $e");
      rethrow;
    }
  }


  // ==========================================
  // 1. 폴더(Folder) 관련 공유 / 공유 해제
  // ==========================================

  /// 특정 폴더를 특정 이메일 사용자와 공유합니다.
  /// 
  /// - 이미 동일한 권한이 존재하는 경우: API 호출을 생략하고 기존 권한 객체를 반환합니다.
  /// - 권한 변경이 필요한 경우: [permissions.update]를 수행합니다.
  /// - 기존 권한이 없는 경우: [permissions.create]로 새로운 권한을 생성합니다.
  Future<drive.Permission> shareFolder({
    required String folderId,
    required String email,
    String role = 'writer', // 기본값: 편집자 권한
    bool sendNotificationEmail = true,
  }) async {
    try {
      // 1. 기존 공유 권한 목록 조회
      final permissionsList = await _driveApi.permissions.list(
        folderId,
        $fields: 'permissions(id, type, role, emailAddress)',
      );

      // 2. 입력된 이메일과 일치하는 기존 권한 찾기
      drive.Permission? existingPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            existingPermission = p;
            break;
          }
        }
      }

      // 3. 기존 권한 상태에 따른 조건부 처리
      if (existingPermission != null) {
        // CASE 3-1: 동일한 권한이 이미 존재 -> 생략
        if (existingPermission.role == role) {
          AppLogger.i('ℹ️ [$email] 사용자에게 이미 동일한 폴더 권한($role)이 부여되어 있습니다. 공유를 생략합니다.');
          return existingPermission;
        }

        // CASE 3-2: 권한 수준 변경 필요 -> update 호출
        AppLogger.i('🔄 [$email] 기존 폴더 권한(${existingPermission.role})을 새 권한($role)으로 업데이트합니다.');
        final updatedPermission = drive.Permission()..role = role;

        final result = await _driveApi.permissions.update(
          updatedPermission,
          folderId,
          existingPermission.id!,
        );

        AppLogger.i('✅ 폴더 권한 업데이트 성공: ${result.id} ($email -> $role)');
        return result;
      }

      // CASE 3-3: 기존 권한 없음 -> 새로 생성
      AppLogger.i('➕ [$email] 새 폴더 공유 권한($role)을 생성합니다.');
      final newPermission = drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email;

      final result = await _driveApi.permissions.create(
        newPermission,
        folderId,
        sendNotificationEmail: sendNotificationEmail,
      );

      AppLogger.i('✅ 성공적으로 폴더가 공유되었습니다: ${result.id} ($email -> $role)');
      return result;

    } catch (e) {
      AppLogger.i('❌ 폴더 공유 작업 실패: $e');
      rethrow;
    }
  }


  /// 나에게 공유된 폴더 목록 가져오기 (Map<계정 이메일, Map<폴더명, 폴더 ID>>)
  Future<Map<String, Map<String, String>>> getSharedFolders({
    required String folderName,
  }) async {
    final sharedFolderMap = <String, Map<String, String>>{};
    
    // 💡 내가 소유하지 않았고(not 'me' in owners), 이름이 일치하는 폴더 검색
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and not 'me' in owners";

    final result = await _driveApi.files.list(
      q: query,
      $fields: "files(id, name, owners/emailAddress, sharingUser/emailAddress)",
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );

    if (result.files != null && result.files!.isNotEmpty) {
      for (var file in result.files!) {
        final folderId = file.id;
        final fName = file.name ?? folderName;
        
        // 소유자 이메일 확인 (없다면 나에게 공유해 준 사람의 이메일 사용)
        final ownerEmail = file.owners?.firstOrNull?.emailAddress ?? 
                          file.sharingUser?.emailAddress;

        if (folderId != null && ownerEmail != null) {
          sharedFolderMap.putIfAbsent(ownerEmail, () => {})[fName] = folderId;
        }
      }
    }

    AppLogger.i("공유받은 '$folderName' 폴더 목록: $sharedFolderMap");
    return sharedFolderMap;
  }

  /// 특정 폴더에서 특정 이메일 사용자의 공유 권한을 제거합니다.
  Future<bool> removeFolderShare({
    required String folderId,
    required String email,
  }) async {
    try {
      // 1. 기존 공유 권한 목록 조회
      final permissionsList = await _driveApi.permissions.list(
        folderId,
        $fields: 'permissions(id, emailAddress, role)',
      );

      // 2. 삭제 대상 이메일에 해당하는 권한(Permission) 찾기
      drive.Permission? targetPermission;
      if (permissionsList.permissions != null) {
        for (final p in permissionsList.permissions!) {
          if (p.emailAddress?.toLowerCase() == email.toLowerCase()) {
            targetPermission = p;
            break;
          }
        }
      }

      // 3. 해당 권한이 존재하는 경우 삭제
      if (targetPermission != null && targetPermission.id != null) {
        await _driveApi.permissions.delete(
          folderId,
          targetPermission.id!,
        );
        AppLogger.i('🗑️ [$email] 사용자의 폴더 공유 권한을 성공적으로 제거했습니다.');
        return true;
      } else {
        AppLogger.i('ℹ️ [$email] 사용자는 기존 폴더 공유 대상에 존재하지 않습니다.');
        return false;
      }
    } catch (e) {
      AppLogger.i('❌ 폴더 공유 권한 제거 실패: $e');
      rethrow;
    }
  }


  /// 1️⃣ 폴더 조회 및 생성 통합 호출
  /// 반환값: Map<사용자_이메일, Map<폴더명, 폴더ID>>
  Future<Map<String, Map<String, String>>> getOrCreateFolder(String folderName) async {
    final userEmail = await _getUserEmail();

    // 1. 기존 폴더 조회
    String? folderId = await getFolderId(folderName);

    // 2. 없으면 새 폴더 생성
    if (folderId == null) {
      folderId = await createFolder(folderName);
    }

    return {
      userEmail: {folderName: folderId}
    };
  }

  /// 3️⃣ 내 드라이브 폴더 + 공유 폴더 전체 조회 기능
  /// 반환값: Map<소유자 이메일('me' 또는 실제 이메일), Map<폴더명, 폴더ID>>
  Future<Map<String, Map<String, String>>> getAllTargetFolders({
    required String folderName,
  }) async {
    final Map<String, Map<String, String>> resultMap = {};

    // 1. 내 드라이브 폴더 Map 가져와서 추가
    final myFolderMap = await getOrCreateFolder(folderName);
    resultMap.addAll(myFolderMap);

    // 2. 공유받은 폴더 Map 가져와서 추가
    final sharedFolderMap = await getSharedFolders(folderName: folderName);
    resultMap.addAll(sharedFolderMap);

    return resultMap;
  }


}