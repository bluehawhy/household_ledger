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
    AppLogger.i("📁 '$folderName' 폴더 확인 중...");
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    
    final result = await _driveApi.files.list(q: query);

    if (result.files != null && result.files!.isNotEmpty) {
      final id = result.files!.first.id!;
      AppLogger.i("  └ 💡 기존 폴더 사용 (폴더 ID: $id)");
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
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and sharedWithMe = true and trashed = false";

    final result = await _driveApi.files.list(
      q: query,
      $fields: "files(id, name, owners/emailAddress)",
    );

    if (result.files != null && result.files!.isNotEmpty) {
      for (var file in result.files!) {
        final folderId = file.id;
        final ownerEmail = file.owners?.firstOrNull?.emailAddress;

        if (folderId != null && ownerEmail != null) {
          sharedFolderMap[ownerEmail] = folderId;
        }
      }
    }

    AppLogger.i("공유받은 '$folderName' 폴더 목록: $sharedFolderMap");
    return sharedFolderMap;
  }
}
