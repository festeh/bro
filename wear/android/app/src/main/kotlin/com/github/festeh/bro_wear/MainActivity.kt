package com.github.festeh.bro_wear

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.github.festeh.bro_wear.bridge.ChannelManager
import com.github.festeh.bro_wear.service.AudioService
import com.github.festeh.bro_wear.util.L

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
    }

    private var audioService: AudioService? = null
    private var channelManager: ChannelManager? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            L.d(TAG, "onServiceConnected")
            val localBinder = binder as AudioService.LocalBinder
            audioService = localBinder.getService()
            serviceBound = true
            channelManager?.setAudioService(audioService)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            L.d(TAG, "onServiceDisconnected")
            audioService = null
            serviceBound = false
            channelManager?.setAudioService(null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        L.d(TAG, "onCreate")
        super.onCreate(savedInstanceState)
        // Keep screen on to prevent WearOS ambient mode from killing the app
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Start foreground service immediately to mark app as "ongoing"
        // This prevents WearOS AutoResume from backgrounding the app
        Intent(this, AudioService::class.java).also { intent ->
            startForegroundService(intent)
        }
        L.d(TAG, "foreground service started")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        L.d(TAG, "configureFlutterEngine start")
        super.configureFlutterEngine(flutterEngine)
        channelManager = ChannelManager(this, flutterEngine.dartExecutor.binaryMessenger)
        channelManager?.setup()
        L.d(TAG, "configureFlutterEngine done")

        // Bind to the service for communication
        Intent(this, AudioService::class.java).also { intent ->
            bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        }
        L.d(TAG, "service binding initiated")
    }

    override fun onStart() {
        L.d(TAG, "onStart")
        super.onStart()
    }

    override fun onStop() {
        L.d(TAG, "onStop")
        super.onStop()
    }

    override fun onDestroy() {
        L.d(TAG, "onDestroy")
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        channelManager?.dispose()
        super.onDestroy()
    }
}
