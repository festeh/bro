package com.github.festeh.bro.power

import android.content.Context
import android.os.PowerManager

class WakeLockManager(context: Context) {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var wakeLock: PowerManager.WakeLock? = null

    fun acquireForWrite(timeoutMs: Long = 10_000L) {
        if (wakeLock == null) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "bro_wear:speech_write"
            )
        }
        if (wakeLock?.isHeld == false) {
            wakeLock?.acquire(timeoutMs)
        }
    }

    fun release() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
    }

    fun isHeld(): Boolean = wakeLock?.isHeld == true
}
