package com.example.reproductor_musica

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

// Extend the audio service activity so plugin behaviour remains
class MainActivity : com.ryanheise.audioservice.AudioServiceActivity() {
    private val CHANNEL = "rexify/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
    }
}
