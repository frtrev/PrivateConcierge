package com.neotheone.privateconcierge.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.ListTemplate

class CarHomeScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
            .addItem(Row.Builder().setTitle("Talk to Charon").addText("Use voice or type a request").setOnClickListener {
                screenManager.push(CarVoiceSearchScreen(carContext))
            }.build())
            .addItem(Row.Builder().setTitle("Nearby").addText("Food, gas, historic, parks, churches, and gyms").setOnClickListener { screenManager.push(NearbyCategoriesScreen(carContext)) }.build())
            .addItem(Row.Builder().setTitle("Reminders").addText("Coming later").build())
            .addItem(Row.Builder().setTitle("My Places").addText("Coming later").build())
            .build()
        return ListTemplate.Builder().setTitle("Private Concierge").setHeaderAction(Action.APP_ICON).setSingleList(list).build()
    }
}
