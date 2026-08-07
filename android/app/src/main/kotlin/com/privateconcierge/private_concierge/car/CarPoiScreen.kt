package com.privateconcierge.private_concierge.car

import android.content.Intent
import android.net.Uri
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

private data class CarPoi(val name: String, val category: String, val address: String, val latitude: Double, val longitude: Double)

private val bundledMemphisPois = listOf(
    CarPoi("Riverfront Grill", "Food", "100 Main Street, Memphis", 35.1495, -90.0490),
    CarPoi("Central Fuel", "Gas", "105 Main Street, Memphis", 35.1645, -90.0390),
    CarPoi("Historic Square", "Historic", "104 Main Street, Memphis", 35.1615, -90.0410),
    CarPoi("Heritage Park", "Parks", "101 Main Street, Memphis", 35.1525, -90.0470),
    CarPoi("Community Church", "Churches", "102 Main Street, Memphis", 35.1555, -90.0450),
    CarPoi("Neighborhood Fitness", "Gyms", "103 Main Street, Memphis", 35.1585, -90.0430),
)

class CarPoiScreen(carContext: CarContext, private val category: String) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        bundledMemphisPois.filter { it.category == category }.forEach { poi ->
            list.addItem(Row.Builder().setTitle(poi.name).addText(poi.address).setOnClickListener {
                screenManager.push(CarPoiDetailScreen(carContext, poi))
            }.build())
        }
        return ListTemplate.Builder().setTitle(category).setHeaderAction(Action.BACK).setSingleList(list.build()).build()
    }
}

private class CarPoiDetailScreen(carContext: CarContext, private val poi: CarPoi) : Screen(carContext) {
    override fun onGetTemplate(): Template = MessageTemplate.Builder(poi.address)
        .setTitle(poi.name)
        .setHeaderAction(Action.BACK)
        .addAction(Action.Builder().setTitle("Navigate").setOnClickListener {
            val destination = Uri.parse("geo:0,0?q=${poi.latitude},${poi.longitude}(${Uri.encode(poi.name)})")
            carContext.startCarApp(Intent(CarContext.ACTION_NAVIGATE, destination))
        }.build())
        .build()
}
