import Flutter
import AVFoundation
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var speechHandler: IosOnDeviceSpeechHandler?

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
    speechHandler = IosOnDeviceSpeechHandler(
      messenger: registrar.messenger()
    )
  }
}

private final class IosOnDeviceSpeechHandler: NSObject {
  private let channel: FlutterMethodChannel
  private let recognizer = SFSpeechRecognizer(locale: Locale.current)
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var pendingResult: FlutterResult?
  private var timeoutWorkItem: DispatchWorkItem?
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

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(
        recognizer?.isAvailable == true &&
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
      recognizer.isAvailable,
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
      try session.setCategory(.record, mode: .measurement, options: .duckOthers)
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = false
      recognitionRequest = request
      pendingResult = result

      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      input.installTap(onBus: 0, bufferSize: 1024, format: format) {
        [weak request] buffer, _ in
        request?.append(buffer)
      }
      hasAudioTap = true
      audioEngine.prepare()
      try audioEngine.start()

      recognitionTask = recognizer.recognitionTask(with: request) {
        [weak self] response, error in
        if let response, response.isFinal {
          self?.finish(text: response.bestTranscription.formattedString)
        } else if let error {
          self?.finish(error: error.localizedDescription)
        }
      }

      let timeout = DispatchWorkItem { [weak self] in
        self?.finish(error: "No speech was recognized before the timeout.")
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
