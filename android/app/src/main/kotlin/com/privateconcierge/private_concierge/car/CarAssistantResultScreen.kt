package com.neotheone.privateconcierge.car

import android.content.Intent
import android.net.Uri
import android.speech.tts.TextToSpeech
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
    private val payload: Map<String, Any?>
) : Screen(carContext) {
    private var textToSpeech: TextToSpeech? = null

    init {
        val spoken = payload["spokenResponse"] as? String
            ?: payload["response"] as? String
            ?: "Charon finished the request."
        textToSpeech = TextToSpeech(carContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, "charon-result")
            }
        }
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
            places.take(5).forEach { place ->
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
            .setTitle("Charon")
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

    private fun places(): List<CarPlaceResult> = parsePlaces(payload)

    private fun navigate(place: CarPlaceResult) {
        val uri = Uri.parse("geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}(${Uri.encode(place.name)})")
        carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
    }

    companion object {
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
    val detail: String
) {
    companion object {
        fun from(payload: Map<String, Any?>): CarPlaceResult? {
            val name = payload["name"] as? String ?: return null
            val latitude = (payload["latitude"] as? Number)?.toDouble() ?: return null
            val longitude = (payload["longitude"] as? Number)?.toDouble() ?: return null
            val address = payload["address"] as? String ?: ""
            val meters = (payload["distanceMeters"] as? Number)?.toDouble()
            val miles = meters?.let { "%.1f miles".format(it / 1609.344) }
            val detail = listOfNotNull(miles, address.takeIf(String::isNotBlank)).joinToString(" · ")
            return CarPlaceResult(name, latitude, longitude, detail)
        }
    }
}
