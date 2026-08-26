import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/google_drive/google_drive_spreadsheet.dart';
import 'package:household_ledger/services/utils/app_logger.dart';

/// 파싱 및 시트 데이터 추가 결과 상태
enum ParseResult {
  success,   // 성공적으로 추가됨
  duplicate, // 중복 데이터로 확인되어 스킵됨
  fail,      // 비어있거나 파싱/API 통신 에러 등 실패
}

/// 단일 입력을 Google Sheets에 전송하는 입력 서비스
class SingleEntryService {
  final LedgerDataService sheetService = LedgerDataService();

  Future<ParseResult> appendParseSingleLine(
    AuthClient authClient,
    sheets.SheetsApi sheetsApi,
    Map<String, dynamic> itemMap,
  ) async {
    if (itemMap.isEmpty) {
      return ParseResult.fail;
    }

    try {
      final LedgerItem item = LedgerItem.fromMap(itemMap);
      final int year = item.date.year;
      final String sheetName = "${item.date.month}월";

      // 💡 setupLedgerSpreadsheetForYear 호출로 캐시 확인 및 생성/가져오기 동시 처리
      final String? spreadsheetId = await sheetService.sheetSetupService
          .setupLedgerSpreadsheetForYear(authClient, year);

      // Null Safety Check: 시트 ID를 가져올 수 없으면 실패 처리
      if (spreadsheetId == null) {
        AppLogger.i("⚠️ [$year년] 시트를 찾을 수 없거나 생성하지 못했습니다.");
        return ParseResult.fail;
      }

      List<List<dynamic>> existingRows = [];
      try {
        final response = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          "'$sheetName'!A1:Z1000",
        );
        existingRows = response.values ?? [];
      } catch (e) {
        AppLogger.i("⚠️ [$year년 $sheetName] 시트 읽기 실패 (신규 시트 또는 데이터 없음): $e");
      }

      final bool isAppended = await sheetService.appendTransactionData(
        sheetsApi,
        spreadsheetId,
        sheetName,
        existingRows,
        item,
      );

      if (isAppended) {
        return ParseResult.success;
      } else {
        AppLogger.i("🔁 [단일 입력 중복 스킵]: ${item.date} | ${item.description} | ${item.amount}원");
        return ParseResult.duplicate;
      }
    } catch (e) {
      AppLogger.i("❌ [appendParseSingleLine] 처리 실패: $e");
      return ParseResult.fail;
    }
  }
}

/// 다중 입력을 Google Sheets에 전송하는 입력 서비스
class MultiEntryService {
  final LedgerDataService sheetService = LedgerDataService();

  Future<Map<ParseResult, int>> appendParseMultiLines(
    AuthClient authClient,
    sheets.SheetsApi sheetsApi,
    List<Map<String, dynamic>> itemMaps,
  ) async {
    int successCount = 0;
    int duplicateCount = 0;
    int failCount = 0;

    AppLogger.i("🚀 [MultiEntryService] 총 ${itemMaps.length}개 항목 일괄 처리 시작");

    // 1. 연도(Year) -> 월(Sheet) 순으로 2단계 분류
    final Map<int, Map<String, List<LedgerItem>>> itemsByYearAndSheet = {};

    for (final itemMap in itemMaps) {
      if (itemMap.isEmpty) {
        failCount++;
        continue;
      }
      try {
        final LedgerItem item = LedgerItem.fromMap(itemMap);
        final int year = item.date.year;
        final String sheetName = "${item.date.month}월";

        itemsByYearAndSheet
            .putIfAbsent(year, () => {})
            .putIfAbsent(sheetName, () => [])
            .add(item);
      } catch (e) {
        AppLogger.i("❌ [Item 변환 실패]: $e");
        failCount++;
      }
    }

    // 2. 연도별 순회 처리
    for (final yearEntry in itemsByYearAndSheet.entries) {
      final int year = yearEntry.key;
      final Map<String, List<LedgerItem>> itemsBySheet = yearEntry.value;

      // 💡 연도에 맞는 spreadsheetId 가져오기 (없으면 자동 생성)
      final String? spreadsheetId = await sheetService.sheetSetupService
          .setupLedgerSpreadsheetForYear(authClient, year);

      // Null-safety 체크: 시트 ID를 얻지 못했다면 해당 연도의 모든 항목을 실패 건수로 합산 처리
      if (spreadsheetId == null) {
        AppLogger.i("⚠️ [$year년] 시트를 찾을 수 없거나 생성에 실패했습니다.");
        final yearItemCount = itemsBySheet.values
            .fold<int>(0, (sum, list) => sum + list.length);
        failCount += yearItemCount;
        continue;
      }

      // 3. 월 단위 시트별 처리
      for (final sheetEntry in itemsBySheet.entries) {
        final String sheetName = sheetEntry.key;
        final List<LedgerItem> pendingItems = sheetEntry.value;

        // 3-1. 해당 월의 기존 시트 데이터 호출
        List<List<dynamic>> existingRows = [];
        try {
          final response = await sheetsApi.spreadsheets.values.get(
            spreadsheetId,
            "'$sheetName'!A1:Z1000",
          );
          existingRows = response.values ?? [];
        } catch (e) {
          AppLogger.i("⚠️ [$year년 $sheetName] 기존 데이터 읽기 실패 (신규 시트 가능성): $e");
        }

        // 3-2. 기존 시트 행 데이터 정규화 및 고유 키(Set) 등록
        final Set<String> existingKeys = {};

        for (final row in existingRows) {
          if (row.isEmpty) continue;

          final String rawRowStr = row.map((e) => e.toString()).join(' ');

          final dateMatch = RegExp(r'\d{4}\D?\d{1,2}\D?\d{1,2}').firstMatch(rawRowStr);
          if (dateMatch == null) continue;

          final String dateDigits = dateMatch.group(0)!.replaceAll(RegExp(r'\D'), '');

          for (final item in pendingItems) {
            final targetDateDigits =
                "${item.date.year}${item.date.month.toString().padLeft(2, '0')}${item.date.day.toString().padLeft(2, '0')}";

            if (!dateDigits.contains(targetDateDigits)) continue;

            final targetAmount = item.amount.toString();
            final targetDesc = item.description.trim();

            final bool hasDesc = rawRowStr.contains(targetDesc);
            final bool hasAmount = row.any((cell) {
              final cellDigits = cell.toString().replaceAll(RegExp(r'\D'), '');
              return cellDigits == targetAmount;
            });

            if (hasDesc && hasAmount) {
              final key = "${targetDateDigits}_${targetDesc}_$targetAmount";
              existingKeys.add(key);
            }
          }
        }

        final List<LedgerItem> itemsToAppend = [];
        final Set<String> batchKeys = {}; // 현재 배치 내 중복 추적을 위한 Set

        // 3-3. 입력 항목 중복 비교
        for (final item in pendingItems) {
          final dateDigits =
              "${item.date.year}${item.date.month.toString().padLeft(2, '0')}${item.date.day.toString().padLeft(2, '0')}";
          final targetDesc = item.description.trim();
          final targetAmount = item.amount.toString();

          final itemKey = "${dateDigits}_${targetDesc}_$targetAmount";

          if (existingKeys.contains(itemKey) || batchKeys.contains(itemKey)) {
            duplicateCount++;
            AppLogger.i("🔁 [중복 스킵] [$year년 $sheetName] $dateDigits | $targetDesc | ${item.amount}원");
          } else {
            itemsToAppend.add(item);
            batchKeys.add(itemKey);
          }
        }

        // 3-4. 중복을 제외한 실제 '신규 데이터'만 구글 시트에 전송
        if (itemsToAppend.isNotEmpty) {
          try {
            final bool isSuccess = await sheetService.appendTransactionBatch(
              sheetsApi,
              spreadsheetId,
              sheetName,
              itemsToAppend,
            );

            if (isSuccess) {
              successCount += itemsToAppend.length;
              AppLogger.i("✅ [$year년 $sheetName] ${itemsToAppend.length}개 신규 항목 입력 성공!");
            } else {
              failCount += itemsToAppend.length;
            }
          } catch (e) {
            AppLogger.i("❌ [$year년 $sheetName] 배치 입력 실패: $e");
            failCount += itemsToAppend.length;
          }
        } else {
          AppLogger.i("💡 [$year년 $sheetName] 전송할 신규 항목이 없습니다. (모두 중복 스킵됨)");
        }
      }
    }

    AppLogger.i("📊 [처리 완료] 성공: $successCount, 중복스킵: $duplicateCount, 실패: $failCount");

    return {
      ParseResult.success: successCount,
      ParseResult.duplicate: duplicateCount,
      ParseResult.fail: failCount,
    };
  }
}