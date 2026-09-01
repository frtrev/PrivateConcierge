package com.neotheone.privateconcierge.car

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.neotheone.privateconcierge.CarNotification
import java.util.Locale

class CarNotificationScreen(
    carContext: CarContext,
    private val notification: CarNotification
) : Screen(carContext) {
    private var textToSpeech: TextToSpeech? = null
    private var speechFinished = false
    private val canNavigate = notification.action == "directions" &&
        notification.latitude != null && notification.longitude != null

    init {
        prepareAndRead()
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                textToSpeech?.stop()
                textToSpeech?.shutdown()
                textToSpeech = null
            }
        })
    }

    override fun onGetTemplate(): Template {
        if (!speechFinished) {
            return MessageTemplate.Builder("Preparing and reading ${notification.title}…")
                .setTitle("Thinking, please wait…")
                .setIcon(CarIcon.ALERT)
                .setLoading(true)
                .build()
        }
        val message = if (canNavigate) {
            "Would you like to navigate to ${notification.placeName ?: notification.title}?"
        } else {
            notification.body
        }
        val template = MessageTemplate.Builder(message)
            .setTitle(notification.title)
            .setHeaderAction(Action.BACK)
        if (canNavigate) {
            template.addAction(
                Action.Builder().setTitle("Navigate").setOnClickListener { navigate() }.build()
            )
        }
        template.addAction(
            Action.Builder().setTitle("Go Back").setOnClickListener { finish() }.build()
        )
        return template.build()
    }

    private fun prepareAndRead() {
        val place = notification.placeName ?: notification.title
        var spoken = listOf(notification.title, notification.body)
            .filter { it.isNotBlank() }.joinToString(". ")
        if (canNavigate) spoken += ". Would you like to navigate to $place?"
        val preferences = carContext.getSharedPreferences("charon_speech", Context.MODE_PRIVATE)
        val engineId = preferences.getString("engine_id", null)
        var created: TextToSpeech? = null
        created = TextToSpeech(carContext, { status ->
            val tts = created
            if (status != TextToSpeech.SUCCESS || tts == null) {
                finishSpeech()
                return@TextToSpeech
            }
            val voiceId = preferences.getString("voice_id", null)
            if (voiceId?.startsWith("locale:") == true) {
                tts.language = Locale.forLanguageTag(voiceId.removePrefix("locale:"))
            } else if (voiceId != null && voiceId != "system:default") {
                tts.voice = tts.voices?.firstOrNull { it.name == voiceId }
            }
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) = finishSpeech()
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = finishSpeech()
                override fun onError(utteranceId: String?, errorCode: Int) = finishSpeech()
            })
            textToSpeech = tts
            if (tts.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, "charon-notification") ==
                TextToSpeech.ERROR
            ) finishSpeech()
        }, engineId)
    }

    private fun finishSpeech() {
        Handler(Looper.getMainLooper()).post {
            if (speechFinished) return@post
            speechFinished = true
            invalidate()
        }
    }

    private fun navigate() {
        val latitude = notification.latitude ?: return
        val longitude = notification.longitude ?: return
        val name = notification.placeName ?: notification.title
        val destination = Uri.parse(
            "geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encode(name)})"
        )
        carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, destination))
    }
}
