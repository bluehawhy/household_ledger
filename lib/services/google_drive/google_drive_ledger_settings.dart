import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;

class LedgerDriveSettings {
  final String accountEmail;
  final String folderId;

  const LedgerDriveSettings({
    required this.accountEmail,
    required this.folderId,
  });

  Map<String, String> toJson() => {
        'accountEmail': accountEmail,
        'folderId': folderId,
      };

  static LedgerDriveSettings? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final accountEmail = value['accountEmail'];
    final folderId = value['folderId'];
    if (accountEmail is! String || folderId is! String) return null;
    if (accountEmail.isEmpty || folderId.isEmpty) return null;
    return LedgerDriveSettings(accountEmail: accountEmail, folderId: folderId);
  }
}

/// 내 가계부 폴더에 기준 계정 설정을 JSON 파일로 보관한다.
class DriveLedgerSettingsService {
  static const _fileName = 'household_ledger_settings.json';
  static const _mimeType = 'application/json';

  final drive.DriveApi _driveApi;

  DriveLedgerSettingsService(this._driveApi);

  Future<LedgerDriveSettings?> load({required String ownerFolderId}) async {
    final file = await _findSettingsFile(ownerFolderId);
    if (file?.id == null) return null;

    final response = await _driveApi.files.get(
      file!.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) return null;

    final content = await response.stream.transform(utf8.decoder).join();
    return LedgerDriveSettings.fromJson(jsonDecode(content));
  }

  Future<void> save({
    required String ownerFolderId,
    required LedgerDriveSettings settings,
  }) async {
    final content = jsonEncode(settings.toJson());
    final media = drive.Media(
      Stream<List<int>>.value(utf8.encode(content)),
      content.length,
      contentType: _mimeType,
    );
    final existingFile = await _findSettingsFile(ownerFolderId);

    if (existingFile?.id != null) {
      await _driveApi.files.update(
        drive.File()..mimeType = _mimeType,
        existingFile!.id!,
        uploadMedia: media,
      );
      return;
    }

    await _driveApi.files.create(
      drive.File()
        ..name = _fileName
        ..mimeType = _mimeType
        ..parents = [ownerFolderId],
      uploadMedia: media,
    );
  }

  Future<drive.File?> _findSettingsFile(String ownerFolderId) async {
    final result = await _driveApi.files.list(
      q: "'$ownerFolderId' in parents and name = '$_fileName' and trashed = false",
      spaces: 'drive',
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id, name)',
    );
    return result.files?.firstOrNull;
  }
}
