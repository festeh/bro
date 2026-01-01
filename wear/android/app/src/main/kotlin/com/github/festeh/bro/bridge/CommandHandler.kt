package com.github.festeh.bro.bridge

import android.content.Context
import com.github.festeh.bro.permission.PermissionManager
import com.github.festeh.bro.service.AudioService
import com.github.festeh.bro.util.L
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class CommandHandler(
    private val context: Context,
    private val permissionManager: PermissionManager
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "CommandHandler"
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
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
            "isPhoneConnected" -> {
                scope.launch {
                    try {
                        val nodes = Wearable.getNodeClient(context)
                            .connectedNodes
                            .await()
                        L.d(TAG, "isPhoneConnected: ${nodes.isNotEmpty()}")
                        result.success(nodes.isNotEmpty())
                    } catch (e: Exception) {
                        L.e(TAG, "Failed to check phone connection: ${e.message}")
                        result.success(false)
                    }
                }
            }
            else -> {
                L.w(TAG, "Unknown method: ${call.method}")
                result.notImplemented()
            }
        }
    }
}
