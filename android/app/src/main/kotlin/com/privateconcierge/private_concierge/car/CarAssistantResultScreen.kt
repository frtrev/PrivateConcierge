package com.neotheone.privateconcierge.car

import android.content.Intent
import android.net.Uri
import android.speech.tts.TextToSpeech
import android.content.Context
import java.util.Locale
import java.text.SimpleDateFormat
import java.util.Date
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

class CarAssistantResultScreen(
    carContext: CarContext,
    private val payload: Map<String, Any?>,
    private val offset: Int = 0
) : Screen(carContext) {
    private var textToSpeech: TextToSpeech? = null

    init {
        val spoken = payload["spokenResponse"] as? String
            ?: payload["response"] as? String
            ?: "Charon finished the request."
        val preferences = carContext.getSharedPreferences("charon_speech", Context.MODE_PRIVATE)
        val engineId = preferences.getString("engine_id", null)
            ?: GOOGLE_TTS_PACKAGE.takeIf { packageName ->
                runCatching {
                    carContext.packageManager.getPackageInfo(packageName, 0)
                }.isSuccess
            }
        textToSpeech = TextToSpeech(carContext, { status ->
            if (status == TextToSpeech.SUCCESS) {
                val voiceId = preferences.getString("voice_id", null)
                if (voiceId == "system:default") {
                    // Keep the engine-selected default voice configured by the user.
                } else if (voiceId?.startsWith("locale:") == true) {
                    textToSpeech?.language = Locale.forLanguageTag(voiceId.removePrefix("locale:"))
                } else {
                    textToSpeech?.voice = textToSpeech?.voices?.firstOrNull { it.name == voiceId }
                }
                textToSpeech?.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, "charon-result")
            }
        }, engineId)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                textToSpeech?.stop()
                textToSpeech?.shutdown()
                textToSpeech = null
            }
        })
    }

    override fun onGetTemplate(): Template {
        val response = payload["spokenResponse"] as? String
            ?: payload["response"] as? String
            ?: "Charon finished the request."
        val places = places()
        if (places.size > 1) {
            val items = ItemList.Builder()
            places.drop(offset).take(PAGE_SIZE).forEach { place ->
                items.addItem(
                    Row.Builder()
                        .setTitle(place.name)
                        .addText(place.detail)
                        .setOnClickListener {
                            screenManager.push(CarPlaceResultScreen(carContext, place))
                        }
                        .build()
                )
            }
            if (offset + PAGE_SIZE < places.size) {
                items.addItem(
                    Row.Builder()
                        .setTitle("More results")
                        .addText("Show the next nearby places")
                        .setOnClickListener {
                            screenManager.push(
                                CarAssistantResultScreen(
                                    carContext,
                                    payload,
                                    offset + PAGE_SIZE
                                )
                            )
                        }
                        .build()
                )
            }
            items.addItem(
                Row.Builder()
                    .setTitle("Talk to Charon")
                    .addText("Ask a follow-up")
                    .setOnClickListener { screenManager.push(CarVoiceSearchScreen(carContext)) }
                    .build()
            )
            return ListTemplate.Builder()
                .setTitle(response)
                .setHeaderAction(Action.BACK)
                .setSingleList(items.build())
                .build()
        }
        val template = MessageTemplate.Builder(response)
            .setTitle("Private Concierge")
            .setHeaderAction(Action.BACK)
        places.firstOrNull()?.let { place ->
            template.addAction(
                Action.Builder()
                    .setTitle("Navigate")
                    .setOnClickListener { navigate(place) }
                    .build()
            )
        }
        template.addAction(
            Action.Builder()
                .setTitle("Talk again")
                .setOnClickListener { screenManager.push(CarVoiceSearchScreen(carContext)) }
                .build()
        )
        return template.build()
    }

    private fun places(): List<CarPlaceResult> = parsePlaces(payload).take(10)

    private fun navigate(place: CarPlaceResult) {
        val uri = Uri.parse("geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}(${Uri.encode(place.name)})")
        carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
    }

    companion object {
        private const val PAGE_SIZE = 4
        private const val GOOGLE_TTS_PACKAGE = "com.google.android.tts"

        fun firstPlace(payload: Map<String, Any?>): CarPlaceResult? =
            parsePlaces(payload).firstOrNull()

        private fun parsePlaces(payload: Map<String, Any?>): List<CarPlaceResult> =
            (payload["places"] as? List<*>).orEmpty().mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val typed = map.entries.associate { (key, value) -> key.toString() to value }
                CarPlaceResult.from(typed)
            }
    }
}

class CarPlaceResultScreen(
    carContext: CarContext,
    private val place: CarPlaceResult
) : Screen(carContext) {
    override fun onGetTemplate(): Template = MessageTemplate.Builder(place.detail)
        .setTitle(place.name)
        .setHeaderAction(Action.BACK)
        .addAction(
            Action.Builder()
                .setTitle("Navigate")
                .setOnClickListener {
                    val uri = Uri.parse("geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}(${Uri.encode(place.name)})")
                    carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
                }
                .build()
        )
        .build()
}

data class CarPlaceResult(
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val detail: String,
    val address: String,
    val category: String,
    val distanceMeters: Double?,
    val phoneNumber: String?,
    val website: String?,
    val isOpenNow: Boolean?,
    val arrivalMs: Long?,
    val departureMs: Long?
) {
    companion object {
        fun from(payload: Map<String, Any?>): CarPlaceResult? {
            val name = payload["name"] as? String ?: return null
            val latitude = (payload["latitude"] as? Number)?.toDouble() ?: return null
            val longitude = (payload["longitude"] as? Number)?.toDouble() ?: return null
            val address = payload["address"] as? String ?: ""
            val meters = (payload["distanceMeters"] as? Number)?.toDouble()
            val category = payload["category"] as? String ?: ""
            val phone = payload["phoneNumber"] as? String
            val website = payload["website"] as? String
            val isOpenNow = payload["isOpenNow"] as? Boolean
            val arrivalMs = (payload["arrivalMs"] as? Number)?.toLong()
            val departureMs = (payload["departureMs"] as? Number)?.toLong()
            val miles = meters?.let { "%.1f miles".format(it / 1609.344) }
            val status = isOpenNow?.let { if (it) "Open now" else "Closed" }
            val formatter = SimpleDateFormat("MM/dd h:mm a", Locale.US)
            val visitTimes = arrivalMs?.let {
                "Arrived: ${formatter.format(Date(it))}  Left: ${departureMs?.let { value -> formatter.format(Date(value)) } ?: "Still there"}"
            }
            val detail = listOfNotNull(
                listOfNotNull(status, miles, address.takeIf(String::isNotBlank)).joinToString(" · ").takeIf(String::isNotBlank),
                visitTimes
            ).joinToString("\n")
            return CarPlaceResult(name, latitude, longitude, detail, address, category, meters, phone, website, isOpenNow, arrivalMs, departureMs)
        }
    }
}
