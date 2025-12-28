package com.github.festeh.bro_wear.bridge

import android.app.Activity
import com.github.festeh.bro_wear.permission.PermissionManager
import com.github.festeh.bro_wear.service.AudioService
import com.github.festeh.bro_wear.util.L
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class ChannelManager(
    activity: Activity,
    private val messenger: BinaryMessenger
) {
    companion object {
        private const val TAG = "ChannelManager"
        private const val EVENT_CHANNEL = "com.github.festeh.bro_wear/vad_state"
        private const val METHOD_CHANNEL = "com.github.festeh.bro_wear/commands"
    }

    private val permissionManager = PermissionManager(activity)
    private val vadStateStream = VadStateStream()
    private val commandHandler = CommandHandler(permissionManager)

    private var eventChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null

    fun setup() {
        L.d(TAG, "setup start")
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(vadStateStream)
        }

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler(commandHandler)
        }
        L.d(TAG, "setup done")
    }

    fun setAudioService(service: AudioService?) {
        L.d(TAG, "setAudioService: ${service != null}")
        commandHandler.setAudioService(service)
        service?.setVadStateStream(vadStateStream)
    }

    fun notifyPermissionDenied() {
        L.d(TAG, "notifyPermissionDenied")
        methodChannel?.invokeMethod("onPermissionDenied", null)
    }

    fun dispose() {
        L.d(TAG, "dispose")
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel = null
        methodChannel = null
    }
}
