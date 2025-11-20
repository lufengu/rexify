import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class PermissionUtils {
  static bool? _storageGrantedCache;

  /// Verificación persistente en memoria: sólo solicita si no está concedido.
  static Future<bool> ensureStoragePermission() async {
    // En web no pedimos permisos
    if (kIsWeb) return true;
    // Si no es Android tampoco hace falta (escribir en app dir)
    if (!Platform.isAndroid) return true;
    if (_storageGrantedCache == true) return true;
    final channel = const MethodChannel('rexify/media_store');
    try {
      final granted = await channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
      _storageGrantedCache = granted;
      return granted;
    } catch (_) {
      // Si falla el canal nativo, devolvemos false para que el caller intente fallback.
      return false;
    }
  }
  /// Solicita permisos necesarios para descargar/guardar archivos.
  /// publicTarget: si se guardará en almacenamiento público (Descargas/Música) o registrar en MediaStore.
  /// isVideo: orientativo para Android 13+ (permiso de medios específicos al leer, no necesario al escribir via MediaStore).
  static Future<bool> ensureDownloadPermissions({bool publicTarget = true, bool isVideo = false}) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;

    final apiLevel = _guessAndroidApi();

    // Si sólo se guarda en directorio privado de la app, no necesitamos permisos adicionales.
    if (!publicTarget) return true;

    // Android <= 9 (API <= 28) requiere WRITE_EXTERNAL_STORAGE
    if (apiLevel != null && apiLevel <= 28) {
      final st = await Permission.storage.request();
      return st.isGranted;
    }

    // Para Android modernos intentamos usar el canal nativo (All files / MediaStore)
    final ok = await ensureStoragePermission();
    if (ok) return true;

    // Intentamos pedir permiso de notificaciones (Android 13+) para progreso de descarga.
    try {
      if (apiLevel != null && apiLevel >= 33) {
        await Permission.notification.request();
      }
    } catch (_) {}
    // Devolvemos true para no bloquear en plataformas modernas si no se puede forzar permiso.
    return true;
  }

  /// Intenta deducir API Level de Android de la cadena del SO. Puede devolver null si no se puede parsear.
  static int? _guessAndroidApi() {
    if (kIsWeb) return null;
    try {
      final v = Platform.operatingSystemVersion;
      // Ejemplos: "Android 13 (SDK 33)" o cadenas similares
      final m = RegExp(r'\bSDK\s*(\d+)\b').firstMatch(v) ?? RegExp(r'Android\s+(\d+)').firstMatch(v);
      if (m != null) return int.tryParse(m.group(1)!);
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
