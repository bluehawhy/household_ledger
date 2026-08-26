import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/utils/app_logger.dart';

// ============================================================================
/// 구글 드라이브 폴더 조회 및 생성 전담 클래스
// ============================================================================
class DriveFolderRepository {
  final drive.DriveApi _driveApi;

  DriveFolderRepository(this._driveApi);

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

  /// 🔍 2️⃣ 특정 이름의 폴더 ID 조회
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

  /// ➕ 3️⃣ 신규 폴더 생성
  Future<String> createFolder(String folderName) async {
    AppLogger.i("  └ ➕ '$folderName' 폴더가 없어 새로 생성합니다...");
    final createdFolder = await _driveApi.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return createdFolder.id!;
  }

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

  /// 2️⃣ 나에게 공유된 폴더 목록 가져오기 (Map<계정 이메일, Map<폴더명, 폴더 ID>>)
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