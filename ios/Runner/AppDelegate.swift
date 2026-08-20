import Flutter
import AVFoundation
import CoreLocation
import Speech
import UIKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  AVSpeechSynthesizerDelegate
{
  private var speechHandler: IosOnDeviceSpeechHandler?
  private var navigationChannel: FlutterMethodChannel?
  private var placeActionsChannel: FlutterMethodChannel?
  private var visitMonitoringHandler: IosVisitMonitoringHandler?
  private var carChannel: FlutterMethodChannel?
  private var speechVoiceChannel: FlutterMethodChannel?
  private let previewSpeechSynthesizer = AVSpeechSynthesizer()
  private var pendingPhoneSpeechResult: FlutterResult?
  private weak var pendingPhoneUtterance: AVSpeechUtterance?
  private var pendingTalkRequest = false
  private var carVoiceTurnActive = false
  private var carVoiceBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var carVoiceTimeout: DispatchWorkItem?
  private var carSpeechAwaitingStart = false
  private var carVoiceTurnGeneration = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    previewSpeechSynthesizer.delegate = self
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "IosOnDeviceSpeech"
    ) else { return }
    let localAiChannel = FlutterMethodChannel(
      name: "charon/local_ai",
      binaryMessenger: registrar.messenger()
    )
    localAiChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "checkCompatibility":
        result([
          "compatible": true,
          "message": "Compatible with the on-device GGUF runtime."
        ])
      case "downloadEnvironment":
        let values = try? FileManager.default.attributesOfFileSystem(
          forPath: NSHomeDirectory()
        )
        let available = (values?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "charon.local-ai.network")
        monitor.pathUpdateHandler = { path in
          monitor.cancel()
          result([
            "unmetered": path.status == .satisfied && !path.isExpensive,
            "availableStorageBytes": available
          ])
        }
        monitor.start(queue: queue)
      case "dispose", "cancel": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    carChannel = FlutterMethodChannel(
      name: "charon/car",
      binaryMessenger: registrar.messenger()
    )
    speechVoiceChannel = FlutterMethodChannel(
      name: "private_concierge/speech_voice",
      binaryMessenger: registrar.messenger()
    )
    speechVoiceChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "voices":
        let voices = AVSpeechSynthesisVoice.speechVoices()
          .filter { $0.language.lowercased().hasPrefix("en") }
          .map { ["id": $0.identifier, "name": $0.name, "locale": $0.language] }
          .sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
        result(voices)
      case "selectedVoice":
        result(UserDefaults.standard.string(forKey: "charon.speechVoiceId"))
      case "select":
        guard let values = call.arguments as? [String: Any],
          let voiceId = values["voiceId"] as? String
        else { result(false); return }
        UserDefaults.standard.set(voiceId, forKey: "charon.speechVoiceId")
        result(true)
      case "preview":
        guard let values = call.arguments as? [String: Any],
          let voiceId = values["voiceId"] as? String,
          let text = values["text"] as? String
        else { result(false); return }
        self.previewVoice(
          voiceId: voiceId,
          text: text,
          rateMultiplier: values["rate"] as? Double ?? 1.0
        )
        result(true)
      case "speak":
        guard let values = call.arguments as? [String: Any],
          let text = values["text"] as? String
        else { result(false); return }
        self.previewSpeechSynthesizer.stopSpeaking(at: .immediate)
        self.pendingPhoneSpeechResult?(false)
        self.pendingPhoneSpeechResult = result
        self.pendingPhoneUtterance = self.previewVoice(
          voiceId: UserDefaults.standard.string(forKey: "charon.speechVoiceId"),
          text: text,
          rateMultiplier: values["rate"] as? Double ?? 1.0,
          stopExisting: false
        )
      case "pause":
        result(self.previewSpeechSynthesizer.pauseSpeaking(at: .word))
      case "resume":
        result(self.previewSpeechSynthesizer.continueSpeaking())
      case "stop":
        result(self.previewSpeechSynthesizer.stopSpeaking(at: .immediate))
      case "installVoices":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    carChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "publishResult",
        let payload = call.arguments as? [String: Any]
      {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.show(payload: payload)
        }
        result(true)
        return
      }
      if call.method == "publishStatus",
        let payload = call.arguments as? [String: Any]
      {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showStatus(payload: payload)
        }
        result(true)
        return
      }
      if call.method == "showAlert",
        let payload = call.arguments as? [String: Any]
      {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showAlert(payload: payload)
        }
        result(true)
        return
      }
      if call.method == "prayerPlaybackState",
        let payload = call.arguments as? [String: Any]
      {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.updatePrayerPlayback(payload)
        }
        result(true)
        return
      }
      if call.method == "responseAudioStarted" {
        self?.carSpeechAwaitingStart = false
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.responseAudioStarted()
        }
        result(true)
        return
      }
      guard call.method == "consumeTalkRequest" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pending = self?.pendingTalkRequest ?? false
      self?.pendingTalkRequest = false
      result(pending)
    }
    speechHandler = IosOnDeviceSpeechHandler(
      messenger: registrar.messenger()
    )
    visitMonitoringHandler = IosVisitMonitoringHandler(
      messenger: registrar.messenger()
    )
    navigationChannel = FlutterMethodChannel(
      name: "charon/navigation",
      binaryMessenger: registrar.messenger()
    )
    navigationChannel?.setMethodCallHandler { call, result in
      guard call.method == "navigate",
        let arguments = call.arguments as? [String: Any],
        let latitude = arguments["latitude"] as? Double,
        let longitude = arguments["longitude"] as? Double
      else {
        result(call.method == "navigate" ? false : FlutterMethodNotImplemented)
        return
      }
      let name = arguments["name"] as? String ?? "Destination"
      var components = URLComponents(string: "http://maps.apple.com/")
      components?.queryItems = [
        URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
        URLQueryItem(name: "q", value: name),
      ]
      guard let url = components?.url else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
    }
    placeActionsChannel = FlutterMethodChannel(
      name: "charon/place_actions",
      binaryMessenger: registrar.messenger()
    )
    placeActionsChannel?.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: Any],
        let value = arguments["value"] as? String
      else {
        result(false)
        return
      }
      let url: URL?
      if call.method == "call" {
        let digits = value.filter { $0.isNumber || $0 == "+" }
        url = URL(string: "tel:\(digits)")
      } else if call.method == "openWebsite" {
        url = URL(string: value)
      } else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let url else { result(false); return }
      UIApplication.shared.open(url, options: [:]) { result($0) }
    }
  }

  @discardableResult
  private func previewVoice(
    voiceId: String?,
    text: String,
    rateMultiplier: Double = 1.0,
    stopExisting: Bool = true
  ) -> AVSpeechUtterance {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true, options: .notifyOthersOnDeactivation)
    if stopExisting { previewSpeechSynthesizer.stopSpeaking(at: .immediate) }
    let utterance = AVSpeechUtterance(string: text)
    if let voiceId { utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId) }
    utterance.rate = min(
      AVSpeechUtteranceMaximumSpeechRate,
      max(
        AVSpeechUtteranceMinimumSpeechRate,
        AVSpeechUtteranceDefaultSpeechRate * Float(rateMultiplier)
      )
    )
    // Give Bluetooth and CarPlay enough preroll after the session changes to
    // playback; shorter delays can clip the first word.
    utterance.preUtteranceDelay = 0.45
    previewSpeechSynthesizer.speak(utterance)
    return utterance
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    guard utterance === pendingPhoneUtterance, carSpeechAwaitingStart else { return }
    carSpeechAwaitingStart = false
    if #available(iOS 14.0, *) {
      CarPlaySessionCoordinator.shared.responseAudioStarted()
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    guard utterance === pendingPhoneUtterance else { return }
    pendingPhoneSpeechResult?(true)
    pendingPhoneSpeechResult = nil
    pendingPhoneUtterance = nil
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    guard utterance === pendingPhoneUtterance else { return }
    pendingPhoneSpeechResult?(false)
    pendingPhoneSpeechResult = nil
    pendingPhoneUtterance = nil
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "charon", url.host == "talk" else {
      return super.application(app, open: url, options: options)
    }
    requestTalkFromCar()
    return true
  }

  func requestTalkFromCar() {
    guard !carVoiceTurnActive else {
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showBusy()
      }
      return
    }
    guard let speechHandler, let carChannel else {
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showRecognitionError(
          "Charon is still starting. Please wait a moment and try again."
        )
      }
      return
    }
    let turnGeneration = beginCarVoiceTurn()
    if #available(iOS 14.0, *) {
      CarPlaySessionCoordinator.shared.showStarting()
    }
    let capturePrayerText: Bool
    if #available(iOS 14.0, *) {
      capturePrayerText = CarPlaySessionCoordinator.shared.shouldCapturePrayerText
    } else {
      capturePrayerText = false
    }
    speechHandler.listenFromCar(punctuatePauses: capturePrayerText) {
      [weak self] text, error in
      guard let self,
        self.carVoiceTurnActive,
        self.carVoiceTurnGeneration == turnGeneration
      else { return }
      if let error {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showRecognitionError(error)
        }
        self.endCarVoiceTurn()
        return
      }
      guard let text, !text.isEmpty else {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showRecognitionError(
            "I didn't hear anything. Please try again."
          )
        }
        self.endCarVoiceTurn()
        return
      }
      self.beginCarProcessingTimeout(turnGeneration: turnGeneration)
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showThinking(transcript: text)
      }
      carChannel.invokeMethod("submitRecognizedText", arguments: text) { result in
        guard self.carVoiceTurnActive,
          self.carVoiceTurnGeneration == turnGeneration
        else { return }
        defer { self.endCarVoiceTurn() }
        if let payload = result as? [String: Any] {
          if #available(iOS 14.0, *) {
            CarPlaySessionCoordinator.shared.show(payload: payload)
          }
        } else if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showRecognitionError(
            "Charon couldn't process that request."
          )
        }
      }
    }
  }

  func speakCarResponse(_ text: String, completion: @escaping (Bool) -> Void) {
    guard let carChannel else { completion(false); return }
    carSpeechAwaitingStart = true
    carChannel.invokeMethod("speakCarResponse", arguments: text) { value in
      self.carSpeechAwaitingStart = false
      completion((value as? Bool) == true)
    }
  }

  func playCarPrayer(_ prayer: [String: Any], completion: @escaping () -> Void) {
    guard let carChannel else { completion(); return }
    carChannel.invokeMethod("playCarPrayer", arguments: prayer) { _ in completion() }
  }

  func controlCarPrayer(_ method: String) {
    carChannel?.invokeMethod(method, arguments: nil)
  }

  private func beginCarVoiceTurn() -> Int {
    carVoiceTurnGeneration += 1
    let turnGeneration = carVoiceTurnGeneration
    carVoiceTurnActive = true
    carVoiceBackgroundTask = UIApplication.shared.beginBackgroundTask(
      withName: "CharonCarVoiceTurn"
    ) { [weak self] in
      guard let self else { return }
      self.endCarVoiceBackgroundTask()
    }
    scheduleCarVoiceTimeout(
      after: 25,
      turnGeneration: turnGeneration,
      message: "Charon didn't hear a request in time. Please try again."
    )
    return turnGeneration
  }

  private func beginCarProcessingTimeout(turnGeneration: Int) {
    scheduleCarVoiceTimeout(
      after: 55,
      turnGeneration: turnGeneration,
      message: "Charon couldn't finish that request in time. Please try again."
    )
  }

  private func scheduleCarVoiceTimeout(
    after seconds: TimeInterval,
    turnGeneration: Int,
    message: String
  ) {
    carVoiceTimeout?.cancel()
    let timeout = DispatchWorkItem { [weak self] in
      guard let self,
        self.carVoiceTurnActive,
        self.carVoiceTurnGeneration == turnGeneration
      else { return }
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showRecognitionError(message)
      }
      self.endCarVoiceTurn()
    }
    carVoiceTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
  }

  private func endCarVoiceTurn() {
    carVoiceTimeout?.cancel()
    carVoiceTimeout = nil
    carVoiceTurnActive = false
    endCarVoiceBackgroundTask()
  }

  private func endCarVoiceBackgroundTask() {
    let task = carVoiceBackgroundTask
    carVoiceBackgroundTask = .invalid
    if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
  }
}

private final class IosVisitMonitoringHandler: NSObject,
  CLLocationManagerDelegate, FlutterStreamHandler
{
  private static let queueKey = "charon.completedLocationVisits"
  private let manager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    let channel = FlutterEventChannel(
      name: "charon/location_visits",
      binaryMessenger: messenger
    )
    channel.setStreamHandler(self)
    manager.delegate = self
    manager.activityType = .other
    manager.pausesLocationUpdatesAutomatically = true
    manager.startMonitoringVisits()
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    drainQueue()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    guard visit.arrivalDate != .distantPast,
      visit.departureDate != .distantFuture
    else { return }
    let payload: [String: Any] = [
      "latitude": visit.coordinate.latitude,
      "longitude": visit.coordinate.longitude,
      "arrivalMs": Int64(visit.arrivalDate.timeIntervalSince1970 * 1000),
      "departureMs": Int64(visit.departureDate.timeIntervalSince1970 * 1000),
    ]
    var queued = UserDefaults.standard.array(forKey: Self.queueKey)
      as? [[String: Any]] ?? []
    let arrival = payload["arrivalMs"] as? Int64
    if !queued.contains(where: {
      ($0["arrivalMs"] as? NSNumber)?.int64Value == arrival
    }) {
      queued.append(payload)
      if queued.count > 50 { queued.removeFirst(queued.count - 50) }
      UserDefaults.standard.set(queued, forKey: Self.queueKey)
    }
    drainQueue()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if CLLocationManager.authorizationStatus() == .authorizedAlways {
      manager.startMonitoringVisits()
    }
  }

  private func drainQueue() {
    guard let eventSink else { return }
    DispatchQueue.main.async {
      let queued = UserDefaults.standard.array(forKey: Self.queueKey)
        as? [[String: Any]] ?? []
      for event in queued { eventSink(event) }
      if !queued.isEmpty {
        UserDefaults.standard.removeObject(forKey: Self.queueKey)
      }
    }
  }
}

private final class IosOnDeviceSpeechHandler: NSObject {
  private let channel: FlutterMethodChannel
  private let recognizer: SFSpeechRecognizer? = {
    let current = SFSpeechRecognizer(locale: Locale.current)
    if current?.supportsOnDeviceRecognition == true { return current }
    let english = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    return english?.supportsOnDeviceRecognition == true ? english : current
  }()
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var pendingResult: FlutterResult?
  private var timeoutWorkItem: DispatchWorkItem?
  private var silenceWorkItem: DispatchWorkItem?
  private var latestTranscription = ""
  private var hasAudioTap = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "private_concierge/on_device_speech",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func listenFromCar(
    punctuatePauses: Bool,
    completion: @escaping (String?, String?) -> Void
  ) {
    authorizeAndListen(result: { value in
      if let text = value as? String {
        completion(text, nil)
      } else if let error = value as? FlutterError {
        completion(nil, error.message ?? "Voice recognition failed.")
      } else {
        completion(nil, "Voice recognition failed.")
      }
    }, punctuatePauses: punctuatePauses)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(
        recognizer?.supportsOnDeviceRecognition == true
      )
    case "listenOnce":
      let arguments = call.arguments as? [String: Any]
      authorizeAndListen(
        result: result,
        punctuatePauses: arguments?["punctuatePauses"] as? Bool ?? false
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authorizeAndListen(
    result: @escaping FlutterResult,
    punctuatePauses: Bool
  ) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "already_listening",
          message: "Speech recognition is already active.",
          details: nil
        )
      )
      return
    }
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      guard status == .authorized else {
        result(
          FlutterError(
            code: "speech_permission",
            message: "Speech recognition permission was not granted.",
            details: nil
          )
        )
        return
      }
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async {
          guard granted else {
            result(
              FlutterError(
                code: "microphone_permission",
                message: "Microphone permission was not granted.",
                details: nil
              )
            )
            return
          }
          self?.startListening(
            result: result,
            punctuatePauses: punctuatePauses
          )
        }
      }
    }
  }

  private func startListening(
    result: @escaping FlutterResult,
    retryCount: Int = 0,
    punctuatePauses: Bool = false
  ) {
    guard let recognizer,
      recognizer.supportsOnDeviceRecognition
    else {
      result(
        FlutterError(
          code: "on_device_unavailable",
          message: "On-device speech recognition is unavailable.",
          details: nil
        )
      )
      return
    }
    do {
      resetRecognitionAudio()
      let session = AVAudioSession.sharedInstance()
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.duckOthers, .allowBluetoothHFP]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      if let preferred = session.availableInputs?.first(where: {
        $0.portType == .carAudio || $0.portType == .bluetoothHFP
      }) {
        try session.setPreferredInput(preferred)
      }

      CarAudioCuePlayer.shared.playListeningCue()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
        self?.beginRecognition(
          recognizer: recognizer,
          result: result,
          punctuatePauses: punctuatePauses
        )
      }
    } catch {
      if retryCount == 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
          self?.startListening(
            result: result,
            retryCount: 1,
            punctuatePauses: punctuatePauses
          )
        }
      } else {
        finish(error: error.localizedDescription, fallbackResult: result)
      }
    }
  }

  private func resetRecognitionAudio() {
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    silenceWorkItem?.cancel()
    silenceWorkItem = nil
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionRequest = nil
    recognitionTask = nil
    if audioEngine.isRunning { audioEngine.stop() }
    if hasAudioTap {
      audioEngine.inputNode.removeTap(onBus: 0)
      hasAudioTap = false
    }
    audioEngine.reset()
    latestTranscription = ""
  }

  private func beginRecognition(
    recognizer: SFSpeechRecognizer,
    result: @escaping FlutterResult,
    punctuatePauses: Bool
  ) {
    do {
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      request.taskHint = punctuatePauses ? .dictation : .search
      recognitionRequest = request
      pendingResult = result
      latestTranscription = ""

      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) {
        [weak request] buffer, _ in
        request?.append(buffer)
      }
      hasAudioTap = true
      audioEngine.prepare()
      try audioEngine.start()
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showListening()
      }

      recognitionTask = recognizer.recognitionTask(with: request) {
        [weak self] response, error in
        guard let self else { return }
        if let response {
          let rawText = punctuatePauses
            ? self.punctuate(response.bestTranscription)
            : response.bestTranscription.formattedString
          let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty {
            latestTranscription = text
            silenceWorkItem?.cancel()
            if response.isFinal {
              finish(text: text)
              return
            }
            let silence = DispatchWorkItem { [weak self] in
              guard let self, !latestTranscription.isEmpty else { return }
              recognitionRequest?.endAudio()
              finish(text: latestTranscription)
            }
            silenceWorkItem = silence
            DispatchQueue.main.asyncAfter(
              deadline: .now() + (punctuatePauses ? 2.5 : 1.4),
              execute: silence
            )
          }
        } else if let error {
          if !latestTranscription.isEmpty {
            finish(text: latestTranscription)
          } else {
            finish(error: error.localizedDescription)
          }
        }
      }

      let timeout = DispatchWorkItem { [weak self] in
        guard let self else { return }
        if latestTranscription.isEmpty {
          finish(error: "No speech was recognized before the timeout.")
        } else {
          finish(text: latestTranscription)
        }
      }
      timeoutWorkItem = timeout
      DispatchQueue.main.asyncAfter(
        deadline: .now() + (punctuatePauses ? 120 : 12),
        execute: timeout
      )
    } catch {
      finish(error: error.localizedDescription, fallbackResult: result)
    }
  }

  private func punctuate(_ transcription: SFTranscription) -> String {
    var output = ""
    var previousEnd: TimeInterval?
    var capitalizeNext = true
    for segment in transcription.segments {
      let word = segment.substring.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !word.isEmpty else { continue }
      if let previousEnd {
        let pause = segment.timestamp - previousEnd
        if pause >= 0.9 {
          if !output.hasSuffix(".") && !output.hasSuffix("!") &&
            !output.hasSuffix("?") { output += "." }
          capitalizeNext = true
        } else if pause >= 0.45 {
          if !output.hasSuffix(",") && !output.hasSuffix(";") &&
            !output.hasSuffix(":") { output += "," }
        }
        output += " "
      }
      if capitalizeNext {
        output += word.prefix(1).uppercased() + word.dropFirst()
        capitalizeNext = false
      } else {
        output += word
      }
      previousEnd = segment.timestamp + segment.duration
    }
    return output
  }

  private func finish(
    text: String? = nil,
    error: String? = nil,
    fallbackResult: FlutterResult? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      resetRecognitionAudio()
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
      let result = pendingResult ?? fallbackResult
      pendingResult = nil
      latestTranscription = ""
      if let error {
        result?(
          FlutterError(code: "recognition_failed", message: error, details: nil)
        )
      } else {
        result?(text ?? "")
      }
    }
  }
}
