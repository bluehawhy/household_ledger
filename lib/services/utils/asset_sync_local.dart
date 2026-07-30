import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigManager {
  // 웹/공통 가상 경로 (Key)
  static const String _webPath = 'household_ledger/asset_local/config.json';
  
  // 앱 기본 Asset 경로
  static const String _assetPath = 'assets/config.json';

  /// [1단계: 초기화] 파일/데이터 존재 여부 체크 -> 없으면 Assets에서 복사
  Future<void> initConfigFile() async {
    if (kIsWeb) {
      // -------------------------------------------------------------
      // [웹(Web) 환경 처리]
      // household_ledger/asset_local/config.json 경로(Key) 존재 여부 체크
      // -------------------------------------------------------------
      final prefs = await SharedPreferences.getInstance();
      final hasConfig = prefs.containsKey(_webPath);

      if (hasConfig) {
        print('🌐 [Web Config] "$_webPath" 경로에 저장된 설정이 존재합니다. (Skip)');
        return;
      }

      print('⚙️ [Web Config] Assets에서 기본 설정을 읽어 "$_webPath" 에 생성합니다...');
      final String assetContent = await rootBundle.loadString(_assetPath);
      await prefs.setString(_webPath, assetContent);
      print('✅ [Web Config] 저장 완료!');
    } else {
      // -------------------------------------------------------------
      // [앱(Android/iOS/Desktop) 환경 처리]
      // [Documents Directory]/household_ledger/asset_local/config.json 폴더 및 파일 생성
      // -------------------------------------------------------------
      final file = await _getLocalFile();

      if (await file.exists()) {
        print('📂 [App Config] 로컬 설정 파일이 이미 존재합니다: ${file.path} (Skip)');
        return;
      }

      print('⚙️ [App Config] Assets에서 기본 설정을 읽어 로컬 파일로 저장합니다...');
      
      // 상위 폴더(household_ledger/asset_local)가 없으면 생성
      await file.parent.create(recursive: true);

      final String assetContent = await rootBundle.loadString(_assetPath);
      await file.writeAsString(assetContent);
      print('✅ [App Config] 로컬 파일 생성 완료: ${file.path}');
    }
  }

  /// [2단계: 로드] 저장소에서 JSON 읽기
  Future<String> loadConfigJson() async {
    await initConfigFile(); // 안전성 확보용 초기화 검사

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_webPath) ?? '';
    } else {
      final file = await _getLocalFile();
      return await file.readAsString();
    }
  }

  /// [3단계: 저장/업데이트] 변경사항 발생 시 저장
  Future<void> saveConfigJson(String jsonString) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webPath, jsonString);
      print('🌐 [Web Config] "$_webPath" 업데이트 완료');
    } else {
      final file = await _getLocalFile();
      // 혹시라도 폴더가 지워졌을 가능성에 대비
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(jsonString);
      print('📂 [App Config] "${file.path}" 업데이트 완료');
    }
  }

  /// (앱 전용) 문서 디렉터리 하위 household_ledger/asset_local/config.json 경로 반환
  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final fullPath = p.join(
      directory.path,
      'household_ledger',
      'asset_local',
      'config.json',
    );
    return File(fullPath);
  }
}