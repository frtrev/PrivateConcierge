package com.privateconcierge.private_concierge.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.validation.HostValidator

class PrivateConciergeCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        else HostValidator.Builder(applicationContext).build()

    override fun onCreateSession(sessionInfo: SessionInfo): Session = PrivateConciergeCarSession()
}

class PrivateConciergeCarSession : Session() {
    override fun onCreateScreen(intent: Intent) = CarHomeScreen(carContext)
}
