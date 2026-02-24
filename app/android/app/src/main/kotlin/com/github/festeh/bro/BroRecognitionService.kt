package com.github.festeh.bro

import android.content.Intent
import android.speech.RecognitionService

class BroRecognitionService : RecognitionService() {
    override fun onStartListening(intent: Intent?, callback: Callback?) {}
    override fun onCancel(callback: Callback?) {}
    override fun onStopListening(callback: Callback?) {}
}
