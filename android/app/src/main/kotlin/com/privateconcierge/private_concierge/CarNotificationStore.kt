package com.neotheone.privateconcierge

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject

data class CarNotification(
    val id: Int,
    val title: String,
    val body: String,
    val action: String,
    val latitude: Double?,
    val longitude: Double?,
    val placeName: String?
)

object CarNotificationStore {
    private const val preferencesName = "charon_car_notifications"
    private const val notificationsKey = "recent"
    private const val maximumNotifications = 6
    private val listeners = mutableSetOf<() -> Unit>()

    fun publish(context: Context, payload: Map<String, Any?>) {
        val notification = CarNotification(
            id = (payload["id"] as? Number)?.toInt() ?: payload.hashCode(),
            title = payload["title"] as? String ?: "Charon",
            body = payload["body"] as? String ?: "",
            action = payload["action"] as? String ?: "read",
            latitude = (payload["latitude"] as? Number)?.toDouble(),
            longitude = (payload["longitude"] as? Number)?.toDouble(),
            placeName = payload["placeName"] as? String
        )
        val updated = recent(context).filterNot { it.id == notification.id }
            .toMutableList().apply { add(0, notification) }.take(maximumNotifications)
        val json = JSONArray()
        updated.forEach { value ->
            json.put(JSONObject().apply {
                put("id", value.id)
                put("title", value.title)
                put("body", value.body)
                put("action", value.action)
                value.latitude?.let { put("latitude", it) }
                value.longitude?.let { put("longitude", it) }
                value.placeName?.let { put("placeName", it) }
            })
        }
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .edit().putString(notificationsKey, json.toString()).apply()
        Handler(Looper.getMainLooper()).post { listeners.toList().forEach { it() } }
    }

    fun recent(context: Context): List<CarNotification> {
        val raw = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
            .getString(notificationsKey, null) ?: return emptyList()
        return runCatching {
            val json = JSONArray(raw)
            (0 until minOf(json.length(), maximumNotifications)).map { index ->
                val value = json.getJSONObject(index)
                CarNotification(
                    id = value.getInt("id"),
                    title = value.optString("title", "Charon"),
                    body = value.optString("body", ""),
                    action = value.optString("action", "read"),
                    latitude = value.optDouble("latitude").takeUnless { it.isNaN() },
                    longitude = value.optDouble("longitude").takeUnless { it.isNaN() },
                    placeName = value.optString("placeName").takeIf { it.isNotEmpty() }
                )
            }
        }.getOrDefault(emptyList())
    }

    fun addListener(listener: () -> Unit) { listeners.add(listener) }
    fun removeListener(listener: () -> Unit) { listeners.remove(listener) }
}
