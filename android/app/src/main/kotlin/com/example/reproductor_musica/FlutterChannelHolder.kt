package com.example.reproductor_musica

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object FlutterChannelHolder {
    private var messenger: BinaryMessenger? = null

    fun init(messenger: BinaryMessenger) {
        this.messenger = messenger
    }

    fun sendAction(action: String, payload: Map<String, Any?>? = null) {
        try {
            val m = messenger ?: return
            val channel = MethodChannel(m, "rexify/media_actions")
            val args = mutableMapOf<String, Any?>()
            args["action"] = action
            if (payload != null) args["payload"] = payload
            channel.invokeMethod("onMediaAction", args)
        } catch (_: Exception) {
            // ignore
        }
    }
}
