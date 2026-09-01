package com.neotheone.privateconcierge.car

import android.content.Intent
import android.content.pm.ApplicationInfo
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.validation.HostValidator
import com.neotheone.privateconcierge.CharonFlutterEngineHost

class PrivateConciergeCarAppService : CarAppService() {
    override fun onCreate() {
        super.onCreate()
        CharonFlutterEngineHost.get(this)
    }
    override fun createHostValidator(): HostValidator =
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        else HostValidator.Builder(applicationContext).build()

    override fun onCreateSession(sessionInfo: SessionInfo): Session = PrivateConciergeCarSession()
}

class PrivateConciergeCarSession : Session() {
    override fun onCreateScreen(intent: Intent) = CarHomeScreen(carContext)
}
