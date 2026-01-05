package com.github.festeh.bro.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.github.festeh.bro.MainActivity
import com.github.festeh.bro.R
import com.github.festeh.bro.audio.AudioCapture
import com.github.festeh.bro.audio.PreRollBuffer
import com.github.festeh.bro.audio.SpeechBuffer
import com.github.festeh.bro.audio.SpeechSegment
import com.github.festeh.bro.bridge.VadStateStream
import com.github.festeh.bro.codec.OpusEncoder
import com.github.festeh.bro.power.WakeLockManager
import com.github.festeh.bro.sync.SpeechDataSender
import com.github.festeh.bro.vad.VadConfig
import com.github.festeh.bro.vad.VadResult
import com.github.festeh.bro.vad.VadStatus
import com.github.festeh.bro.vad.WebRtcVadEngine
import com.github.festeh.bro.util.L
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AudioService : Service() {

    companion object {
        private const val TAG = "AudioService"
        private const val CHANNEL_ID = "bro_wear_audio"
        private const val NOTIFICATION_ID = 1
    }

    private val binder = LocalBinder()
    private var vadStateStream: VadStateStream? = null

    private val config = VadConfig()
    private val vadEngine = WebRtcVadEngine()
    private var audioCapture: AudioCapture? = null
    private lateinit var preRollBuffer: PreRollBuffer
    private lateinit var speechBuffer: SpeechBuffer
    private lateinit var wakeLockManager: WakeLockManager
    private lateinit var opusEncoder: OpusEncoder
    private lateinit var dataSender: SpeechDataSender

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)

    private var isInSpeech = false
    private var silenceStartTime: Long = 0
    private var listening = false
    private val vadWindow = ArrayDeque<Boolean>(config.triggerWindow)

    private fun addToVadWindow(isSpeech: Boolean) {
        if (vadWindow.size >= config.triggerWindow) {
            vadWindow.removeFirst()
        }
        vadWindow.addLast(isSpeech)
    }

    private fun speechCountInWindow(): Int = vadWindow.count { it }

    inner class LocalBinder : Binder() {
        fun getService(): AudioService = this@AudioService
    }

    override fun onCreate() {
        L.d(TAG, "onCreate start")
        super.onCreate()
        createNotificationChannel()
        preRollBuffer = PreRollBuffer(config.sampleRate, config.preRollMs)
        speechBuffer = SpeechBuffer(config.sampleRate, config.maxSpeechMs)
        wakeLockManager = WakeLockManager(this)
        opusEncoder = OpusEncoder()
        opusEncoder.init()
        dataSender = SpeechDataSender(this)
        L.d(TAG, "onCreate done")
    }

    override fun onBind(intent: Intent?): IBinder {
        L.d(TAG, "onBind")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        L.d(TAG, "onStartCommand")
        startForegroundService()
        return START_STICKY
    }

    fun setVadStateStream(stream: VadStateStream?) {
        vadStateStream = stream
    }

    fun startListening(): Boolean {
        L.d(TAG, "startListening called, listening=$listening")
        if (listening) return true

        vadEngine.start(config)
        L.d(TAG, "VAD engine started")

        audioCapture = AudioCapture(config) { audioFrame ->
            processAudioFrame(audioFrame)
        }

        if (!audioCapture!!.start()) {
            L.e(TAG, "AudioCapture failed to start")
            vadEngine.stop()
            return false
        }

        listening = true
        L.d(TAG, "startListening success")
        vadStateStream?.emitStatus(VadStatus.LISTENING)
        return true
    }

    fun stopListening() {
        L.d(TAG, "stopListening called, listening=$listening")
        if (!listening) return

        listening = false
        audioCapture?.stop()
        audioCapture = null
        vadEngine.stop()

        // Discard any pending speech (don't send incomplete segments)
        if (isInSpeech) {
            L.d(TAG, "Discarding incomplete segment on stopListening")
            speechBuffer.clear()
            wakeLockManager.release()
        }

        // Reset all state
        isInSpeech = false
        silenceStartTime = 0
        vadWindow.clear()
        preRollBuffer.clear()
        vadStateStream?.emitStatus(VadStatus.IDLE)
        L.d(TAG, "stopListening done")
    }

    fun isListening(): Boolean = listening

    private fun processAudioFrame(audioFrame: ShortArray) {
        // Always write to pre-roll buffer
        preRollBuffer.write(audioFrame)

        val result = vadEngine.process(audioFrame)
        // Don't emit every frame - causes UI flickering

        if (result.isSpeech) {
            handleSpeechDetected(audioFrame)
        } else {
            handleSilenceDetected(audioFrame)
        }
    }

    private fun handleSpeechDetected(audioFrame: ShortArray) {
        addToVadWindow(true)

        if (!isInSpeech) {
            if (speechCountInWindow() >= config.triggerThreshold) {
                // Confirmed speech - start recording
                isInSpeech = true
                vadStateStream?.emitStatus(VadStatus.SPEECH)
                wakeLockManager.acquireForWrite()
                val preRoll = preRollBuffer.flush()
                speechBuffer.start(preRoll, config.preRollMs)
                // Note: current frame is already in preRoll, don't append again
            }
            // else: not enough speech frames in window yet, keep waiting
            return
        }

        speechBuffer.append(audioFrame)
        silenceStartTime = 0

        // Check max duration
        if (speechBuffer.isMaxDurationReached()) {
            finalizeSpeechSegment("maxDuration_speech")
            isInSpeech = false
            vadStateStream?.emitStatus(VadStatus.LISTENING)
            vadWindow.clear()
            wakeLockManager.release()
        }
    }

    private fun handleSilenceDetected(audioFrame: ShortArray) {
        addToVadWindow(false)  // Keep window accurate even during silence

        if (!isInSpeech) return

        // Keep appending audio during silence timeout - this audio might still contain speech
        speechBuffer.append(audioFrame)

        // Check max duration first
        if (speechBuffer.isMaxDurationReached()) {
            finalizeSpeechSegment("maxDuration_silence")
            isInSpeech = false
            vadStateStream?.emitStatus(VadStatus.LISTENING)
            silenceStartTime = 0
            vadWindow.clear()
            wakeLockManager.release()
            return
        }

        if (silenceStartTime == 0L) {
            silenceStartTime = System.currentTimeMillis()
        }

        val silenceDuration = System.currentTimeMillis() - silenceStartTime
        if (silenceDuration >= config.silenceTimeoutMs) {
            finalizeSpeechSegment("silenceTimeout")
            isInSpeech = false
            vadStateStream?.emitStatus(VadStatus.LISTENING)
            silenceStartTime = 0
            vadWindow.clear()
            wakeLockManager.release()
        }
    }

    private fun finalizeSpeechSegment(reason: String = "unknown") {
        val segment = speechBuffer.toSegment()
        L.d(TAG, "Finalizing segment: reason=$reason, duration=${segment.durationMs}ms")

        // Encode to Opus
        val opusData = try {
            opusEncoder.encode(segment.data)
        } catch (e: Exception) {
            L.e(TAG, "Failed to encode segment: ${e.message}")
            speechBuffer.clear()
            return
        }

        val encodedSegment = segment.copy(opusData = opusData)
        val compressionRatio = segment.data.size * 2f / opusData.size

        L.d(TAG, "Speech segment: ${segment.durationMs}ms, " +
            "PCM: ${segment.data.size * 2} bytes, " +
            "Opus: ${opusData.size} bytes, " +
            "ratio: %.1fx".format(compressionRatio))

        // Send to phone asynchronously
        serviceScope.launch {
            val success = dataSender.send(encodedSegment)
            if (success) {
                L.d(TAG, "Segment ${segment.id} sent to phone")
            } else {
                L.e(TAG, "Failed to send segment ${segment.id}")
            }
        }

        speechBuffer.clear()
    }

    private fun startForegroundService() {
        val notification = createNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Audio Listening",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Voice activity detection service"
            setShowBadge(false)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Bro")
            .setContentText("Listening...")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        L.d(TAG, "onDestroy")
        stopListening()
        opusEncoder.release()
        serviceJob.cancel()
        super.onDestroy()
    }
}
