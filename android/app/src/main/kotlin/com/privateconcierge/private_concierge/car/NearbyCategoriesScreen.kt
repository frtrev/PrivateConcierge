package com.neotheone.privateconcierge.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

class NearbyCategoriesScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        listOf("Food", "Gas", "Historic", "Parks", "Churches", "Gyms").forEach { category ->
            list.addItem(Row.Builder().setTitle(category).setOnClickListener {
                screenManager.push(CarPoiScreen(carContext, category))
            }.build())
        }
        return ListTemplate.Builder().setTitle("Nearby").setHeaderAction(Action.BACK).setSingleList(list.build()).build()
    }
}
