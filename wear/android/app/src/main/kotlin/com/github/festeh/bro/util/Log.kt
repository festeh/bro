package com.github.festeh.bro.util

import android.util.Log as AndroidLog

object L {
    private const val TAG = "BroWear"

    fun d(tag: String, msg: String) {
        AndroidLog.d("$TAG:$tag", msg)
    }

    fun i(tag: String, msg: String) {
        AndroidLog.i("$TAG:$tag", msg)
    }

    fun w(tag: String, msg: String) {
        AndroidLog.w("$TAG:$tag", msg)
    }

    fun e(tag: String, msg: String, t: Throwable? = null) {
        if (t != null) {
            AndroidLog.e("$TAG:$tag", msg, t)
        } else {
            AndroidLog.e("$TAG:$tag", msg)
        }
    }
}
