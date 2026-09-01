package com.neotheone.privateconcierge.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.neotheone.privateconcierge.CarNotificationStore

class CarHomeScreen(carContext: CarContext) : Screen(carContext) {
    private val notificationListener = { invalidate() }

    init {
        CarNotificationStore.addListener(notificationListener)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarNotificationStore.removeListener(notificationListener)
            }
        })
    }

    override fun onGetTemplate(): Template {
        val items = ItemList.Builder().addItem(
            GridItem.Builder()
                .setTitle("Talk to Charon")
                .setText("Voice or type a request")
                .setImage(CarIcon.APP_ICON)
                .setOnClickListener { screenManager.push(CarVoiceSearchScreen(carContext)) }
                .build()
        )
        CarNotificationStore.recent(carContext).forEach { notification ->
            items.addItem(
                GridItem.Builder()
                    .setTitle(notification.title)
                    .setText(notification.body)
                    .setImage(
                        if (notification.action == "directions") CarIcon.PAN
                        else CarIcon.COMPOSE_MESSAGE
                    )
                    .setOnClickListener {
                        screenManager.push(CarNotificationScreen(carContext, notification))
                    }
                    .build()
            )
        }
        return GridTemplate.Builder()
            .setTitle("Private Concierge")
            .setHeaderAction(Action.APP_ICON)
            .setItemSize(GridTemplate.ITEM_SIZE_LARGE)
            .setSingleList(items.build())
            .build()
    }
}
