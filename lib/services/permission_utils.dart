import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class PermissionUtils {
  static bool? _storageGrantedCache;

  /// Verificación persistente en memoria: sólo solicita si no está concedido.
  static Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;
    if (_storageGrantedCache == true) return true;
    final channel = const MethodChannel('rexify/media_store');
    try {
      final has = await channel.invokeMethod<bool>('checkStoragePermission');
      if (has == true) {
        _storageGrantedCache = true;
        return true;
      }
      final granted = await channel.invokeMethod<bool>('ensureStoragePermission');
      if (granted == true) {
        _storageGrantedCache = true;
        return true;
      }
    } catch (_) {
      // Fallback: permission_handler (para APIs viejas)
      try {
        final st = await Permission.storage.request();
        if (st.isGranted) {
          _storageGrantedCache = true;
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
  /// Solicita permisos necesarios para descargar/guardar archivos.
  /// publicTarget: si se guardará en almacenamiento público (Descargas/Música) o registrar en MediaStore.
  /// isVideo: orientativo para Android 13+ (permiso de medios específicos al leer, no necesario al escribir via MediaStore).
  static Future<bool> ensureDownloadPermissions({bool publicTarget = true, bool isVideo = false}) async {
    // iOS y otras plataformas no requieren permisos para escribir en directorios de app o compartir al sistema.
    if (!Platform.isAndroid) return true;

    // Android 10+ (API 29+): no se necesita WRITE_EXTERNAL_STORAGE para insertar en MediaStore ni para
    // escribir en directorios específicos de la app. Por compatibilidad, intentamos pedir storage si aplica,
    // pero no bloqueamos si es denegado en sistemas modernos.
    final apiLevel = _guessAndroidApi();

    if (!publicTarget) {
      // Guardado en Documents/temporales de la app: sin permiso.
      return true;
    }

    // Para API <= 28 (Android 9 o menor): se requiere permiso de almacenamiento para escribir en público.
    if (apiLevel != null && apiLevel <= 28) {
      final st = await Permission.storage.request();
      return st.isGranted;
    }

    // Para API >= 29: no bloquear si storage es denegado.
    // API >= 29: usar lógica central de ensureStoragePermission (canal nativo + cache).
    final ok = await ensureStoragePermission();
    if (ok) return true;

    // Aun así, pedimos permiso de notificaciones para mostrar progreso de flutter_downloader en Android 13+.
    try {
      if ((apiLevel ?? 33) >= 33) {
        await Permission.notification.request();
      }
    } catch (_) {}
    return true;
  }

  /// Intenta deducir API Level de Android de la cadena del SO. Puede devolver null si no se puede parsear.
  static int? _guessAndroidApi() {
    try {
      final s = Platform.operatingSystemVersion; // ej: Android 14 (API 34) o similar
      final apiMatch = RegExp(r'API\s*(\d+)').firstMatch(s);
      if (apiMatch != null) {
        return int.tryParse(apiMatch.group(1)!);
      }
      final verMatch = RegExp(r'Android\s*(\d{1,2})').firstMatch(s);
      if (verMatch != null) {
        final major = int.tryParse(verMatch.group(1)!);
        // Mapeo aproximado mayor->API reciente (mejor que nada)
        if (major != null) {
          switch (major) {
            case 13:
              return 33;
            case 12:
              return 31;
            case 11:
              return 30;
            case 10:
              return 29;
            case 9:
              return 28;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Permisos para leer biblioteca local (archivos descargados) en almacenamiento público.
  /// En Android 13+ pide READ_MEDIA_AUDIO; en APIs anteriores pide READ/WRITE_EXTERNAL_STORAGE.
  static Future<bool> ensureLibraryPermissions() async {
    if (!Platform.isAndroid) return true;
    final api = _guessAndroidApi() ?? 33;
    try {
      if (api >= 33) {
        final audio = await Permission.audio.request();
        // notification es útil para controles, no obligatoria
        try { await Permission.notification.request(); } catch (_) {}
        return audio.isGranted;
      }
      // Para APIs antiguas, pedir almacenamiento
      final ok = await ensureStoragePermission();
      return ok;
    } catch (_) {
      return false;
    }
  }
}
