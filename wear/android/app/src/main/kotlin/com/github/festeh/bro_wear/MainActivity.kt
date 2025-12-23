package com.github.festeh.bro_wear

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.github.festeh.bro_wear.bridge.ChannelManager
import com.github.festeh.bro_wear.service.AudioService

class MainActivity : FlutterActivity() {
    private var audioService: AudioService? = null
    private var channelManager: ChannelManager? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as AudioService.LocalBinder
            audioService = localBinder.getService()
            serviceBound = true
            channelManager?.setAudioService(audioService)
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            audioService = null
            serviceBound = false
            channelManager?.setAudioService(null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelManager = ChannelManager(this, flutterEngine.dartExecutor.binaryMessenger)
        channelManager?.setup()
    }

    override fun onStart() {
        super.onStart()
        Intent(this, AudioService::class.java).also { intent ->
            bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        }
    }

    override fun onStop() {
        super.onStop()
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
    }

    override fun onDestroy() {
        channelManager?.dispose()
        super.onDestroy()
    }
}
