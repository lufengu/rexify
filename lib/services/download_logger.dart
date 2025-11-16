import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DownloadLogger {
  DownloadLogger._();
  static final DownloadLogger instance = DownloadLogger._();

  Future<File> _ensureLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/Rexify/logs');
    if (!await logDir.exists()) await logDir.create(recursive: true);
    final file = File('${logDir.path}/downloads.log');
    if (!await file.exists()) await file.create(recursive: true);
    return file;
  }

  Future<void> log(String message) async {
    try {
      final file = await _ensureLogFile();
      final now = DateTime.now().toIso8601String();
      await file.writeAsString('[$now] $message\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> logJson(Map<String, dynamic> data) async {
    try {
      final file = await _ensureLogFile();
      final now = DateTime.now().toIso8601String();
      final line = {'ts': now, ...data};
      await file.writeAsString('${line.toString()}\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
