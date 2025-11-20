package com.example.reproductor_musica

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.view.KeyEvent
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.RemoteViews
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.io.File

object MusicNotificationManager {
    private const val CHANNEL_ID = "rexify_playback"
    private const val NOTIF_ID = 8123
    // Animación nativa: handler y runnable para actualizar RemoteViews periódicamente
    private var animHandler: android.os.Handler? = null
    private var animRunnable: Runnable? = null
    private var isAnimating = false
    private var lastPlayingState = false

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "Reproducción", NotificationManager.IMPORTANCE_LOW)
                ch.description = "Notificación de reproducción Rexify"
                nm.createNotificationChannel(ch)
            }
        }
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIF_ID)
    }

    fun update(
        context: Context,
        title: String?,
        artist: String?,
        artworkPath: String?,
        positionMs: Long,
        durationMs: Long,
        playing: Boolean
    ) {
        ensureChannel(context)
        val collapsed = RemoteViews(context.packageName, R.layout.notification_music_collapsed)

        collapsed.setTextViewText(R.id.track_title, title ?: "—")
        collapsed.setTextViewText(R.id.artist_name, artist ?: "")

        val current = format(positionMs)
        val total = format(durationMs)
        collapsed.setTextViewText(R.id.current_time, current)
        collapsed.setTextViewText(R.id.remaining_time, total)

        val progress = if (durationMs > 0) ((positionMs * 1000L) / durationMs).toInt().coerceIn(0, 1000) else 0
        collapsed.setProgressBar(R.id.progress_bar, 1000, progress, false)

        // Si está reproduciendo, arrancamos animación nativa periódica que actualizará las barras.
        // Si no, detenemos la animación y dejamos barras en tamaño mínimo.
        if (playing) {
            startAnimationIfNeeded(context, collapsed, positionMs)
        } else {
            stopAnimationIfNeeded()
            intArrayOf(R.id.bar1, R.id.bar2, R.id.bar3, R.id.bar4, R.id.bar5, R.id.bar6, R.id.bar7, R.id.bar8).forEach { id ->
                collapsed.setViewLayoutHeight(id, 6)
            }
        }

        // Artwork
        if (!artworkPath.isNullOrEmpty()) {
            val f = File(artworkPath)
            if (f.exists()) {
                val bmp = BitmapFactory.decodeFile(f.absolutePath)
                collapsed.setImageViewBitmap(R.id.album_art, bmp)
            }
        }
        // Intent para abrir la app al pulsar la notificación
        val intent = Intent(context, MainActivity::class.java)
        val pi = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or pendingFlag())

        // PendingIntents para controles multimedia: enviamos ACTION_MEDIA_BUTTON a la MediaButtonReceiver
        fun mediaButtonPendingIntent(keyCode: Int, reqCode: Int): PendingIntent {
            val keyEventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
            val keyEventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)
            val intentDown = Intent(Intent.ACTION_MEDIA_BUTTON)
            intentDown.component = ComponentName(context.packageName, "com.ryanheise.audioservice.MediaButtonReceiver")
            intentDown.putExtra(Intent.EXTRA_KEY_EVENT, keyEventDown)
            val piDown = PendingIntent.getBroadcast(context, reqCode * 2, intentDown, PendingIntent.FLAG_UPDATE_CURRENT or pendingFlag())

            val intentUp = Intent(Intent.ACTION_MEDIA_BUTTON)
            intentUp.component = ComponentName(context.packageName, "com.ryanheise.audioservice.MediaButtonReceiver")
            intentUp.putExtra(Intent.EXTRA_KEY_EVENT, keyEventUp)
            val piUp = PendingIntent.getBroadcast(context, reqCode * 2 + 1, intentUp, PendingIntent.FLAG_UPDATE_CURRENT or pendingFlag())

            // Devolver un PendingIntent que dispare el DOWN; el sistema y receiver deberían procesar ambos si fuera necesario.
            // Para RemoteViews es suficiente registrar uno; registramos el DOWN intent.
            return piDown
        }

        val piPrev = mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_PREVIOUS, 10)
        val piPlayPause = mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 11)
        val piNext = mediaButtonPendingIntent(KeyEvent.KEYCODE_MEDIA_NEXT, 12)

        // También enviar a nuestro NotificationActionReceiver para que lo reenvíe a Dart
        fun actionPendingIntent(actionName: String, req: Int): PendingIntent {
            val actionIntent = Intent(context, NotificationActionReceiver::class.java)
            actionIntent.putExtra("action", actionName)
            return PendingIntent.getBroadcast(context, req, actionIntent, PendingIntent.FLAG_UPDATE_CURRENT or pendingFlag())
        }

        val piPrevNative = actionPendingIntent("playPrevious", 20)
        val piPlayPauseNative = actionPendingIntent("togglePlayPause", 21)
        val piNextNative = actionPendingIntent("playNext", 22)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pi)
            // Asignar PendingIntents a botones de RemoteViews
            .also { _ ->
                try {
                    // Preferimos que el click dispare nuestro receiver (que reenvía a Dart).
                    collapsed.setOnClickPendingIntent(R.id.btn_prev, piPrevNative)
                    collapsed.setOnClickPendingIntent(R.id.btn_play_pause, piPlayPauseNative)
                    collapsed.setOnClickPendingIntent(R.id.btn_next, piNextNative)
                } catch (_: Exception) { /* algunas API/skins pueden arrojar */ }
            }
            .setOngoing(playing)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(collapsed) // reutilizamos
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        NotificationManagerCompat.from(context).notify(NOTIF_ID, builder.build())
    }

    private fun startAnimationIfNeeded(context: Context, collapsed: RemoteViews, positionMs: Long) {
        if (isAnimating) return
        isAnimating = true
        lastPlayingState = true
        if (animHandler == null) animHandler = android.os.Handler(android.os.Looper.getMainLooper())

        // Runnable que actualiza las barras cada 250ms
        animRunnable = object : Runnable {
            var seedBase = ((positionMs / 250L) % 1000).toInt()
            override fun run() {
                try {
                    val bars = intArrayOf(R.id.bar1, R.id.bar2, R.id.bar3, R.id.bar4, R.id.bar5, R.id.bar6, R.id.bar7, R.id.bar8)
                    bars.forEachIndexed { idx, id ->
                        // generador simple pseudo-aleatorio estable en el tiempo
                        val h = 6 + ((seedBase + idx * 11) % 22)
                        try { collapsed.setViewLayoutHeight(id, h) } catch (_: Exception) { }
                    }
                    // Publicar la notificación actualizada (sólo content view)
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.notify(NOTIF_ID, NotificationCompat.Builder(context, CHANNEL_ID)
                        .setSmallIcon(android.R.drawable.ic_media_play)
                        .setCustomContentView(collapsed)
                        .setCustomBigContentView(collapsed)
                        .setStyle(NotificationCompat.DecoratedCustomViewStyle())
                        .build())
                } catch (_: Exception) { }
                seedBase = (seedBase + 1) % 1000
                animHandler?.postDelayed(this, 250)
            }
        }
        animHandler?.post(animRunnable!!)
    }

    private fun stopAnimationIfNeeded() {
        isAnimating = false
        try {
            animRunnable?.let { animHandler?.removeCallbacks(it) }
        } catch (_: Exception) { }
        animRunnable = null
    }

    private fun format(ms: Long): String {
        if (ms <= 0) return "0:00"
        val totalSeconds = ms / 1000
        val m = totalSeconds / 60
        val s = (totalSeconds % 60).toInt()
        return "$m:" + s.toString().padStart(2, '0')
    }

    private fun pendingFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
    }
}

// Helpers para RemoteViews actualizando altura de View (no existe API directa, usamos Reflection fallback)
private fun RemoteViews.setViewLayoutHeight(viewId: Int, heightDp: Int) {
    // Ajuste mínimo seguro
    val hPx = heightDp
    setInt(viewId, "setLayoutParams", hPx) // Puede no funcionar en todas las versiones, alternativa: usar varias vistas predefinidas
}