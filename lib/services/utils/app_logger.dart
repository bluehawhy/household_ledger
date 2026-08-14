import 'package:logger/logger.dart';

class AppLogger {
  static const bool _isDebug = !bool.fromEnvironment('dart.vm.product');

  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: CustomLogPrinter(),
  );

  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) _logger.d(message, error: error, stackTrace: stackTrace);
  }

  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) _logger.i(message, error: error, stackTrace: stackTrace);
  }

  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) _logger.e(message, error: error, stackTrace: stackTrace);
  }
}

/// 💡 [시간] [로그레벨] [파일명:줄번호] 메시지 형태로 한 줄 출력하는 커스텀 프린터
class CustomLogPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}";
    final levelStr = event.level.name.toUpperCase().padRight(5);

    // 💡 스택트레이스에서 AppLogger를 실제 호출한 위치(파일명 & 줄번호) 추출
    final locationStr = _getCallerLocation();

    // 한 줄 출력: [02:17:07.770] [INFO ] [test_parser.dart:18] 메시지
    return ["[ $timeStr ] [$levelStr] [$locationStr] ${event.message}"];
  }

  /// 호출 위치 파싱 헬퍼 함수
  String _getCallerLocation() {
    final lines = StackTrace.current.toString().split('\n');

    for (final line in lines) {
      // AppLogger 내부 및 logger 패키지 라이브러리 프레임 제외
      if (line.contains('app_logger.dart') ||
          line.contains('package:logger') ||
          line.trim().isEmpty) {
        continue;
      }

      // 파일 위치 정규식 매칭 (예: test_parser.dart:18:13 또는 text_parser_service.dart:45:7)
      final match = RegExp(r'([a-zA-Z0-9_]+\.dart):(\d+)').firstMatch(line);
      if (match != null) {
        final fileName = match.group(1);
        final lineNumber = match.group(2);
        return '$fileName:$lineNumber';
      }
    }

    return 'unknown';
  }
}