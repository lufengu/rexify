package com.example.reproductor_musica

import android.app.AlertDialog
import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

// Extend the audio service activity so plugin behaviour remains
class MainActivity : com.ryanheise.audioservice.AudioServiceActivity() {
    private val CHANNEL = "rexify/media_store"
    private var permissionResult: MethodChannel.Result? = null
    private val REQUEST_STORAGE = 9999
    private val PREFS = "rexify_prefs"
    private val KEY_STORAGE_GRANTED = "storage_granted"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Inicializar holder para que los receivers nativos puedan enviar eventos a Dart
        try {
            FlutterChannelHolder.init(flutterEngine.dartExecutor.binaryMessenger)
        } catch (_: Exception) { }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            MediaScannerConnection.scanFile(this, arrayOf(path), null) { _, uri ->
                                // no-op
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("scan_error", e.message, null)
                        }
                    } else {
                        result.error("invalid_args", "path is required", null)
                    }
                }
                "saveToMediaStore" -> {
                    val path = call.argument<String>("path")
                    val displayName = call.argument<String>("displayName") ?: File(path ?: "").name
                    val mime = call.argument<String>("mime") ?: "audio/mpeg"
                    if (path == null) {
                        result.error("invalid_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.MediaColumns.RELATIVE_PATH, "Music/Rexify")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                        }
                        val collection: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                        } else {
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                        }
                        val resolver = contentResolver
                        val uri = resolver.insert(collection, values)
                        if (uri == null) {
                            result.error("insert_failed", "Could not create media entry", null)
                            return@setMethodCallHandler
                        }

                        var out: OutputStream? = null
                        var input: FileInputStream? = null
                        try {
                            out = resolver.openOutputStream(uri)
                            input = FileInputStream(file)
                            val buf = ByteArray(4096)
                            var read: Int
                            while (input.read(buf).also { read = it } > 0) {
                                out?.write(buf, 0, read)
                            }
                        } finally {
                            out?.close()
                            input?.close()
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            values.clear()
                            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(uri, values, null, null)
                        }

                        // Ensure media scanner picks it up on older devices
                        MediaScannerConnection.scanFile(this, arrayOf(path), arrayOf(mime)) { _, _ -> }

                        result.success(uri.toString())
                    } catch (e: Exception) {
                        Log.e("MainActivity", "saveToMediaStore error", e)
                        result.error("save_error", e.message, null)
                    }
                }
                "checkStoragePermission" -> {
                    val granted = hasStoragePermission()
                    result.success(granted)
                }
                "requestStoragePermission" -> {
                    // Guarda el result para responder cuando onRequestPermissionsResult reciba el callback
                    permissionResult = result
                    requestStoragePermission()
                }
                "ensureStoragePermission" -> {
                    val granted = hasStoragePermission()
                    if (granted) {
                        cacheGranted(true)
                        result.success(true)
                    } else {
                        permissionResult = result
                        requestStoragePermission()
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Canal para notificación personalizada de reproducción
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rexify/custom_notif").setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title")
                    val artist = call.argument<String>("artist")
                    val artworkPath = call.argument<String>("artworkPath")
                    val positionMs = call.argument<Long>("positionMs") ?: 0L
                    val durationMs = call.argument<Long>("durationMs") ?: 0L
                    val playing = call.argument<Boolean>("playing") ?: false
                    try {
                        MusicNotificationManager.update(
                            this,
                            title,
                            artist,
                            artworkPath,
                            positionMs,
                            durationMs,
                            playing
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("notif_error", e.message, null)
                    }
                }
                "hide" -> {
                    MusicNotificationManager.hide(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Comprueba si el app tiene permisos de almacenamiento necesarios
    private fun hasStoragePermission(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                // Android 11+ usa MANAGE_EXTERNAL_STORAGE
                android.os.Environment.isExternalStorageManager()
            } catch (e: Exception) {
                false
            }
        } else {
            val read = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE)
            read == PackageManager.PERMISSION_GRANTED
        }
        if (granted) cacheGranted(true)
        return granted
    }

    // Solicita permisos de almacenamiento. En Android 11+ abre la pantalla de ajustes para conceder "All files access".
    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Mostrar diálogo explicativo antes de dirigir a ajustes
            AlertDialog.Builder(this)
                .setTitle("Permiso de almacenamiento requerido")
                .setMessage("Rexify necesita permiso para guardar y acceder a archivos para gestionar descargas. Pulsa " +
                        "Aceptar para abrir la configuración y conceder el permiso de acceso a todos los archivos.")
                .setNegativeButton("Cancelar") { dialog, _ ->
                    permissionResult?.success(false)
                    permissionResult = null
                    dialog.dismiss()
                }
                .setPositiveButton("Aceptar") { _, _ ->
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                        intent.data = Uri.parse("package:" + packageName)
                        startActivityForResult(intent, REQUEST_STORAGE)
                    } catch (e: Exception) {
                        // fallback: abrir ajustes de la app
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = Uri.parse("package:" + packageName)
                        startActivityForResult(intent, REQUEST_STORAGE)
                    }
                }
                .show()
        } else {
            val permissions = arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            // Si ya deberíamos mostrar una explicación, mostrar diálogo antes de solicitar
            val shouldExplain = ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_EXTERNAL_STORAGE)
            if (shouldExplain) {
                AlertDialog.Builder(this)
                    .setTitle("Permiso requerido")
                    .setMessage("Rexify necesita permiso para leer y guardar archivos en tu dispositivo para poder descargar medios.")
                    .setNegativeButton("Cancelar") { dialog, _ ->
                        permissionResult?.success(false)
                        permissionResult = null
                        dialog.dismiss()
                    }
                    .setPositiveButton("Continuar") { _, _ ->
                        ActivityCompat.requestPermissions(this, permissions, REQUEST_STORAGE)
                    }
                    .show()
            } else {
                ActivityCompat.requestPermissions(this, permissions, REQUEST_STORAGE)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            cacheGranted(granted)
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_STORAGE) {
            // Tras volver de la pantalla de ajustes, comprobar si ahora tenemos permiso
            val granted = hasStoragePermission()
            cacheGranted(granted)
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun cacheGranted(granted: Boolean) {
        try {
            val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
            prefs.edit().putBoolean(KEY_STORAGE_GRANTED, granted).apply()
        } catch (_: Exception) { }
    }
}
