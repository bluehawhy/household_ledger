import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 구글 드라이브 폴더 조회 및 생성 전담 클래스
// ============================================================================
class DriveFolderRepository {
  final drive.DriveApi _driveApi;

  DriveFolderRepository(this._driveApi);

  /// 1️⃣ 내 드라이브에 특정 이름의 폴더가 있는지 확인하고, 없으면 생성 후 ID 반환
  Future<String> getOrCreateFolder(String folderName) async {
    AppLogger.i("📁 '$folderName' 내 드라이브 폴더 확인 중...");
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and 'root' in parents";

    final result = await _driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      AppLogger.i("  └ 💡 기존 내 드라이브 폴더 사용 (폴더 ID: $id)");
      return id;
    }

    AppLogger.i("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final createdFolder = await _driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return createdFolder.id!;
  }

  /// 2️⃣ 나에게 공유된 폴더 목록 가져오기 (Map<계정 이메일, 폴더 ID>)
  Future<Map<String, String>> getSharedFolders({
    required String folderName,
  }) async {
    final sharedFolderMap = <String, String>{};
    
    // 💡 내가 소유하지 않았고(not 'me' in owners), 이름이 일치하는 폴더 검색
    // sharedWithMe = true 단독 조건보다 더 폭넓게 공유된 폴더를 잡아냅니다.
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false and not 'me' in owners";

    final result = await _driveApi.files.list(
      q: query,
      $fields: "files(id, name, owners/emailAddress, sharingUser/emailAddress)",
      // 💡 공유된 파일/폴더 검색을 위한 필수 옵션 추가
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );

    if (result.files != null && result.files!.isNotEmpty) {
      for (var file in result.files!) {
        final folderId = file.id;
        
        // 소유자 이메일 확인 (없다면 나에게 공유해 준 사람의 이메일 사용)
        final ownerEmail = file.owners?.firstOrNull?.emailAddress ?? 
                           file.sharingUser?.emailAddress;

        if (folderId != null && ownerEmail != null) {
          sharedFolderMap[ownerEmail] = folderId;
        }
      }
    }

    AppLogger.i("공유받은 '$folderName' 폴더 목록: $sharedFolderMap");
    return sharedFolderMap;
  }
 
 
   /// 3️⃣ 내 드라이브 폴더 + 공유 폴더 전체 조회 기능
  /// 반환값: Map<소유자 이메일('me' 또는 실제 이메일), Map<폴더명, 폴더ID>>
  Future<Map<String, Map<String, String>>> getAllTargetFolders({
    required String folderName,
  }) async {
    final Map<String, Map<String, String>> resultMap = {};

    // 1. 내 드라이브 폴더 가져오기 (없으면 생성)
    final myFolderId = await getOrCreateFolder(folderName);
    resultMap['me'] = {folderName: myFolderId};

    // 2. 공유받은 폴더 가져오기
    final sharedFolders = await getSharedFolders(folderName: folderName);
    sharedFolders.forEach((email, folderId) {
      resultMap.putIfAbsent(email, () => {})[folderName] = folderId;
    });

    return resultMap;
  }
}