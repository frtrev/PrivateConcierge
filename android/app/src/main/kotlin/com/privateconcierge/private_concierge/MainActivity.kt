package com.neotheone.privateconcierge

import android.Manifest
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "private_concierge/on_device_speech"
    private val navigationChannelName = "charon/navigation"
    private val speechRequest = 7001
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPrayerPunctuation = false
    private var recognizer: SpeechRecognizer? = null
    private var carChannel: MethodChannel? = null
    private var pendingTalkRequest = false
    private var previewTts: TextToSpeech? = null
    private var defaultPreviewVoice: Voice? = null
    private var previewTtsInitializing = false
    private val pendingTtsActions = mutableListOf<(TextToSpeech?) -> Unit>()
    private var pendingPhoneSpeechResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        CharonFlutterEngineHost.get(context)

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingTalkRequest = intent?.data?.let { it.scheme == "charon" && it.host == "talk" } == true
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "charon/local_ai").setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCompatibility" -> {
                    val minimumSdk = call.argument<Int>("minimumAndroidSdk") ?: 24
                    val compatible = Build.VERSION.SDK_INT >= minimumSdk
                    result.success(mapOf(
                        "compatible" to compatible,
                        "message" to if (compatible) "Compatible with the on-device GGUF runtime." else "Requires Android API $minimumSdk or newer."
                    ))
                }
                "downloadEnvironment" -> {
                    val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                    val unmetered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true
                    result.success(mapOf(
                        "unmetered" to unmetered,
                        "availableStorageBytes" to StatFs(filesDir.path).availableBytes
                    ))
                }
                "dispose", "cancel" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        carChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "charon/car").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeTalkRequest" -> {
                        val pending = pendingTalkRequest
                        pendingTalkRequest = false
                        result.success(pending)
                    }
                    // Android Auto owns its templates and submits directly through
                    // this engine. Phone-only status/result publication is optional.
                    "publishStatus", "publishResult" -> result.success(true)
                    "publishNotification" -> {
                        @Suppress("UNCHECKED_CAST")
                        CarNotificationStore.publish(
                            applicationContext,
                            call.arguments as? Map<String, Any?> ?: emptyMap()
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(isOnDeviceRecognitionAvailable())
                "listenOnce" -> startOnDeviceRecognition(
                    result,
                    call.argument<Boolean>("punctuatePauses") ?: false
                )
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "private_concierge/speech_voice").setMethodCallHandler { call, result ->
            val preferences = getSharedPreferences("charon_speech", Context.MODE_PRIVATE)
            when (call.method) {
                "pause" -> {
                    previewTts?.stop()
                    result.success(true)
                }
                "resume" -> result.success(true)
                "stop" -> {
                    previewTts?.stop()
                    result.success(true)
                }
                "selectedVoice" -> result.success(preferences.getString("voice_id", null))
                "selectedEngine" -> result.success(selectedEngineId(preferences))
                "engines" -> withPreviewTts { tts ->
                    if (tts == null) result.success(emptyList<Map<String, String>>())
                    else result.success(
                        tts.engines
                            .sortedBy { it.label.lowercase(Locale.ROOT) }
                            .map { mapOf("id" to it.name, "name" to it.label) }
                    )
                }
                "selectEngine" -> {
                    val engineId = call.argument<String>("engineId")
                    if (engineId == null) result.success(false)
                    else {
                        preferences.edit().putString("engine_id", engineId).remove("voice_id").apply()
                        resetPreviewTts()
                        result.success(true)
                    }
                }
                "select" -> {
                    val voiceId = call.argument<String>("voiceId")
                    if (voiceId == null) result.success(false)
                    else {
                        preferences.edit()
                            .putString("engine_id", selectedEngineId(preferences))
                            .putString("voice_id", voiceId)
                            .apply()
                        result.success(true)
                    }
                }
                "voices", "preview", "speak" -> withPreviewTts { tts ->
                    if (tts == null) {
                        result.error("tts_unavailable", "Text to speech is unavailable.", null)
                    } else {
                        if (call.method == "voices") {
                            val namedVoices = tts.voices.orEmpty()
                                .filter { isEnglish(it.locale) }
                                .sortedBy { it.name.lowercase(Locale.ROOT) }
                                .map { mapOf("id" to it.name, "name" to it.name, "locale" to it.locale.toLanguageTag()) }
                            val localeVoices = tts.availableLanguages.orEmpty()
                                .filter(::isEnglish)
                                .sortedBy { it.displayName.lowercase(Locale.ROOT) }
                                .map { locale ->
                                    mapOf(
                                        "id" to "locale:${locale.toLanguageTag()}",
                                        "name" to locale.getDisplayName(locale),
                                        "locale" to locale.toLanguageTag()
                                    )
                                }
                            val exposed = if (namedVoices.isNotEmpty()) namedVoices else localeVoices
                            result.success(
                                listOf(
                                    mapOf(
                                        "id" to "system:default",
                                        "name" to "System default",
                                        "locale" to "Android TTS settings"
                                    )
                                ) + exposed
                            )
                        } else {
                            val voiceId = if (call.method == "speak") {
                                preferences.getString("voice_id", null) ?: "system:default"
                            } else call.argument<String>("voiceId")
                            val text = call.argument<String>("text") ?: "Hello."
                            val rate = call.argument<Double>("rate")?.toFloat() ?: 1.0f
                            if (voiceId == "system:default") {
                                defaultPreviewVoice?.let { tts.voice = it }
                            } else if (voiceId?.startsWith("locale:") == true) {
                                tts.setLanguage(Locale.forLanguageTag(voiceId.removePrefix("locale:")))
                            } else {
                                tts.voice = tts.voices?.firstOrNull { it.name == voiceId }
                            }
                            val utteranceId = if (call.method == "speak") "charon-phone-response" else "charon-preview"
                            tts.setSpeechRate(rate)
                            if (call.method == "speak") {
                                pendingPhoneSpeechResult?.success(false)
                                pendingPhoneSpeechResult = result
                            }
                            val status = tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
                            if (status == TextToSpeech.ERROR) {
                                if (call.method == "speak") {
                                    pendingPhoneSpeechResult = null
                                    result.error("tts_failed", "Text to speech could not start.", null)
                                } else result.success(false)
                            } else if (call.method != "speak") {
                                result.success(true)
                            }
                        }
                    }
                }
                "installVoices" -> {
                    val engineId = preferences.getString("engine_id", null)
                    val intent = Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA).apply {
                        if (engineId != null) setPackage(engineId)
                    }
                    if (intent.resolveActivity(packageManager) == null) result.success(false)
                    else {
                        startActivity(intent)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
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

    private fun withPreviewTts(action: (TextToSpeech?) -> Unit) {
        previewTts?.let {
            action(it)
            return
        }
        pendingTtsActions.add(action)
        if (previewTtsInitializing) return
        previewTtsInitializing = true
        var created: TextToSpeech? = null
        val preferences = getSharedPreferences("charon_speech", Context.MODE_PRIVATE)
        val engineId = selectedEngineId(preferences)
        created = TextToSpeech(this, { status ->
            Handler(Looper.getMainLooper()).post {
                previewTtsInitializing = false
                val ready = if (status == TextToSpeech.SUCCESS) created else null
                if (ready != null) {
                    defaultPreviewVoice = ready.voice
                    ready.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) = Unit

                        override fun onDone(utteranceId: String?) {
                            if (utteranceId != "charon-phone-response") return
                            Handler(Looper.getMainLooper()).post {
                                pendingPhoneSpeechResult?.success(true)
                                pendingPhoneSpeechResult = null
                            }
                        }

                        override fun onStop(utteranceId: String?, interrupted: Boolean) {
                            if (utteranceId != "charon-phone-response") return
                            Handler(Looper.getMainLooper()).post {
                                pendingPhoneSpeechResult?.success(false)
                                pendingPhoneSpeechResult = null
                            }
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            finishPhoneSpeechWithError(utteranceId)
                        }

                        override fun onError(utteranceId: String?, errorCode: Int) {
                            finishPhoneSpeechWithError(utteranceId)
                        }
                    })
                    previewTts = ready
                }
                val actions = pendingTtsActions.toList()
                pendingTtsActions.clear()
                actions.forEach { it(ready) }
            }
        }, engineId)
    }

    private fun finishPhoneSpeechWithError(utteranceId: String?) {
        if (utteranceId != "charon-phone-response") return
        Handler(Looper.getMainLooper()).post {
            pendingPhoneSpeechResult?.error("tts_failed", "Text to speech did not finish.", null)
            pendingPhoneSpeechResult = null
        }
    }

    private fun resetPreviewTts() {
        previewTts?.stop()
        previewTts?.shutdown()
        previewTts = null
        defaultPreviewVoice = null
        previewTtsInitializing = false
        pendingTtsActions.clear()
    }

    private fun selectedEngineId(preferences: android.content.SharedPreferences): String? {
        preferences.getString("engine_id", null)?.let { return it }
        return if (isPackageInstalled(GOOGLE_TTS_PACKAGE)) GOOGLE_TTS_PACKAGE else null
    }

    private fun isPackageInstalled(packageName: String): Boolean = try {
        packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun isEnglish(locale: Locale): Boolean =
        locale.language.equals(Locale.ENGLISH.language, ignoreCase = true) ||
            runCatching { locale.isO3Language.equals("eng", ignoreCase = true) }.getOrDefault(false)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.data?.let { it.scheme == "charon" && it.host == "talk" } == true) {
            pendingTalkRequest = true
            carChannel?.invokeMethod("talkRequested", null)
        }
    }

    override fun onResume() {
        super.onResume()
        val result = pendingResult ?: return
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            pendingResult = null
            Log.d(TAG, "Resuming pending recognition after permission grant")
            startOnDeviceRecognition(result)
        }
    }

    private fun isOnDeviceRecognitionAvailable(): Boolean {
        val services = packageManager.queryIntentServices(
            Intent(RecognitionService.SERVICE_INTERFACE),
            PackageManager.MATCH_DEFAULT_ONLY
        )
        val available = services.isNotEmpty() || SpeechRecognizer.isRecognitionAvailable(this)
        Log.d(TAG, "Speech recognition available=$available services=${services.size}")
        return available
    }

    private fun startOnDeviceRecognition(
        result: MethodChannel.Result,
        punctuatePauses: Boolean = false
    ) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Log.d(TAG, "Requesting RECORD_AUDIO permission")
            pendingResult = result
            pendingPrayerPunctuation = punctuatePauses
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), speechRequest)
            return
        }
        if (!isOnDeviceRecognitionAvailable()) {
            result.error("unsupported", "Voice recognition is unavailable on this device.", null)
            return
        }
        pendingResult = result
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, punctuatePauses)
            if (punctuatePauses) {
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    2500L
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    2000L
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                    10000L
                )
            }
            if (punctuatePauses && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                putExtra("android.speech.extra.ENABLE_FORMATTING", "quality")
            }
        }
        recognizer?.destroy()
        val onDeviceAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        Log.d(TAG, "Starting recognition onDevice=$onDeviceAvailable")
        recognizer = if (onDeviceAvailable) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        } else {
            SpeechRecognizer.createSpeechRecognizer(this)
        }.also { speech ->
            var latestPartial = ""
            var silenceStartedAt: Long? = null
            var wasSpeaking = false
            val pauseBoundaries = mutableListOf<Pair<Int, Char>>()
            speech.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    Log.d(TAG, "Recognizer ready for speech")
                }
                override fun onBeginningOfSpeech() {
                    Log.d(TAG, "Recognizer detected speech")
                }
                override fun onRmsChanged(rmsdB: Float) {
                    if (!punctuatePauses) return
                    val speaking = rmsdB >= 1.5f
                    val now = SystemClock.elapsedRealtime()
                    if (wasSpeaking && !speaking) {
                        silenceStartedAt = now
                    } else if (!wasSpeaking && speaking) {
                        val started = silenceStartedAt
                        val pause = if (started == null) 0 else now - started
                        val wordCount = latestPartial.trim()
                            .split(Regex("\\s+"))
                            .count { it.isNotBlank() }
                        if (wordCount > 0 && pause >= 450) {
                            val mark = if (pause >= 900) '.' else ','
                            if (pauseBoundaries.none { it.first == wordCount }) {
                                pauseBoundaries.add(wordCount to mark)
                            }
                        }
                        silenceStartedAt = null
                    }
                    wasSpeaking = speaking
                }
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) {
                    latestPartial = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?: latestPartial
                }
                override fun onEvent(eventType: Int, params: Bundle?) = Unit
                override fun onError(error: Int) {
                    Log.e(TAG, "Recognition failed code=$error")
                    finishSpeechError("Voice recognition failed (code $error).")
                }
                override fun onResults(results: Bundle?) {
                    val rawText = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    val text = if (punctuatePauses && rawText != null) {
                        punctuateAtPauses(rawText, pauseBoundaries)
                    } else rawText
                    Log.d(TAG, "Recognition completed hasText=${!text.isNullOrBlank()}")
                    pendingResult?.success(text)
                    pendingResult = null
                    recognizer?.destroy()
                    recognizer = null
                }
            })
            speech.startListening(intent)
        }
    }

    private fun punctuateAtPauses(
        text: String,
        boundaries: List<Pair<Int, Char>>
    ): String {
        if (boundaries.isEmpty()) return text
        val marks = boundaries.toMap()
        val words = text.trim().split(Regex("\\s+"))
        val output = StringBuilder()
        words.forEachIndexed { index, rawWord ->
            if (output.isNotEmpty()) output.append(' ')
            val shouldCapitalize = index == 0 || marks[index] == '.'
            val word = if (shouldCapitalize && rawWord.isNotEmpty()) {
                rawWord.replaceFirstChar { it.uppercase() }
            } else rawWord
            output.append(word)
            val mark = marks[index + 1]
            if (mark != null && word.lastOrNull() !in listOf('.', ',', ';', ':', '!', '?')) {
                output.append(mark)
            }
        }
        return output.toString()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == speechRequest) {
            val result = pendingResult ?: return
            val punctuatePauses = pendingPrayerPunctuation
            pendingResult = null
            pendingPrayerPunctuation = false
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "RECORD_AUDIO permission granted")
                startOnDeviceRecognition(result, punctuatePauses)
            }
            else result.error("permission_denied", "Microphone permission was denied.", null)
        }
    }

    private fun finishSpeechError(message: String) {
        val result = pendingResult ?: return
        pendingResult = null
        result.error("recognition_failed", message, null)
        recognizer?.destroy()
        recognizer = null
        previewTts?.shutdown()
        previewTts = null
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        previewTts?.stop()
        previewTts?.shutdown()
        previewTts = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PrivateConciergeVoice"
        private const val GOOGLE_TTS_PACKAGE = "com.google.android.tts"
    }
}
