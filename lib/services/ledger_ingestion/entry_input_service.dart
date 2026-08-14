import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';
import 'package:household_ledger/services/utils/app_logger.dart';


/// 단일 입력을 Google Sheets에 전송하는 입력 서비스
class SingleEntryService {
  final HouseholdSheetService sheetService = HouseholdSheetService();

  Future<ParseResult> appendParseSingleLine(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    Map<String, dynamic> itemMap,
  ) async {
    if (itemMap.isEmpty) {
      return ParseResult.fail;
    }

    try {
      final LedgerItem item = LedgerItem.fromMap(itemMap);
      final sheetName = "${item.date.month}월";

      List<List<dynamic>> existingRows = [];
      try {
        final response = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          "'$sheetName'!A1:Z1000",
        );
        existingRows = response.values ?? [];
      } catch (e) {
        AppLogger.i("⚠️ [$sheetName] 시트 읽기 실패 (신규 시트 또는 데이터 없음): $e");
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

class MultiEntryService {
  final HouseholdSheetService sheetService = HouseholdSheetService();

  Future<Map<ParseResult, int>> appendParseMultiLines(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    List<Map<String, dynamic>> itemMaps,
  ) async {
    int successCount = 0;
    int duplicateCount = 0;
    int failCount = 0;

    AppLogger.i("🚀 [MultiEntryService] 총 ${itemMaps.length}개 항목 일괄 처리 시작");

    // 1. 월(Sheet)별로 입력 값 분류
    final Map<String, List<LedgerItem>> itemsBySheet = {};

    for (final itemMap in itemMaps) {
      if (itemMap.isEmpty) {
        failCount++;
        continue;
      }
      try {
        final LedgerItem item = LedgerItem.fromMap(itemMap);
        final sheetName = "${item.date.month}월";
        itemsBySheet.putIfAbsent(sheetName, () => []).add(item);
      } catch (e) {
        AppLogger.i("❌ [Item 변환 실패]: $e");
        failCount++;
      }
    }

    // 2. 월 단위 처리 (시트 읽기 ➔ 객체 맵핑 ➔ 중복 검사 ➔ 일괄 쓰기)
    for (final entry in itemsBySheet.entries) {
      final String sheetName = entry.key;
      final List<LedgerItem> pendingItems = entry.value;

      // 2-1. 해당 월의 기존 시트 데이터 호출
      List<List<dynamic>> existingRows = [];
      try {
        final response = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          "'$sheetName'!A1:Z1000",
        );
        existingRows = response.values ?? [];
      } catch (e) {
        AppLogger.i("⚠️ [$sheetName] 기존 데이터 읽기 실패 (신규 시트 가능성): $e");
      }

      // 2-2. 기존 시트 행 데이터 정규화 및 고유 키(Set) 등록
      final Set<String> existingKeys = {};

      for (final row in existingRows) {
        if (row.isEmpty) continue;

        // row 전체를 문자열 하나로 합침 (예: "2026.07.27 신한카드 네이버페이-제로맥주구매 3,000")
        final String rawRowStr = row.map((e) => e.toString()).join(' ');

        // 날짜 추출 (YYYYMMDD 형식의 8자리 숫자 검색)
        final dateMatch = RegExp(r'\d{4}\D?\d{1,2}\D?\d{1,2}').firstMatch(rawRowStr);
        if (dateMatch == null) continue; // 헤더나 날짜가 없는 행은 스킵

        final String dateDigits = dateMatch.group(0)!.replaceAll(RegExp(r'\D'), '');

        // 금액 및 적요 매핑을 위해 row 내의 각 셀 검사
        for (final item in pendingItems) {
          final targetDateDigits =
              "${item.date.year}${item.date.month.toString().padLeft(2, '0')}${item.date.day.toString().padLeft(2, '0')}";
          
          if (!dateDigits.contains(targetDateDigits)) continue;

          final targetAmount = item.amount.toString();
          final targetDesc = item.description.trim();

          // 적요 포함 여부 & 금액 일치 여부 확인
          final bool hasDesc = rawRowStr.contains(targetDesc);
          final bool hasAmount = row.any((cell) {
            final cellDigits = cell.toString().replaceAll(RegExp(r'\D'), '');
            return cellDigits == targetAmount;
          });

          if (hasDesc && hasAmount) {
            // 시트에 이미 존재하는 키 추가
            final key = "${targetDateDigits}_${targetDesc}_$targetAmount";
            existingKeys.add(key);
          }
        }
      }

      final List<LedgerItem> itemsToAppend = [];

      // 2-3. 입력 항목 중복 비교
      for (final item in pendingItems) {
        final dateDigits =
            "${item.date.year}${item.date.month.toString().padLeft(2, '0')}${item.date.day.toString().padLeft(2, '0')}";
        final targetDesc = item.description.trim();
        final targetAmount = item.amount.toString();

        final itemKey = "${dateDigits}_${targetDesc}_$targetAmount";

        if (existingKeys.contains(itemKey)) {
          // 중복 발견!
          duplicateCount++;
          AppLogger.i("🔁 [중복 스킵] [$sheetName] $dateDigits | $targetDesc | ${item.amount}원");
        } else {
          // 신규 데이터 추가 목록에 넣고, 이번 입력 뭉치 내 중복 방지용으로 Key 세트에도 즉시 추가
          itemsToAppend.add(item);
          existingKeys.add(itemKey);
        }
      }

      // 2-4. 중복을 제외한 실제 '신규 데이터'만 구글 시트에 전송
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
            AppLogger.i("✅ [$sheetName] ${itemsToAppend.length}개 신규 항목 입력 성공!");
          } else {
            failCount += itemsToAppend.length;
          }
        } catch (e) {
          AppLogger.i("❌ [$sheetName] 배치 입력 실패: $e");
          failCount += itemsToAppend.length;
        }
      } else {
        AppLogger.i("💡 [$sheetName] 전송할 신규 항목이 없습니다. (모두 중복 스킵됨)");
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


/// HouseholdSheetService 파일에 추가할 일괄(Batch) Append 함수
Future<bool> appendTransactionBatch(
  sheets.SheetsApi sheetsApi,
  String spreadsheetId,
  String sheetName,
  List<LedgerItem> items,
) async {
  if (items.isEmpty) return true;

  try {
    // 1. Google Sheets에 입력할 2차원 배열 데이터 구성
    final List<List<Object?>> valueList = items.map((item) {
      final formattedDate =
          "${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}";

      return <Object?>[
        formattedDate,
        item.category,    // 이제 String? 형태도 문제없이 들어갑니다.
        item.description,
        item.amount,
        item.payMethod,
      ];
    }).toList();

    // 2. ValueRange 객체 생성
    final valueRange = sheets.ValueRange(values: valueList);

    // 3. API 요청 (단 1회의 append 로 전송)
    await sheetsApi.spreadsheets.values.append(
      valueRange,
      spreadsheetId,
      "'$sheetName'!A1",
      valueInputOption: "USER_ENTERED",
    );

    return true;
  } catch (e) {
    AppLogger.i("❌ [appendTransactionBatch] 오류 발생: $e");
    return false;
  }
}

