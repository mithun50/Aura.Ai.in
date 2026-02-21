package com.aura.mobile.aura_mobile.assistant

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class TtsManager(context: Context, private val onInitCompleted: () -> Unit) : TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var isInitialized = false
    private var utteranceCounter = 0
    private var lastQueuedId: String? = null
    private var onDoneCallback: (() -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        tts = TextToSpeech(context, this)
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.US)
            if (result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED) {
                isInitialized = true

                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}

                    override fun onDone(utteranceId: String?) {
                        if (utteranceId != null && utteranceId == lastQueuedId) {
                            val cb = onDoneCallback
                            if (cb != null) {
                                onDoneCallback = null
                                mainHandler.post { cb() }
                            }
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {}
                })

                onInitCompleted()
            }
        }
    }

    fun speak(text: String, utteranceId: String? = null) {
        if (isInitialized) {
            val id = utteranceId ?: "utt_${utteranceCounter++}"
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        }
    }

    /** Queue speech without flushing previous utterances — used for streaming chunks. */
    fun speakQueued(text: String) {
        if (isInitialized) {
            val id = "utt_${utteranceCounter++}"
            lastQueuedId = id
            tts?.speak(text, TextToSpeech.QUEUE_ADD, null, id)
        }
    }

    /** Register a callback that fires when the last queued utterance finishes speaking. */
    fun onAllSpoken(callback: () -> Unit) {
        if (lastQueuedId == null) {
            // Nothing was queued, fire immediately
            mainHandler.post { callback() }
        } else {
            onDoneCallback = callback
        }
    }

    fun stop() {
        tts?.stop()
        onDoneCallback = null
        lastQueuedId = null
    }

    fun shutdown() {
        tts?.stop()
        tts?.shutdown()
        onDoneCallback = null
        lastQueuedId = null
    }
}
