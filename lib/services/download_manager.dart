import 'dart:isolate';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'download_logger.dart';

@pragma('vm:entry-point')
class DownloadManager {
  static const String portName = 'rexify_downloader_port';
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    // La UI registrará su propio ReceivePort con el mismo nombre
    _initialized = true;
  }

  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = ui.IsolateNameServer.lookupPortByName(portName);
    send?.send([id, status, progress]);
  }

  static Future<String?> enqueue({
    required String baseUrl,
    required String link,
    String format = 'mp3',
    bool video = false,
    bool saveToExternal = true,
  }) async {
    try {
      final normalized = _normalize(link);
      final url = Uri.parse(baseUrl).replace(
        path: '/download',
        queryParameters: {
          'q': normalized,
          'format': format,
          if (video) 'video': '1',
        },
      );

      // pick directory
      Directory dir;
      if (saveToExternal) {
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads) ??
            await getExternalStorageDirectories(type: StorageDirectory.music);
        dir = (extDirs != null && extDirs.isNotEmpty)
            ? Directory('${extDirs.first.path}/Rexify')
            : await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
        dir = Directory('${dir.path}/Rexify');
      }
      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now().millisecondsSinceEpoch;
      final ext = (format.toLowerCase() == 'mp4') ? (video ? 'mp4' : 'm4a') : 'mp3';
      final fileName = 'rex_${now}.$ext';

      await DownloadLogger.instance.logJson({
        'event': 'bg_enqueue',
        'url': url.toString(),
        'dir': dir.path,
        'file': fileName,
      });

      final taskId = await FlutterDownloader.enqueue(
        url: url.toString(),
        savedDir: dir.path,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: true,
        saveInPublicStorage: saveToExternal,
      );
      return taskId;
    } catch (e) {
      await DownloadLogger.instance.logJson({
        'event': 'bg_enqueue_error',
        'error': e.toString(),
      });
      return null;
    }
  }

  static Future<DownloadTask?> loadTask(String taskId) async {
    try {
      final sanitized = taskId.replaceAll("'", "");
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(
        query: "SELECT * FROM task WHERE task_id = '$sanitized'",
      );
      if (tasks == null || tasks.isEmpty) {
        return null;
      }
      return tasks.firstWhere(
        (t) => t.taskId == taskId,
        orElse: () => tasks.first,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<File?> resolveDownloadedFile(String taskId) async {
    final task = await loadTask(taskId);
    if (task == null) return null;
    final savedDir = task.savedDir;
    final filename = task.filename;
    if ((savedDir == null || savedDir.isEmpty) || (filename == null || filename.isEmpty)) {
      return null;
    }
    final file = File('$savedDir/$filename');
    return await file.exists() ? file : null;
  }

  static Future<DownloadTaskStatus?> resolveTaskStatus(String taskId) async {
    final task = await loadTask(taskId);
    return task?.status;
  }

  /// Elimina una tarea de FlutterDownloader y opcionalmente borra el archivo.
  static Future<bool> removeTask(String taskId, {bool deleteFile = true}) async {
    try {
      await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: deleteFile);
      await DownloadLogger.instance.logJson({
        'event': 'bg_remove',
        'taskId': taskId,
        'deletedFile': deleteFile,
      });
      return true;
    } catch (e) {
      await DownloadLogger.instance.logJson({
        'event': 'bg_remove_error',
        'taskId': taskId,
        'error': e.toString(),
      });
      return false;
    }
  }

  /// Borra todas las tareas registradas por FlutterDownloader. Devuelve la cuenta de tareas eliminadas.
  static Future<int> removeAllDownloads({bool deleteFiles = true}) async {
    try {
      final tasks = await FlutterDownloader.loadTasks() ?? [];
      int removed = 0;
      for (final t in tasks) {
        try {
          await FlutterDownloader.remove(taskId: t.taskId, shouldDeleteContent: deleteFiles);
          removed++;
        } catch (_) {
          // ignorar fallos individuales
        }
      }
      await DownloadLogger.instance.logJson({
        'event': 'bg_remove_all',
        'count': removed,
        'deletedFiles': deleteFiles,
      });
      return removed;
    } catch (e) {
      await DownloadLogger.instance.logJson({
        'event': 'bg_remove_all_error',
        'error': e.toString(),
      });
      return 0;
    }
  }

  static Future<File?> enqueueStreamingDownload({
    required Uri uri,
    required String filename,
    required void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final streamed = await client.send(req);
      if (streamed.statusCode != 200) return null;

      final tempDir = (await getTemporaryDirectory()).path;
      final filePath = p.join(tempDir, filename);
      final file = File(filePath);
      final sink = file.openWrite();
      final contentLength = streamed.contentLength ?? -1;
      int received = 0;

      await for (final chunk in streamed.stream) {
        if (chunk.isNotEmpty) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null && contentLength > 0) {
            onProgress(received / contentLength);
          } else if (onProgress != null) {
            // progreso indefinido: se puede enviar null/ -1 o estimar
            onProgress(-1);
          }
        }
      }
      await sink.close();
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static String _normalize(String query) {
    var s = query.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      s = s.replaceAll(RegExp(r"\s+"), "");
      Uri? u;
      try { u = Uri.parse(s); } catch (_) { u = null; }
      if (u != null) {
        final host = (u.host).toLowerCase();
        if (host.contains('youtu.be')) {
          final id = (u.pathSegments.isNotEmpty) ? u.pathSegments.last : null;
          if (id != null && id.isNotEmpty) return 'https://www.youtube.com/watch?v=$id';
        }
        if (host.contains('youtube.com')) {
          final v = u.queryParameters['v'];
          if (v != null && v.isNotEmpty) return 'https://www.youtube.com/watch?v=$v';
        }
      }
      return s;
    } else {
      s = s.replaceAll(RegExp(r"\s+"), " ");
      return s;
    }
  }
}
