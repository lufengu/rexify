import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
// removed unused imports: path, open_file, just_audio
import 'package:flutter/services.dart';
import 'download_logger.dart';

class BackendClient {
  BackendClient({required this.baseUrl});

  final String baseUrl; // Ej: http://127.0.0.1:5000

  /// Descarga un MP3 desde el backend dado un término de búsqueda.
  /// Retorna un File guardado en el directorio temporal de la app.
  /// [onProgress] recibe (bytesReceived, totalBytes) donde totalBytes puede ser -1 si desconocido.
  Future<File> downloadSongMp3(
    String query, {
    Duration connectTimeout = const Duration(seconds: 60),
    Duration receiveTimeout = const Duration(minutes: 2),
    int maxRetries = 2,
    bool saveToExternal = false,
    String format = 'mp3',
    bool video = false,
    void Function(int received, int total)? onProgress,
  }) async {
    final normalized = _normalizeQueryForBackend(query);
    await DownloadLogger.instance.logJson({
      'event': 'enqueue_direct',
      'q': normalized,
      'format': format,
      'video': video,
    });
    final qp = <String, String>{'q': normalized, 'format': format};
    if (video) qp['video'] = '1';
    final uri = Uri.parse('$baseUrl/download').replace(queryParameters: qp);
    int attempt = 0;
    HttpException? lastError;
    while (attempt <= maxRetries) {
      attempt++;
      final client = http.Client();
      try {
        // Timeout de conexión: usamos Future.timeout sobre send()
        final request = http.Request('GET', uri);
        final streamed = await client.send(request).timeout(connectTimeout);
        if (streamed.statusCode != 200) {
          final reason = await streamed.stream.bytesToString();
          throw HttpException('Error ${streamed.statusCode} descargando MP3: $reason', uri: uri);
        }

    String filename = _extractFilename(streamed.headers['content-disposition']) ??
      'audio_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.${format.toLowerCase() == 'mp4' ? (video ? 'mp4' : 'm4a') : 'mp3'}';

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$filename');
    final sink = tempFile.openWrite();
        final total = streamed.contentLength ?? -1;
        int received = 0;
        final receiveDeadline = DateTime.now().add(receiveTimeout);
        try {
          await for (final chunk in streamed.stream) {
            received += chunk.length;
            sink.add(chunk);
            // Emitir progreso si se solicita
            try {
              if (onProgress != null) onProgress(received, total);
            } catch (_) {}
            // Corta si sobrepasamos timeout de recepción sin terminar
            if (DateTime.now().isAfter(receiveDeadline)) {
              throw HttpException('Timeout recepción excedido tras ${(receiveTimeout.inSeconds)}s, recibido=$received bytes', uri: uri);
            }
          }
        } finally {
          await sink.close();
        }
        // Mover a directorio persistente de la app para que el archivo no se pierda
        try {
          final persistDir = await getApplicationDocumentsDirectory();
          final targetDir = Directory('${persistDir.path}/Rexify');
          if (!await targetDir.exists()) await targetDir.create(recursive: true);
          var finalFile = File('${targetDir.path}/$filename');
          // Si ya existe, renombra con sufijo
          if (await finalFile.exists()) {
            final unique = DateTime.now().millisecondsSinceEpoch;
            finalFile = File('${targetDir.path}/${unique}_$filename');
          }
          await tempFile.rename(finalFile.path);

          // Si se solicita guardar en carpeta pública (Music/Downloads), intentamos mover/copy allí
          if (saveToExternal) {
            try {
              final extDirs = await getExternalStorageDirectories(type: StorageDirectory.music) ??
                  await getExternalStorageDirectories(type: StorageDirectory.downloads);
              if (extDirs != null && extDirs.isNotEmpty) {
                final extBase = extDirs.first;
                final publicDir = Directory('${extBase.path}/Rexify');
                if (!await publicDir.exists()) await publicDir.create(recursive: true);
                var publicFile = File('${publicDir.path}/$filename');
                if (await publicFile.exists()) {
                  publicFile = File('${publicDir.path}/${DateTime.now().millisecondsSinceEpoch}_$filename');
                }
                // Try rename, fallback to copy
                try {
                  await finalFile.rename(publicFile.path);
                } catch (_) {
                  await finalFile.copy(publicFile.path);
                  try {
                    await finalFile.delete();
                  } catch (_) {}
                }
                finalFile = publicFile;
                // Try to notify MediaStore via platform channel (preferred)
                try {
                  const MethodChannel channel = MethodChannel('rexify/media_store');
                  // Determinar MIME por extensión/naturaleza
                  final lower = finalFile.path.toLowerCase();
                  String mime;
                  if (lower.endsWith('.mp3')) {
                    mime = 'audio/mpeg';
                  } else if (lower.endsWith('.m4a')) {
                    mime = 'audio/mp4';
                  } else if (lower.endsWith('.mp4')) {
                    mime = video ? 'video/mp4' : 'audio/mp4';
                  } else {
                    mime = 'application/octet-stream';
                  }
                  await channel.invokeMethod('saveToMediaStore', {
                    'path': finalFile.path,
                    'displayName': finalFile.uri.pathSegments.last,
                    'mime': mime,
                  });
                } catch (e) {
                  // fallback: request a media scan to make file visible
                  try {
                    const MethodChannel channel = MethodChannel('rexify/media_store');
                    await channel.invokeMethod('scanFile', {'path': finalFile.path});
                  } catch (_) {}
                }
              }
            } catch (_) {
              // ignore external save errors (fallback to app dir)
            }
          }

          // Verificación rápida solo para MP3: archivo debe parecer MP3 y tener tamaño mínimo
          try {
            final lower = finalFile.path.toLowerCase();
            if (lower.endsWith('.mp3')) {
              final ok = await _isProbableMp3(finalFile);
              if (!ok) throw HttpException('Downloaded file is not a valid MP3', uri: uri);
            }
          } catch (e) {
            // Si la verificación falla, intenta devolver temporal para inspección
            throw HttpException('Downloaded file failed validation: ${e.toString()}', uri: uri);
          }

          await DownloadLogger.instance.logJson({
            'event': 'download_success',
            'path': finalFile.path,
            'uri': uri.toString(),
            'size': await finalFile.length(),
          });
          return finalFile;
        } catch (e) {
          // Si mover falla, devolver el temporal (al menos no perder la descarga)
          await DownloadLogger.instance.logJson({
            'event': 'move_failed',
            'temp': tempFile.path,
            'error': e.toString(),
          });
          return tempFile;
        }
      } on SocketException catch (e) {
        lastError = HttpException('SocketException: ${e.message}', uri: uri);
        await DownloadLogger.instance.logJson({
          'event': 'socket_exception',
          'error': e.toString(),
          'attempt': attempt,
        });
        if (attempt > maxRetries) rethrow; // agotado
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      } on TimeoutException catch (e) {
        lastError = HttpException('Timeout: ${e.message}', uri: uri);
        await DownloadLogger.instance.logJson({
          'event': 'timeout',
          'error': e.toString(),
          'attempt': attempt,
        });
        if (attempt > maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      } on HttpException {
        await DownloadLogger.instance.logJson({
          'event': 'http_exception',
          'attempt': attempt,
        });
        rethrow; // errores HTTP definitivos no se reintentan
      } finally {
        client.close();
      }
    }
    await DownloadLogger.instance.logJson({
      'event': 'failed_all_retries',
      'error': lastError?.toString() ?? 'unknown',
    });
    throw lastError ?? HttpException('Fallo desconocido tras reintentos', uri: uri);
  }

  // --- Y2Mate integration ---

  Future<Map<String, dynamic>> resolveY2Mate(String query) async {
    final normalized = _normalizeQueryForBackend(query);
    final uri = Uri.parse('$baseUrl/y2mate/resolve').replace(queryParameters: {'q': normalized});
    final r = await http.get(uri).timeout(const Duration(seconds: 30));
    if (r.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    }
    throw HttpException('Resolve y2mate failed (${r.statusCode})', uri: uri);
  }

  Future<File> downloadY2Mate(
    String query, {
    String format = 'mp3',
    String? quality,
    String? formatId,
    bool saveToExternal = false,
    Duration connectTimeout = const Duration(seconds: 60),
    Duration receiveTimeout = const Duration(minutes: 3),
    void Function(int received, int total)? onProgress,
  }) async {
    final normalized = _normalizeQueryForBackend(query);
    await DownloadLogger.instance.logJson({
      'event': 'enqueue_y2mate',
      'q': normalized,
      'format': format,
      'quality': quality,
      'formatId': formatId,
    });

    final qp = <String, String>{'q': normalized, 'format': format};
    if (quality != null && quality.isNotEmpty) qp['quality'] = quality;
    if (formatId != null && formatId.isNotEmpty) qp['format_id'] = formatId;
    final uri = Uri.parse('$baseUrl/download_y2mate').replace(queryParameters: qp);

    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final streamed = await client.send(req).timeout(connectTimeout + receiveTimeout);
      if (streamed.statusCode != 200 && streamed.statusCode != 206) {
        throw HttpException('HTTP ${streamed.statusCode}', uri: uri);
      }

      String filename = _extractFilename(streamed.headers['content-disposition']) ??
          'y2_${DateTime.now().millisecondsSinceEpoch}.${format.toLowerCase() == 'mp4' ? 'mp4' : 'mp3'}';

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      final sink = tempFile.openWrite();
      final total = streamed.contentLength ?? -1;
      int received = 0;
      final deadline = DateTime.now().add(receiveTimeout);
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) onProgress(received, total);
        if (DateTime.now().isAfter(deadline)) {
          throw const HttpException('receive timeout');
        }
      }
      await sink.flush();
      await sink.close();

      if (saveToExternal) {
        // Intentar mover/registrar en almacenamiento externo via MethodChannel (opcional)
        try {
          // Reutilizar logger por ahora; en futuro se puede invocar canal nativo.
          await DownloadLogger.instance.log('Saved temp file at ${tempFile.path}');
        } catch (_) {}
      }

      return tempFile;
    } finally {
      client.close();
    }
  }

  // no helper methods needed; using dart:convert jsonDecode

  // Normaliza entradas para el backend:
  // - Si es URL: elimina todos los espacios/linebreaks; para YouTube extrae el ID y genera URL canónica.
  // - Si es texto (búsqueda): colapsa espacios múltiples a uno.
  String _normalizeQueryForBackend(String query) {
    var s = query.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      // Eliminar espacios o saltos insertados al copiar/pegar
      s = s.replaceAll(RegExp(r"\s+"), "");
      // Canonizar YouTube
      Uri? u;
      try { u = Uri.parse(s); } catch (_) { u = null; }
      if (u != null) {
        final host = (u.host).toLowerCase();
        if (host.contains('youtu.be')) {
          final id = (u.pathSegments.isNotEmpty) ? u.pathSegments.last : null;
          if (id != null && id.isNotEmpty) return 'https://www.youtube.com/watch?v=$id';
        }
        if (host.contains('youtube.com')) {
          // Solo mantener parámetro v
          final v = u.queryParameters['v'];
          if (v != null && v.isNotEmpty) return 'https://www.youtube.com/watch?v=$v';
        }
      }
      return s;
    } else {
      // Búsqueda textual: colapsar espacios múltiples
      s = s.replaceAll(RegExp(r"\s+"), " ");
      return s;
    }
  }

  // Lee los primeros bytes para comprobar si parece un MP3 (ID3 o frame sync 0xFFEx)
  Future<bool> _isProbableMp3(File file) async {
    try {
      final len = await file.length();
      // tamaño mínimo razonable (10 KB)
      if (len < 10 * 1024) return false;
      final raf = await file.open();
      try {
        final header = await raf.read(4);
        if (header.length >= 3) {
          // ID3 tag
          if (header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33) return true;
        }
        if (header.length >= 2) {
          // MPEG frame sync: 0xFF 0xFB or 0xFF 0xF3 or 0xFF 0xF2
          if (header[0] == 0xFF && ((header[1] & 0xE0) == 0xE0)) return true;
        }
        return false;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  String? _extractFilename(String? contentDisposition) {
    if (contentDisposition == null) return null;
    // Maneja encabezado con encoding: filename*=UTF-8''nombre%20con%20espacios.mp3
    final regex = RegExp(r"filename\*=UTF-8''([^;]+)");
    final matchExt = regex.firstMatch(contentDisposition);
    if (matchExt != null) {
      return Uri.decodeFull(matchExt.group(1)!);
    }

    final simple = RegExp(r'filename="?([^";]+)"?');
    final m2 = simple.firstMatch(contentDisposition);
    if (m2 != null) return m2.group(1);
    return null;
  }
}

// Fin del archivo: BackendClient proporciona downloadSongMp3(...) y helpers.
