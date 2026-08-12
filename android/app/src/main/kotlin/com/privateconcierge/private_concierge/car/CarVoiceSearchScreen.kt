package com.neotheone.privateconcierge.car

import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Template
import com.neotheone.privateconcierge.CharonFlutterEngineHost
import io.flutter.plugin.common.MethodChannel

class CarVoiceSearchScreen(carContext: CarContext) : Screen(carContext) {
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(
        CharonFlutterEngineHost.get(carContext).dartExecutor.binaryMessenger,
        "charon/car"
    )
    private var status = "Tap the microphone and ask Charon"
    private var submitting = false

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
            .addItem(Row.Builder().setTitle(status).build())
            .build()
        return SearchTemplate.Builder(object : SearchTemplate.SearchCallback {
            override fun onSearchTextChanged(searchText: String) = Unit

            override fun onSearchSubmitted(searchText: String) {
                if (searchText.isBlank() || submitting) return
                submitting = true
                status = "Searching privately on this phone…"
                invalidate()
                submit(searchText, attemptsRemaining = 12)
            }
        })
            .setHeaderAction(Action.BACK)
            .setShowKeyboardByDefault(false)
            .setItemList(list)
            .build()
    }

    private fun submit(text: String, attemptsRemaining: Int) {
        channel.invokeMethod("submitText", text, object : MethodChannel.Result {
            override fun success(result: Any?) {
                submitting = false
                @Suppress("UNCHECKED_CAST")
                val payload = result as? Map<String, Any?>
                if (payload == null) {
                    showError("Charon could not read that result.")
                } else {
                    if (payload["type"] == "navigation") {
                        CarAssistantResultScreen.firstPlace(payload)?.let { place ->
                            val uri = Uri.parse("geo:${place.latitude},${place.longitude}?q=${place.latitude},${place.longitude}(${Uri.encode(place.name)})")
                            carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, uri))
                        }
                    }
                    screenManager.push(CarAssistantResultScreen(carContext, payload))
                }
            }

            override fun error(code: String, message: String?, details: Any?) {
                retryOrFail(text, attemptsRemaining, message)
            }

            override fun notImplemented() {
                retryOrFail(text, attemptsRemaining, null)
            }
        })
    }

    private fun retryOrFail(text: String, attemptsRemaining: Int, message: String?) {
        if (attemptsRemaining > 0) {
            handler.postDelayed({ submit(text, attemptsRemaining - 1) }, 500)
        } else {
            showError(message ?: "Charon is still starting. Please try again.")
        }
    }

    private fun showError(message: String) {
        submitting = false
        status = message
        invalidate()
    }
}
