import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:household_ledger/services/ledger_ingestion/ledger_item.dart'; // 👈 import 추가
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

  /// ✏️ Map을 받아 LedgerItem으로 만든 후 appendTransactionData를 호출해 시트에 삽입합니다.
  Future<ParseResult> appendParseSingleLine(
    sheets.SheetsApi sheetsApi,
    String spreadsheetId,
    Map<String, dynamic> itemMap,
  ) async {
    if (itemMap.isEmpty) {
      return ParseResult.fail;
    }

    try {
      // 1. Map -> LedgerItem 변환
      final LedgerItem item = LedgerItem.fromMap(itemMap);

      // 2. 월별 시트 이름 설정 (예: "7월")
      final sheetName = "${item.date.month}월";

      // 3. 기존 시트 데이터 가져오기 (중복 체크용)
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

      // 4. 시트에 데이터 추가
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
        return ParseResult.duplicate;
      }
    } catch (e) {
      print("❌ [appendParseSingleLine] 처리 실패: $e");
      return ParseResult.fail;
    }
  }
}