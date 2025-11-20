package com.example.reproductor_musica

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.util.Log

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            // Prefer explicit 'action' extra
            val act = intent.getStringExtra("action")
            if (!act.isNullOrEmpty()) {
                FlutterChannelHolder.sendAction(act)
                return
            }

            // Fallback: handle media button intents
            if (intent.action == Intent.ACTION_MEDIA_BUTTON) {
                val ke = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                if (ke != null && ke.action == KeyEvent.ACTION_DOWN) {
                    when (ke.keyCode) {
                        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY -> FlutterChannelHolder.sendAction("togglePlayPause")
                        KeyEvent.KEYCODE_MEDIA_PAUSE -> FlutterChannelHolder.sendAction("pause")
                        KeyEvent.KEYCODE_MEDIA_NEXT -> FlutterChannelHolder.sendAction("playNext")
                        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> FlutterChannelHolder.sendAction("playPrevious")
                        else -> FlutterChannelHolder.sendAction("unknown")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("NotificationActionReceiver", "failed to forward action", e)
        }
    }
}
