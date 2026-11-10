import 'dart:io';

import 'package:flutter/foundation.dart';

/// Local diagnostics log.
///
/// The app is offline-first with no backend, so there is nowhere safe to send
/// alerts from the phone (a notify token must never ship inside an APK).
/// Instead every key operation and every uncaught error is written to
/// `app.log` in the app's private folder. The owner can open it from
/// Settings -> Diagnostics log and share it to the developer in one tap.
class AppLog {
  AppLog._();
  static File? _file;
  static const _maxBytes = 256 * 1024;
  static final List<String> _pending = [];

  static Future<void> init(String dir) async {
    _file = File('$dir/app.log');
    if (!await _file!.exists()) await _file!.create(recursive: true);
    if (_pending.isNotEmpty) {
      final lines = [..._pending];
      _pending.clear();
      for (final l in lines) {
        await _append(l);
      }
    }
  }

  static File? get file => _file;

  static void info(String msg) => _write('INFO', msg);
  static void warn(String msg) => _write('WARN', msg);
  static void error(String msg, [Object? error, StackTrace? stack]) {
    final b = StringBuffer(msg);
    if (error != null) b.write(' | $error');
    if (stack != null) {
      b.write('\n');
      b.write(stack.toString().split('\n').take(12).join('\n'));
    }
    _write('ERROR', b.toString());
  }

  static void _write(String level, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$level] $msg';
    debugPrint(line);
    if (_file == null) {
      _pending.add(line);
      return;
    }
    _append(line);
  }

  static Future<void> _append(String line) async {
    try {
      final f = _file!;
      if (await f.exists() && await f.length() > _maxBytes) {
        final text = await f.readAsString();
        await f.writeAsString(text.substring(text.length ~/ 2));
      }
      await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never crash the app.
    }
  }

  static Future<String> read() async {
    final f = _file;
    if (f == null || !await f.exists()) return '';
    return f.readAsString();
  }

  static Future<int> errorCount() async {
    final t = await read();
    return '[ERROR]'.allMatches(t).length;
  }

  static Future<void> clear() async {
    final f = _file;
    if (f != null && await f.exists()) await f.writeAsString('');
  }
}
