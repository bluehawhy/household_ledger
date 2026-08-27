import 'package:logger/logger.dart';

class AppLogger {
  static const bool _isDebug = !bool.fromEnvironment('dart.vm.product');

  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: CustomLogPrinter(),
  );

  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.d(message,error: error,stackTrace: stackTrace ?? StackTrace.current,);
    }
  }

  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.i(message,error: error,stackTrace: stackTrace ?? StackTrace.current,);
    }
  }

  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.w(message,error: error,stackTrace: stackTrace ?? StackTrace.current,);
    }
  }

  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.e(message,error: error,stackTrace: stackTrace ?? StackTrace.current,);
    }
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

    // AppLogger 호출 순간에 전달된 스택에서 실제 호출 위치를 추출한다.
    final locationStr = _getCallerLocation(event.stackTrace);

    // 한 줄 출력: [02:17:07.770] [INFO ] [test_parser.dart:18] 메시지
    return ["[ $timeStr ] [$levelStr] [$locationStr] ${event.message}"];
  }

  /// 호출 위치 파싱 헬퍼 함수
  String _getCallerLocation(StackTrace? stackTrace) {
    if (stackTrace == null) return 'unknown';

    final lines = stackTrace.toString().split('\n');

    for (final line in lines) {
      // AppLogger, logger 패키지, 웹 Dart 런타임 프레임은 제외한다.
      if (line.contains('app_logger.dart') ||
          line.contains('package:logger') ||
          line.contains('dart-sdk/') ||
          line.contains('js_dev_runtime') ||
          line.trim().isEmpty) {
        continue;
      }

      // VM은 `file.dart:줄:열`, 웹 DDC는 `file.dart 줄:열` 형식을 사용한다.
      final match = RegExp(
        r'([a-zA-Z0-9_]+\.dart)(?::|\s+)(\d+)(?::\d+)?',
      ).firstMatch(line);
      if (match != null) {
        final fileName = match.group(1);
        final lineNumber = match.group(2);
        return '$fileName:$lineNumber';
      }
    }

    return 'unknown';
  }
}
