package com.github.festeh.bro

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.util.Log
import com.github.festeh.bro.audio.PcmPlayer
import com.github.festeh.bro.bridge.ChatChannelManager
import com.github.festeh.bro.bridge.PingHandler
import com.github.festeh.bro.codec.OpusDecoder
import com.github.festeh.bro.service.AiChatService
import com.github.festeh.bro.storage.SegmentDatabase
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.github.festeh.bro/storage"
    }

    private val mainScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val database by lazy { SegmentDatabase(this) }
    private var pingHandler: PingHandler? = null

    // Audio playback
    private val pcmPlayer by lazy { PcmPlayer() }
    private var currentPlayingId: String? = null

    // Chat service
    private var chatService: AiChatService? = null
    private var chatChannelManager: ChatChannelManager? = null
    private var chatServiceBound = false

    private val chatServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.d(TAG, "Chat service connected")
            val localBinder = binder as AiChatService.LocalBinder
            chatService = localBinder.getService()
            chatServiceBound = true
            chatChannelManager?.setChatService(chatService)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Chat service disconnected")
            chatService = null
            chatServiceBound = false
            chatChannelManager?.setChatService(null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize singleton Opus decoder
        OpusDecoder.init()

        // Setup ping handler
        pingHandler = PingHandler(this)

        // Setup chat channel manager
        chatChannelManager = ChatChannelManager(flutterEngine.dartExecutor.binaryMessenger)
        chatChannelManager?.setup()

        // Start and bind to chat service
        Intent(this, AiChatService::class.java).also { intent ->
            startService(intent)
            bindService(intent, chatServiceConnection, Context.BIND_AUTO_CREATE)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "listSegments" -> {
                    mainScope.launch {
                        try {
                            val segments = database.getAll()
                            val segmentsList = segments.map { segment ->
                                mapOf(
                                    "id" to segment.id,
                                    "timestamp" to segment.timestamp,
                                    "durationMs" to segment.durationMs,
                                    "waveform" to segment.waveform
                                )
                            }
                            result.success(segmentsList)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to list segments", e)
                            result.error("LIST_ERROR", e.message, null)
                        }
                    }
                }

                "playAudio" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("INVALID_ARG", "ID is required", null)
                        return@setMethodCallHandler
                    }

                    mainScope.launch {
                        try {
                            val uuid = UUID.fromString(id)
                            val rawOpusData = database.getAudio(uuid)

                            if (rawOpusData == null) {
                                result.error("NOT_FOUND", "Segment not found", null)
                                return@launch
                            }

                            // Decode Opus to PCM
                            val pcmData = OpusDecoder.decodeRawFrames(rawOpusData)
                            Log.d(TAG, "Decoded ${rawOpusData.size} bytes to ${pcmData.size} PCM samples")

                            // Track which segment is playing
                            currentPlayingId = id

                            // Play via AudioTrack
                            pcmPlayer.play(pcmData)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to play audio", e)
                            result.error("AUDIO_ERROR", e.message, null)
                        }
                    }
                }

                "stopAudio" -> {
                    pcmPlayer.stop()
                    currentPlayingId = null
                    result.success(true)
                }

                "pauseAudio" -> {
                    pcmPlayer.pause()
                    result.success(true)
                }

                "getCurrentPlayingId" -> {
                    result.success(currentPlayingId)
                }

                "resumeAudio" -> {
                    pcmPlayer.resume()
                    result.success(true)
                }

                "getPlaybackPosition" -> {
                    result.success(pcmPlayer.getPositionMs())
                }

                "isPlaying" -> {
                    result.success(pcmPlayer.isPlaying())
                }

                "deleteSegment" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("INVALID_ARG", "ID is required", null)
                        return@setMethodCallHandler
                    }

                    mainScope.launch {
                        try {
                            val uuid = UUID.fromString(id)
                            val success = database.delete(uuid)
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to delete segment", e)
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    }
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

                "pingWatch" -> {
                    mainScope.launch {
                        try {
                            val success = pingHandler?.pingWatch() ?: false
                            Log.d(TAG, "Ping result: $success")
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to ping watch", e)
                            result.success(false)
                        }
                    }
                }

                "clearAll" -> {
                    mainScope.launch {
                        try {
                            val deleted = database.clearAll()
                            Log.d(TAG, "Cleared $deleted segments")
                            result.success(deleted)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to clear all", e)
                            result.error("CLEAR_ERROR", e.message, null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        pcmPlayer.release()
        if (chatServiceBound) {
            unbindService(chatServiceConnection)
            chatServiceBound = false
        }
        chatChannelManager?.dispose()
        pingHandler?.dispose()
        pingHandler = null
        super.onDestroy()
    }
}
