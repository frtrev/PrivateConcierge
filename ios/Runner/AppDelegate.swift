import Flutter
import AVFoundation
import CoreLocation
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var speechHandler: IosOnDeviceSpeechHandler?
  private var navigationChannel: FlutterMethodChannel?
  private var visitMonitoringHandler: IosVisitMonitoringHandler?
  private var carChannel: FlutterMethodChannel?
  private var pendingTalkRequest = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "IosOnDeviceSpeech"
    ) else { return }
    carChannel = FlutterMethodChannel(
      name: "charon/car",
      binaryMessenger: registrar.messenger()
    )
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
    guard let speechHandler, let carChannel else {
      pendingTalkRequest = true
      self.carChannel?.invokeMethod("talkRequested", arguments: nil)
      return
    }
    if #available(iOS 14.0, *) {
      CarPlaySessionCoordinator.shared.showStarting()
    }
    speechHandler.listenFromCar { [weak self] text, error in
      guard let self else { return }
      if let error {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showRecognitionError(error)
        }
        return
      }
      guard let text, !text.isEmpty else {
        if #available(iOS 14.0, *) {
          CarPlaySessionCoordinator.shared.showRecognitionError(
            "I didn't hear anything. Please try again."
          )
        }
        return
      }
      if #available(iOS 14.0, *) {
        CarPlaySessionCoordinator.shared.showThinking(transcript: text)
      }
      carChannel.invokeMethod("submitRecognizedText", arguments: text) { result in
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

  func listenFromCar(completion: @escaping (String?, String?) -> Void) {
    authorizeAndListen { value in
      if let text = value as? String {
        completion(text, nil)
      } else if let error = value as? FlutterError {
        completion(nil, error.message ?? "Voice recognition failed.")
      } else {
        completion(nil, "Voice recognition failed.")
      }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(
        recognizer?.supportsOnDeviceRecognition == true
      )
    case "listenOnce":
      authorizeAndListen(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authorizeAndListen(result: @escaping FlutterResult) {
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
          self?.startListening(result: result)
        }
      }
    }
  }

  private func startListening(result: @escaping FlutterResult) {
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
      let session = AVAudioSession.sharedInstance()
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
        self?.beginRecognition(recognizer: recognizer, result: result)
      }
    } catch {
      finish(error: error.localizedDescription, fallbackResult: result)
    }
  }

  private func beginRecognition(
    recognizer: SFSpeechRecognizer,
    result: @escaping FlutterResult
  ) {
    do {
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      request.taskHint = .search
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
          let text = response.bestTranscription.formattedString
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
              deadline: .now() + 1.4,
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
      DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    } catch {
      finish(error: error.localizedDescription, fallbackResult: result)
    }
  }

  private func finish(
    text: String? = nil,
    error: String? = nil,
    fallbackResult: FlutterResult? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
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
