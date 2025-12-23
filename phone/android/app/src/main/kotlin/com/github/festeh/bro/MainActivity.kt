package com.github.festeh.bro

import android.util.Log
import com.github.festeh.bro.storage.SpeechStorage
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.github.festeh.bro/storage"
    }

    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val storage by lazy { SpeechStorage(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "listFiles" -> {
                    mainScope.launch {
                        try {
                            val files = storage.listAll()
                            val filesList = files.map { file ->
                                mapOf(
                                    "path" to file.absolutePath,
                                    "id" to extractId(file),
                                    "timestamp" to extractTimestamp(file),
                                    "sizeBytes" to file.length()
                                )
                            }
                            result.success(filesList)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to list files", e)
                            result.error("LIST_ERROR", e.message, null)
                        }
                    }
                }

                "deleteFile" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARG", "Path is required", null)
                        return@setMethodCallHandler
                    }

                    val file = File(path)
                    val success = storage.delete(file)
                    result.success(success)
                }

                "isWatchConnected" -> {
                    mainScope.launch {
                        try {
                            val nodes = Wearable.getNodeClient(this@MainActivity)
                                .connectedNodes
                                .await()
                            result.success(nodes.isNotEmpty())
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to check watch connection", e)
                            result.success(false)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun extractId(file: File): String {
        // Filename format: {timestamp}_{uuid}.opus
        val name = file.nameWithoutExtension
        val parts = name.split("_", limit = 2)
        return if (parts.size > 1) parts[1] else name
    }

    private fun extractTimestamp(file: File): Long {
        // Filename format: {timestamp}_{uuid}.opus
        val name = file.nameWithoutExtension
        val parts = name.split("_", limit = 2)
        return parts.firstOrNull()?.toLongOrNull() ?: file.lastModified()
    }
}
