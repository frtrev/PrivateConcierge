package com.neotheone.privateconcierge

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

object CharonFlutterEngineHost {
    const val engineId = "charon_shared_engine"

    @Synchronized
    fun get(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(engineId)?.let { return it }
        val applicationContext = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        return FlutterEngine(applicationContext).also { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, "charon/car")
                .setMethodCallHandler { call, result ->
                    if (call.method == "publishNotification") {
                        @Suppress("UNCHECKED_CAST")
                        CarNotificationStore.publish(
                            applicationContext,
                            call.arguments as? Map<String, Any?> ?: emptyMap()
                        )
                        result.success(true)
                    } else {
                        result.notImplemented()
                    }
                }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(engineId, engine)
        }
    }
}
