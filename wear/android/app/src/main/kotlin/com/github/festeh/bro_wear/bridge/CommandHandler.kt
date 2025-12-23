package com.github.festeh.bro_wear.bridge

import com.github.festeh.bro_wear.permission.PermissionManager
import com.github.festeh.bro_wear.service.AudioService
import com.github.festeh.bro_wear.util.L
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CommandHandler(
    private val permissionManager: PermissionManager
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "CommandHandler"
    }

    private var audioService: AudioService? = null

    fun setAudioService(service: AudioService?) {
        L.d(TAG, "setAudioService: ${service != null}")
        audioService = service
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        L.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "checkPermission" -> {
                val status = permissionManager.getPermissionStatus()
                L.d(TAG, "checkPermission: $status")
                result.success(status)
            }
            "requestPermission" -> {
                permissionManager.requestRecordPermission()
                result.success(true)
            }
            "openSettings" -> {
                permissionManager.openAppSettings()
                result.success(true)
            }
            "start" -> {
                val success = audioService?.startListening() ?: false
                L.d(TAG, "start: $success")
                result.success(success)
            }
            "stop" -> {
                audioService?.stopListening()
                result.success(true)
            }
            "getStatus" -> {
                result.success(mapOf(
                    "isListening" to (audioService?.isListening() ?: false),
                    "hasPermission" to permissionManager.hasRecordPermission()
                ))
            }
            else -> {
                L.w(TAG, "Unknown method: ${call.method}")
                result.notImplemented()
            }
        }
    }
}
