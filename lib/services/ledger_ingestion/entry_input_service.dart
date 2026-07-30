import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart';
import 'package:household_ledger/services/google_drive/google_spreadsheet.dart';

/// 파싱 및 시트 데이터 추가 결과 상태
enum ParseResult {
  success,   // 성공적으로 추가됨
  duplicate, // 중복 데이터로 확인되어 스킵됨
  fail,      // 비어있거나 파싱/API 통신 에러 등 실패
}

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
        print("⚠️ [$sheetName] 시트 읽기 실패 (신규 시트 또는 데이터 없음): $e");
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
        print("🔁 [단일 입력 중복 스킵]: ${item.date} | ${item.description} | ${item.amount}원");
        return ParseResult.duplicate;
      }
    } catch (e) {
      print("❌ [appendParseSingleLine] 처리 실패: $e");
      return ParseResult.fail;
    }
  }
}

/// 다중 입력을 캐시 및 배치 기반으로 Google Sheets에 전송하는 서비스
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

    print("🚀 [MultiEntryService] 총 ${itemMaps.length}개 항목 일괄(Batch) 처리 시작");

    // 1. 월별로 처리할 데이터 분류 (예: {"6월": [item1, item2], "5월": [item3]})
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
        print("❌ [Item 변환 실패]: $e");
        failCount++;
      }
    }

    // 2. 월(Sheet) 단위로 한 번에 시트 읽기 & 중복 검사 & 일괄 Append
    for (final entry in itemsBySheet.entries) {
      final String sheetName = entry.key;
      final List<LedgerItem> pendingItems = entry.value;

      // 해당 월의 기존 시트 데이터 읽어오기 (1회 호출)
      List<List<dynamic>> existingRows = [];
      try {
        final response = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          "'$sheetName'!A1:Z1000",
        );
        existingRows = response.values ?? [];
      } catch (e) {
        print("⚠️ [$sheetName] 기존 데이터 읽기 실패 (신규 시트 가능성): $e");
      }

      // 메모리 내 중복 검사 및 최종 추가 대상 선별
      final List<LedgerItem> itemsToAppend = [];

      for (final item in pendingItems) {
        final formattedDate =
            "${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}";

        // 기존 행(existingRows) 및 이번 배치에서 선별된 행과 중복 비교
        final bool isDuplicate = existingRows.any((row) {
          if (row.length < 4) return false;
          final rowDate = row[0].toString();
          final rowDesc = row[2].toString();
          final rowAmount = row[3].toString();

          return rowDate.contains(formattedDate) &&
              rowDesc == item.description &&
              rowAmount == item.amount.toString();
        });

        if (isDuplicate) {
          duplicateCount++;
          print("🔁 [중복 스킵] [$sheetName] ${item.date} | ${item.description} | ${item.amount}원");
        } else {
          itemsToAppend.add(item);
          // 이번 배치 내부 중복 방지를 위해 기존 목록 캐시에 임시 추가
          existingRows.add([
            formattedDate,
            item.category,
            item.description,
            item.amount,
            item.payMethod,
          ]);
        }
      }

      // 3. 중복되지 않은 신규 데이터가 있다면 '월당 딱 1번의 API 호출'로 일괄 전송
      if (itemsToAppend.isNotEmpty) {
        try {
          // 💡 핵심: 1건씩 loop 돌리지 않고, 리스트 전체를 한 번에 넣는 batchAppend API 호출
          final bool isSuccess = await sheetService.appendTransactionBatch(
            sheetsApi,
            spreadsheetId,
            sheetName,
            itemsToAppend,
          );

          if (isSuccess) {
            successCount += itemsToAppend.length;
            print("✅ [$sheetName] ${itemsToAppend.length}개 항목 일괄 입력 성공!");
          } else {
            failCount += itemsToAppend.length;
          }
        } catch (e) {
          print("❌ [$sheetName] 배치 입력 실패: $e");
          failCount += itemsToAppend.length;
        }
      }
    }

    print("📊 [처리 완료] 성공: $successCount, 중복스킵: $duplicateCount, 실패: $failCount");

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
    print("❌ [appendTransactionBatch] 오류 발생: $e");
    return false;
  }
}