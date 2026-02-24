package com.github.festeh.bro

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

class BroVoiceInteractionSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return BroVoiceInteractionSession(this)
    }
}

private class BroVoiceInteractionSession(
    val context: VoiceInteractionSessionService
) : VoiceInteractionSession(context) {

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        // Launch the Flutter activity with assist flag
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_ASSIST
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        context.startActivity(intent)
        hide()
    }
}
