import 'package:flutter/material.dart';
import 'package:household_ledger/services/auth/app_account.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:household_ledger/services/auth/google_auth.dart';
import 'package:household_ledger/services/google_drive/google_drive_cache.dart';
import 'package:household_ledger/services/google_drive/google_drive_folder.dart';
import 'package:household_ledger/services/google_drive/google_drive_ledger_settings.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/ui/main_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingUI extends StatefulWidget {
  final AppAccount googleUser;
  final LedgerCacheManager cacheManager;
  final String currentSelectedEmail;
  final ValueChanged<String> onAccountChanged;

  const SettingUI({
    super.key,
    required this.googleUser,
    required this.cacheManager,
    required this.currentSelectedEmail,
    required this.onAccountChanged,
  });

  @override
  State<SettingUI> createState() => _SettingUIState();
}

class _SettingUIState extends State<SettingUI> {
  late String _selectedEmail;

  bool _isClearing = false;
  bool _isSharing = false;
  bool _isSigningOut = false;
  bool _isLoadingSharedAccounts = true;

  String? _removingSharedEmail;

  List<String> _sharedEmails = [];

  final GoogleAuthManager _authManager = GoogleAuthManager();

  @override
  void initState() {
    super.initState();

    _selectedEmail = widget.currentSelectedEmail;

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadSharedAccounts(),
    );
  }

  // ===========================================================================
  // 가계부 기준 계정
  // ===========================================================================

  /// 계정 선택 다이얼로그 표시
  Future<void> _showAccountSelectionDialog() async {
    try {
      final client = await _authManager.getClient();

      await widget.cacheManager.refreshAllFolderIds(
        DriveFolderService(
          drive.DriveApi(client),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      if (widget.cacheManager.cachedAccountEmails.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '가계부 폴더 목록을 불러오지 못했습니다: $e',
            ),
          ),
        );

        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '최신 목록을 불러오지 못해 기존 가계부 목록을 표시합니다.',
          ),
        ),
      );
    }

    if (!mounted) return;

    final List<String> availableEmails =
        widget.cacheManager.cachedAccountEmails;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            '가계부 기준 계정 선택',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...availableEmails.map(
                (email) {
                  final isMyAccount =
                      email == widget.googleUser.email;

                  final isSelected =
                      email == _selectedEmail;

                  final folderName =
                      widget.cacheManager
                              .getFoldersByAccount(email)?['가계부'] ??
                          '가계부';

                  return RadioListTile<String>(
                    title: Text(
                      isMyAccount
                          ? '$email (내 계정)'
                          : '$email (공유 계정)',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      '$folderName 폴더 기준',
                    ),
                    value: email,
                    groupValue: _selectedEmail,
                    onChanged: (String? value) async {
                      if (value == null) return;

                      setState(() {
                        _selectedEmail = value;
                      });

                      Navigator.pop(dialogContext);

                      try {
                        await _saveSelectedAccount(value);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            SnackBar(
                              content: Text(
                                '기준 계정 저장에 실패했습니다: $e',
                              ),
                            ),
                          );
                        }
                      }

                      widget.onAccountChanged(value);

                      if (!mounted) return;

                      ScaffoldMessenger.of(context)
                          .showSnackBar(
                        SnackBar(
                          content: Text(
                            '기준 계정이 $value (으)로 변경되었습니다.',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveSelectedAccount(
    String accountEmail,
  ) async {
    final ownerFolderId =
        widget.cacheManager
            .getFoldersByAccount(
              widget.googleUser.email,
            )?['가계부'];

    final selectedFolderId =
        widget.cacheManager
            .getFoldersByAccount(
              accountEmail,
            )?['가계부'];

    if (ownerFolderId == null ||
        selectedFolderId == null) {
      throw StateError(
        '저장할 가계부 폴더 정보를 찾지 못했습니다.',
      );
    }

    final client =
        await _authManager.getClient();

    await DriveLedgerSettingsService(
      drive.DriveApi(client),
    ).save(
      ownerFolderId: ownerFolderId,
      settings: LedgerDriveSettings(
        accountEmail: accountEmail,
        folderId: selectedFolderId,
      ),
    );
  }

  // ===========================================================================
  // 가계부 공유 관리
  // ===========================================================================

  /// 공유 관리 다이얼로그
  Future<void> _showShareManagementDialog() async {
    /*
     * 팝업을 열 때 최신 공유 목록 갱신
     */
    await _loadSharedAccounts(
      showErrorMessage: true,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            StateSetter setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                '가계부 공유 관리',
              ),

              content: SizedBox(
                width: double.maxFinite,
                child: _sharedEmails.isEmpty
                    ? const Padding(
                        padding:
                            EdgeInsets.symmetric(
                          vertical: 24,
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.group_off_outlined,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              '현재 공유 중인 계정이 없습니다.',
                              textAlign:
                                  TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount:
                            _sharedEmails.length,
                        separatorBuilder:
                            (_, __) =>
                                const Divider(
                          height: 1,
                        ),
                        itemBuilder:
                            (context, index) {
                          final email =
                              _sharedEmails[index];

                          final isRemoving =
                              _removingSharedEmail ==
                                  email;

                          return ListTile(
                            contentPadding:
                                EdgeInsets.zero,
                            leading: const Icon(
                              Icons
                                  .person_outline,
                            ),
                            title: Text(email),
                            subtitle:
                                const Text(
                              '편집 가능',
                            ),
                            trailing:
                                isRemoving
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth:
                                              2,
                                        ),
                                      )
                                    : IconButton(
                                        icon:
                                            const Icon(
                                          Icons
                                              .delete_outline,
                                        ),
                                        tooltip:
                                            '공유 해제',
                                        onPressed:
                                            _removingSharedEmail ==
                                                    null
                                                ? () async {
                                                    await _removeShare(
                                                      email,
                                                    );

                                                    if (!mounted) {
                                                      return;
                                                    }

                                                    setDialogState(
                                                      () {},
                                                    );
                                                  }
                                                : null,
                                      ),
                          );
                        },
                      ),
              ),

              actions: [
                TextButton.icon(
                  icon: const Icon(
                    Icons.person_add_alt_1,
                  ),
                  label:
                      const Text('공유하기'),
                  onPressed: _isSharing
                      ? null
                      : () async {
                          /*
                           * 관리 팝업을 닫고
                           * 이메일 입력 팝업을 표시
                           */
                          Navigator.pop(
                            dialogContext,
                          );

                          await _showShareEmailDialog();
                        },
                ),

                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 공유 이메일 입력
  Future<void> _showShareEmailDialog() async {
    final emailController =
        TextEditingController();

    final email =
        await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '가계부 공유',
          ),
          content: TextField(
            controller: emailController,
            keyboardType:
                TextInputType.emailAddress,
            autofocus: true,
            decoration:
                const InputDecoration(
              labelText: '공유할 이메일',
              hintText:
                  'example@gmail.com',
            ),
            onSubmitted: (value) {
              Navigator.pop(
                dialogContext,
                value.trim(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  emailController.text
                      .trim(),
                );
              },
              child: const Text('다음'),
            ),
          ],
        );
      },
    );

    emailController.dispose();

    if (email == null ||
        email.isEmpty) {
      return;
    }

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              '올바른 이메일 주소를 입력해 주세요.',
            ),
          ),
        );
      }

      return;
    }

    await _confirmAndShare(email);
  }

  /// 공유 확인 및 실행
  Future<void> _confirmAndShare(
    String email,
  ) async {
    final folderId =
        widget.cacheManager
            .getFoldersByAccount(
              widget.googleUser.email,
            )?['가계부'];

    if (folderId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            '공유할 가계부 폴더를 찾지 못했습니다.',
          ),
        ),
      );

      return;
    }

    try {
      final client =
          await _authManager.getClient();

      final driveApi =
          drive.DriveApi(client);

      final sheetRepo =
          DriveSheetService(driveApi);

      final spreadsheets =
          Map<String, String>.fromEntries(
        (await sheetRepo
                .getSpreadsheetsInFolder(
          folderId: folderId,
        ))
            .entries
            .where(
              (entry) => RegExp(
                r'^가계부_\d{4}$',
              ).hasMatch(entry.key),
            ),
      );

      if (!mounted) return;

      final approved =
          await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              '공유를 진행할까요?',
            ),
            content: Text(
              '$email 님에게 가계부 폴더와 '
              '그 안의 가계부 파일 '
              '${spreadsheets.length}개를 '
              '편집 가능으로 공유합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                },
                child: const Text('공유'),
              ),
            ],
          );
        },
      );

      if (approved != true ||
          !mounted) {
        return;
      }

      setState(() {
        _isSharing = true;
      });

      final folderRepo =
          DriveFolderService(driveApi);

      await folderRepo.shareFolder(
        folderId: folderId,
        email: email,
      );

      await Future.wait(
        spreadsheets.values.map(
          (spreadsheetId) =>
              sheetRepo.shareSpreadsheet(
            spreadsheetId:
                spreadsheetId,
            email: email,
          ),
        ),
      );

      await _loadSharedAccounts(
        showErrorMessage: false,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            '$email 님에게 가계부를 '
            '편집자로 공유했습니다.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '가계부 공유에 실패했습니다: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  /// 공유된 계정 목록 조회
  Future<void> _loadSharedAccounts({
    bool showErrorMessage = true,
  }) async {
    if (mounted) {
      setState(() {
        _isLoadingSharedAccounts = true;
      });
    }

    try {
      final client =
          await _authManager.getClient();

      final driveApi =
          drive.DriveApi(client);

      final folderRepo =
          DriveFolderService(driveApi);

      await widget.cacheManager
          .refreshAllFolderIds(
        folderRepo,
      );

      final folderId =
          widget.cacheManager
              .getFoldersByAccount(
                widget.googleUser.email,
              )?['가계부'];

      if (folderId == null) {
        throw StateError(
          '내 가계부 폴더를 찾지 못했습니다.',
        );
      }

      final emails =
          await folderRepo
              .getSharedFolderEmails(
        folderId,
      );

      if (mounted) {
        setState(() {
          _sharedEmails = emails;
        });
      }
    } catch (e) {
      if (mounted &&
          showErrorMessage) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '공유 대상 목록을 불러오지 못했습니다: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSharedAccounts =
              false;
        });
      }
    }
  }

  /// 공유 해제
  Future<void> _removeShare(
    String email,
  ) async {
    final approved =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '공유 해제',
          ),
          content: Text(
            '$email 님의 가계부 접근 권한을 '
            '해제할까요?\n'
            '파일은 삭제되지 않습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text('공유 해제'),
            ),
          ],
        );
      },
    );

    if (approved != true ||
        !mounted) {
      return;
    }

    setState(() {
      _removingSharedEmail = email;
    });

    try {
      final folderId =
          widget.cacheManager
              .getFoldersByAccount(
                widget.googleUser.email,
              )?['가계부'];

      if (folderId == null) {
        throw StateError(
          '내 가계부 폴더를 찾지 못했습니다.',
        );
      }

      final client =
          await _authManager.getClient();

      final driveApi =
          drive.DriveApi(client);

      final folderRepo =
          DriveFolderService(driveApi);

      final sheetRepo =
          DriveSheetService(driveApi);

      final spreadsheets =
          await sheetRepo
              .getSpreadsheetsInFolder(
        folderId: folderId,
      );

      await folderRepo
          .removeSharedFolder(
        folderId: folderId,
        email: email,
      );

      await Future.wait(
        spreadsheets.entries
            .where(
              (entry) => RegExp(
                r'^가계부_\d{4}$',
              ).hasMatch(entry.key),
            )
            .map(
              (entry) =>
                  sheetRepo
                      .removeSpreadsheetShare(
                spreadsheetId:
                    entry.value,
                email: email,
              ),
            ),
      );

      /*
       * API를 다시 조회하는 대신
       * 화면에서는 바로 제거
       */
      if (mounted) {
        setState(() {
          _sharedEmails.remove(email);
        });

        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '$email 님의 공유 권한을 '
              '해제했습니다.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '공유 해제에 실패했습니다: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _removingSharedEmail = null;
        });
      }
    }
  }

  // ===========================================================================
  // 캐시
  // ===========================================================================

  /// 로컬 캐시 데이터 초기화
  Future<void> _clearCache() async {
    setState(() {
      _isClearing = true;
    });

    try {
      await widget.cacheManager
          .clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              '로컬 캐시가 정상적으로 삭제되었습니다.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '캐시 삭제 중 오류 발생: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  // ===========================================================================
  // 로그아웃
  // ===========================================================================

  Future<void> _signOut() async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('로그아웃'),
          content: const Text(
            '현재 Google 계정에서 '
            '로그아웃하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text('로그아웃'),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await _authManager.signOut();

      final preferences =
          await SharedPreferences
              .getInstance();

      await preferences.setBool(
        'is_logged_in',
        false,
      );

      if (!mounted) return;

      Navigator.of(context)
          .pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) =>
              const MainUI(
            skipSessionRestore: true,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              '로그아웃에 실패했습니다: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isMyAccountSelected =
        _selectedEmail ==
            widget.googleUser.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),

      body: ListView(
        children: [
          // ================================================================
          // 구글 프로필
          // ================================================================

          UserAccountsDrawerHeader(
            accountName: Text(
              widget.googleUser
                      .displayName ??
                  '사용자',
            ),
            accountEmail: Text(
              widget.googleUser.email,
            ),
            currentAccountPicture:
                CircleAvatar(
              backgroundImage:
                  widget.googleUser
                              .photoUrl !=
                          null
                      ? NetworkImage(
                          widget.googleUser
                              .photoUrl!,
                        )
                      : null,
              child:
                  widget.googleUser
                              .photoUrl ==
                          null
                      ? const Icon(
                          Icons.person,
                          size: 40,
                        )
                      : null,
            ),
          ),

          // ================================================================
          // 가계부 기준 계정
          // ================================================================

          ListTile(
            leading: const Icon(
              Icons.folder_shared_outlined,
            ),
            title: const Text(
              '가계부 기준 계정',
            ),
            subtitle: Text(
              isMyAccountSelected
                  ? '$_selectedEmail (내 계정)'
                  : '$_selectedEmail (공유 계정)',
            ),
            trailing:
                const Icon(
              Icons.chevron_right,
            ),
            onTap:
                _showAccountSelectionDialog,
          ),

          const Divider(),

          // ================================================================
          // 가계부 공유 관리
          // ================================================================

          ListTile(
            leading: const Icon(
              Icons.group_outlined,
            ),
            title: const Text(
              '가계부 공유 관리',
            ),
            subtitle: Text(
              _isLoadingSharedAccounts
                  ? '공유 계정 확인 중...'
                  : _sharedEmails.isEmpty
                      ? '공유 중인 계정 없음'
                      : '${_sharedEmails.length}개 계정과 공유 중',
            ),
            trailing:
                _isLoadingSharedAccounts
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right,
                      ),
            onTap:
                _isLoadingSharedAccounts
                    ? null
                    : _showShareManagementDialog,
          ),

          const Divider(),

          // ================================================================
          // 로컬 캐시 초기화
          // ================================================================

          ListTile(
            leading: const Icon(
              Icons.cleaning_services,
              color: Colors.orange,
            ),
            title: const Text(
              '로컬 캐시 초기화',
            ),
            subtitle: const Text(
              '저장된 임시 데이터 및 캐시를 삭제합니다.',
            ),
            trailing: _isClearing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline,
                  ),
            onTap: _isClearing
                ? null
                : () {
                    showDialog(
                      context: context,
                      builder:
                          (dialogContext) {
                        return AlertDialog(
                          title:
                              const Text(
                            '캐시 삭제',
                          ),
                          content:
                              const Text(
                            '저장된 로컬 캐시 데이터를 '
                            '모두 삭제하시겠습니까?',
                          ),
                          actions: [
                            TextButton(
                              onPressed:
                                  () {
                                Navigator.pop(
                                  dialogContext,
                                );
                              },
                              child:
                                  const Text(
                                '취소',
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  () {
                                Navigator.pop(
                                  dialogContext,
                                );

                                _clearCache();
                              },
                              child:
                                  const Text(
                                '삭제',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.red,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
          ),

          const Divider(),

          // ================================================================
          // 로그아웃
          // ================================================================

          ListTile(
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
            ),
            title:
                const Text('로그아웃'),
            subtitle: const Text(
              '현재 Google 계정에서 로그아웃합니다.',
            ),
            trailing: _isSigningOut
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.chevron_right,
                  ),
            onTap: _isSigningOut
                ? null
                : _signOut,
          ),

          const Divider(),

          // ================================================================
          // 기타
          // ================================================================

          ListTile(
            leading: const Icon(
              Icons.notifications_none,
            ),
            title:
                const Text('알림 설정'),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {},
          ),

          ListTile(
            leading: const Icon(
              Icons.info_outline,
            ),
            title:
                const Text('앱 정보'),
            subtitle:
                const Text('버전 1.0.0'),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
