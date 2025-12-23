package com.github.festeh.bro_wear.bridge

import com.github.festeh.bro_wear.permission.PermissionManager
import com.github.festeh.bro_wear.service.AudioService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CommandHandler(
    private val permissionManager: PermissionManager
) : MethodChannel.MethodCallHandler {

    private var audioService: AudioService? = null

    fun setAudioService(service: AudioService?) {
        audioService = service
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermission" -> {
                result.success(permissionManager.getPermissionStatus())
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
                result.notImplemented()
            }
        }
    }
}
