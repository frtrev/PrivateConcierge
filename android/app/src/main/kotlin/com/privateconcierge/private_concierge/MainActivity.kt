package com.neotheone.privateconcierge

import android.Manifest
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "private_concierge/on_device_speech"
    private val navigationChannelName = "charon/navigation"
    private val speechRequest = 7001
    private var pendingResult: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private var carChannel: MethodChannel? = null
    private var pendingTalkRequest = false

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        CharonFlutterEngineHost.get(context)

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingTalkRequest = intent?.data?.let { it.scheme == "charon" && it.host == "talk" } == true
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        carChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "charon/car").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consumeTalkRequest") {
                    val pending = pendingTalkRequest
                    pendingTalkRequest = false
                    result.success(pending)
                } else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isOnDeviceRecognitionAvailable())
                "listenOnce" -> startOnDeviceRecognition(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, navigationChannelName).setMethodCallHandler { call, result ->
            if (call.method != "navigate") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val latitude = call.argument<Double>("latitude")
            val longitude = call.argument<Double>("longitude")
            val name = call.argument<String>("name") ?: "Destination"
            if (latitude == null || longitude == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            val uri = Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encode(name)})")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            if (intent.resolveActivity(packageManager) == null) result.success(false)
            else {
                startActivity(intent)
                result.success(true)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "charon/place_actions").setMethodCallHandler { call, result ->
            val value = call.argument<String>("value")
            if (value == null) {
                result.success(false)
                return@setMethodCallHandler
            }
            val uri = when (call.method) {
                "call" -> Uri.parse("tel:${value.filter { it.isDigit() || it == '+' }}")
                "openWebsite" -> Uri.parse(value)
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            val intent = Intent(Intent.ACTION_VIEW, uri)
            if (intent.resolveActivity(packageManager) == null) result.success(false)
            else {
                startActivity(intent)
                result.success(true)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.data?.let { it.scheme == "charon" && it.host == "talk" } == true) {
            pendingTalkRequest = true
            carChannel?.invokeMethod("talkRequested", null)
        }
    }

    private fun isOnDeviceRecognitionAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(this)

    private fun startOnDeviceRecognition(result: MethodChannel.Result) {
        if (!isOnDeviceRecognitionAvailable()) {
            result.error("unsupported", "On-device voice recognition is unavailable on this device.", null)
            return
        }
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), speechRequest)
            return
        }
        pendingResult = result
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }
        recognizer?.destroy()
        recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this).also { speech ->
            speech.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
                override fun onError(error: Int) = finishSpeechError("On-device recognition failed (code $error).")
                override fun onResults(results: Bundle?) {
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    pendingResult?.success(text)
                    pendingResult = null
                    recognizer?.destroy()
                    recognizer = null
                }
            })
            speech.startListening(intent)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == speechRequest) {
            val result = pendingResult ?: return
            pendingResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startOnDeviceRecognition(result)
            else result.error("permission_denied", "Microphone permission was denied.", null)
        }
    }

    private fun finishSpeechError(message: String) {
        val result = pendingResult ?: return
        pendingResult = null
        result.error("recognition_failed", message, null)
        recognizer?.destroy()
        recognizer = null
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }
}
