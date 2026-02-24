package com.github.festeh.bro

import android.app.role.RoleManager
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.github.festeh.bro/assistant"
    private val EVENT_CHANNEL = "com.github.festeh.bro/assistant_events"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLaunchedFromAssist" -> {
                        result.success(isAssistIntent(intent))
                    }
                    "requestAssistantRole" -> {
                        val roleManager = getSystemService(RoleManager::class.java)
                        if (roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                            if (roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
                                // Check if voice_interaction_service is properly configured.
                                // On some devices, holding the role doesn't automatically
                                // populate this setting (e.g. when set via adb or system UI).
                                val vis = Settings.Secure.getString(
                                    contentResolver, "voice_interaction_service"
                                )
                                if (vis.isNullOrEmpty()) {
                                    result.success("misconfigured")
                                } else {
                                    result.success("already_held")
                                }
                            } else {
                                val roleIntent = roleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT)
                                startActivityForResult(roleIntent, REQUEST_ROLE_CODE)
                                result.success("requested")
                            }
                        } else {
                            result.success("unavailable")
                        }
                    }
                    "openAssistantSettings" -> {
                        val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isAssistIntent(intent)) {
            eventSink?.success("assist")
        }
    }

    private fun isAssistIntent(intent: Intent?): Boolean {
        return intent?.action == Intent.ACTION_ASSIST
    }

    companion object {
        private const val REQUEST_ROLE_CODE = 1001
    }
}
