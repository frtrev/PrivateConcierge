import Flutter
import AVFoundation
import CarPlay
import MapKit
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if URLContexts.contains(where: {
      $0.url.scheme == "charon" && $0.url.host == "talk"
    }) {
      (UIApplication.shared.delegate as? AppDelegate)?.requestTalkFromCar()
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}

@available(iOS 14.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    let talk = CPGridButton(
      titleVariants: ["Talk to Charon"],
      image: microphoneButtonImage()
    ) { _ in
      (UIApplication.shared.delegate as? AppDelegate)?.requestTalkFromCar()
    }
    let template = CPGridTemplate(title: "Private Concierge", gridButtons: [talk])
    interfaceController.setRootTemplate(template, animated: false, completion: nil)
    CarPlaySessionCoordinator.shared.connect(
      interfaceController,
      scene: templateApplicationScene,
      homeTemplate: template
    )
  }

  private func microphoneButtonImage() -> UIImage {
    let size = CGSize(width: 120, height: 120)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
      let bounds = CGRect(origin: .zero, size: size)
      let diameter = min(size.width, size.height) * 0.84
      let circle = CGRect(
        x: (size.width - diameter) / 2,
        y: (size.height - diameter) / 2,
        width: diameter,
        height: diameter
      )
      UIColor(red: 0.843, green: 0.678, blue: 0.333, alpha: 1).setFill()
      context.cgContext.fillEllipse(in: circle)

      let symbolConfig = UIImage.SymbolConfiguration(
        pointSize: diameter * 0.45,
        weight: .semibold
      )
      guard let microphone = UIImage(
        systemName: "mic.fill",
        withConfiguration: symbolConfig
      )?.withTintColor(
        UIColor(red: 0.129, green: 0.09, blue: 0, alpha: 1),
        renderingMode: .alwaysOriginal
      ) else { return }
      let microphoneSize = microphone.size
      microphone.draw(
        at: CGPoint(
          x: bounds.midX - microphoneSize.width / 2,
          y: bounds.midY - microphoneSize.height / 2
        )
      )
    }.withRenderingMode(.alwaysOriginal)
  }
}

@available(iOS 14.0, *)
final class CarPlaySessionCoordinator: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = CarPlaySessionCoordinator()
  private weak var interfaceController: CPInterfaceController?
  private weak var carPlayScene: CPTemplateApplicationScene?
  private var homeTemplate: CPTemplate?
  private var latestPayload: [String: Any]?
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var listenAfterSpeech = false
  private var changingRootTemplate = false
  private var pendingRootTemplate: CPTemplate?

  private override init() {
    super.init()
    speechSynthesizer.delegate = self
  }

  func connect(
    _ interfaceController: CPInterfaceController,
    scene: CPTemplateApplicationScene,
    homeTemplate: CPTemplate
  ) {
    self.interfaceController = interfaceController
    self.carPlayScene = scene
    self.homeTemplate = homeTemplate
    if let latestPayload { show(payload: latestPayload) }
  }

  func showListening() {
    showMessage("Listening…", detail: "Speak now. Charon is using the active car audio input.")
  }

  func showStarting() {
    showMessage("Starting microphone…", detail: "Charon is connecting to the car audio input.")
  }

  func showBusy() {
    showMessage(
      "Charon is already listening…",
      detail: "Finish the current request or wait for it to time out."
    )
  }

  func showThinking(transcript: String) {
    showMessage("Thinking…", detail: "You said: \(transcript)")
  }

  func showRecognitionError(_ message: String) {
    showMessage("Charon couldn't listen", detail: message, showBack: true)
  }

  func showAlert(payload: [String: Any]) {
    guard let interfaceController else { return }
    let title = payload["title"] as? String ?? "Charon"
    let body = payload["body"] as? String ?? ""
    let dismiss = CPAlertAction(title: "Dismiss", style: .default) { _ in
      interfaceController.dismissTemplate(animated: true, completion: nil)
    }
    let message = body.isEmpty ? title : "\(title)\n\(body)"
    let alert = CPAlertTemplate(titleVariants: [message], actions: [dismiss])
    interfaceController.presentTemplate(alert, animated: true, completion: nil)
  }

  func showStatus(payload: [String: Any]) {
    let state = payload["state"] as? String ?? ""
    let message = payload["message"] as? String
    switch state {
    case "listening":
      showListening()
    case "processing":
      showMessage("Thinking…", detail: "Searching privately on this iPhone.")
    case "error", "unsupported":
      showMessage("Charon couldn't listen", detail: message ?? "Please try again.", showBack: true)
    default:
      break
    }
  }

  func showHome() {
    guard let homeTemplate else { return }
    latestPayload = nil
    setRootTemplate(homeTemplate, animated: true)
  }

  private func showMessage(
    _ message: String,
    detail: String,
    showBack: Bool = false
  ) {
    guard let interfaceController else { return }
    let status = CPListItem(text: message, detailText: detail)
    if #available(iOS 15.0, *) {
      status.isEnabled = false
    } else {
      status.handler = { _, completion in completion() }
    }
    var items = [status]
    if showBack {
      let goBack = CPListItem(text: "Go Back", detailText: nil)
      goBack.handler = { [weak self] _, completion in
        self?.showHome()
        completion()
      }
      items.append(goBack)
    }
    let template = CPListTemplate(
      title: "Private Concierge",
      sections: [CPListSection(items: items)]
    )
    setRootTemplate(template, animated: true)
  }

  func show(payload: [String: Any]) {
    latestPayload = payload
    guard let interfaceController else { return }
    let response = payload["spokenResponse"] as? String
      ?? payload["response"] as? String
      ?? "Charon finished the request."
    let places = payload["places"] as? [[String: Any]] ?? []
    let isNavigation = payload["type"] as? String == "navigation"
    listenAfterSpeech = response.trimmingCharacters(in: .whitespacesAndNewlines)
      .hasSuffix("?")
    speechSynthesizer.stopSpeaking(at: .immediate)
    if isNavigation {
      listenAfterSpeech = false
      releaseResponseAudioRoute()
      if let place = places.first {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          self?.navigate(to: place)
        }
      }
    } else {
      prepareResponseAudioRoute()
      CarAudioCuePlayer.shared.playResponseCue { [weak self] in
        // CarPlay/HFP needs a moment after acquiring the route. Without this
        // guard interval, the head unit can clip the first spoken words.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
          guard let self else { return }
          let utterance = AVSpeechUtterance(string: response)
          utterance.preUtteranceDelay = 0.15
          self.speechSynthesizer.speak(utterance)
        }
      }
    }
    let actions = payload["actions"] as? [[String: Any]] ?? []
    if let place = places.first,
      actions.contains(where: { $0["type"] as? String == "call" }),
      let phone = place["phoneNumber"] as? String
    {
      let digits = phone.filter { $0.isNumber || $0 == "+" }
      if let url = URL(string: "tel:\(digits)") {
        UIApplication.shared.open(url)
      }
    }
    let list = CPListSection(items: resultItems(response: response, places: places))
    let template = CPListTemplate(title: "Private Concierge", sections: [list])
    setRootTemplate(template, animated: true)
  }

  private func setRootTemplate(_ template: CPTemplate, animated: Bool) {
    guard let interfaceController else { return }
    if changingRootTemplate {
      pendingRootTemplate = template
      return
    }
    changingRootTemplate = true
    interfaceController.setRootTemplate(template, animated: animated) {
      [weak self] _, _ in
      guard let self else { return }
      self.changingRootTemplate = false
      guard let pending = self.pendingRootTemplate else { return }
      self.pendingRootTemplate = nil
      self.setRootTemplate(pending, animated: false)
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    guard listenAfterSpeech else {
      releaseResponseAudioRoute()
      return
    }
    listenAfterSpeech = false
    showMessage(
      "Your turn…",
      detail: "Charon will listen after the tone."
    )
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
      (UIApplication.shared.delegate as? AppDelegate)?.requestTalkFromCar()
    }
  }

  private func prepareResponseAudioRoute() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.duckOthers, .allowBluetoothHFP]
    )
    try? session.setActive(true, options: .notifyOthersOnDeactivation)
    if let carInput = session.availableInputs?.first(where: {
      $0.portType == .carAudio || $0.portType == .bluetoothHFP
    }) {
      try? session.setPreferredInput(carInput)
    }
  }

  private func releaseResponseAudioRoute() {
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
  }

  private func resultItems(
    response: String,
    places: [[String: Any]]
  ) -> [CPListItem] {
    let responseItem = CPListItem(text: response, detailText: nil)
    if #available(iOS 15.0, *) {
      responseItem.isEnabled = false
    } else {
      responseItem.handler = { _, completion in completion() }
    }
    var items = [responseItem]
    for place in places.prefix(5) {
      let name = place["name"] as? String ?? "Place"
      let address = place["address"] as? String ?? ""
      let distance = (place["distanceMeters"] as? NSNumber)?.doubleValue
      let miles = distance.map { String(format: "%.1f miles", $0 / 1609.344) }
      let detail = [miles, address.isEmpty ? nil : address]
        .compactMap { $0 }
        .joined(separator: " · ")
      let item = CPListItem(text: name, detailText: detail)
      item.handler = { [weak self] _, completion in
        self?.showPlace(place)
        completion()
      }
      items.append(item)
    }
    let goBack = CPListItem(text: "Go Back", detailText: nil)
    goBack.handler = { [weak self] _, completion in
      self?.showHome()
      completion()
    }
    items.append(goBack)
    return items
  }

  private func showPlace(_ place: [String: Any]) {
    guard let interfaceController else { return }
    let name = place["name"] as? String ?? "Place"
    let address = place["address"] as? String ?? ""
    let detail = CPListItem(text: name, detailText: address)
    let navigate = CPListItem(
      text: "Navigate",
      detailText: "Open the route in Maps, then tap Go"
    )
    navigate.handler = { [weak self] _, completion in
      self?.navigate(to: place)
      completion()
    }
    var detailItems = [detail, navigate]
    if let phone = place["phoneNumber"] as? String, !phone.isEmpty {
      let call = CPListItem(text: "Call", detailText: phone)
      call.handler = { _, completion in
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(digits)") {
          UIApplication.shared.open(url)
        }
        completion()
      }
      detailItems.append(call)
    }
    if place["website"] as? String != nil {
      let website = CPListItem(
        text: "Website available",
        detailText: "Open it from Charon on your phone"
      )
      if #available(iOS 15.0, *) { website.isEnabled = false }
      else { website.handler = { _, completion in completion() } }
      detailItems.append(website)
    }
    let template = CPListTemplate(
      title: name,
      sections: [CPListSection(items: detailItems)]
    )
    template.backButton = CPBarButton(type: .text) { [weak interfaceController] _ in
      interfaceController?.popTemplate(animated: true, completion: nil)
    }
    template.backButton?.title = "Back"
    interfaceController.pushTemplate(template, animated: true, completion: nil)
  }

  private func navigate(to place: [String: Any]) {
    guard let latitude = (place["latitude"] as? NSNumber)?.doubleValue,
      let longitude = (place["longitude"] as? NSNumber)?.doubleValue
    else { return }
    let item = MKMapItem(
      placemark: MKPlacemark(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
      )
    )
    item.name = place["name"] as? String
    let options = [
      MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
    ]
    if let carPlayScene {
      MKMapItem.openMaps(
        with: [MKMapItem.forCurrentLocation(), item],
        launchOptions: options,
        from: carPlayScene,
        // iOS 26.6 invokes this callback unconditionally after handing the
        // route to Maps. Passing nil causes an asynchronous MapKit crash.
        completionHandler: { _ in }
      )
    } else {
      item.openInMaps(launchOptions: options)
    }
  }
}

/// Short locally-generated cues keep the interaction eyes-free without adding
/// audio files to the app bundle. The completion fires after playback so the
/// listening cue cannot be captured as part of the driver's request.
final class CarAudioCuePlayer: NSObject, AVAudioPlayerDelegate {
  static let shared = CarAudioCuePlayer()

  private var player: AVAudioPlayer?
  private var completion: (() -> Void)?
  private var fallback: DispatchWorkItem?

  func playListeningCue() {
    play(
      segments: [(frequency: 880, duration: 0.13)],
      completion: {}
    )
  }

  func playResponseCue(completion: @escaping () -> Void) {
    play(
      segments: [
        (frequency: 660, duration: 0.08),
        (frequency: 880, duration: 0.11),
      ],
      completion: completion
    )
  }

  private func play(
    segments: [(frequency: Double, duration: Double)],
    completion: @escaping () -> Void
  ) {
    finishPlayback()
    do {
      let session = AVAudioSession.sharedInstance()
      if !session.isOtherAudioPlaying {
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
      }
      let player = try AVAudioPlayer(data: waveData(segments: segments))
      self.player = player
      self.completion = completion
      player.delegate = self
      player.volume = 0.65
      player.prepareToPlay()
      guard player.play() else {
        finishPlayback()
        return
      }
      let totalDuration = segments.reduce(0) { $0 + $1.duration }
      let fallback = DispatchWorkItem { [weak self] in self?.finishPlayback() }
      self.fallback = fallback
      DispatchQueue.main.asyncAfter(
        deadline: .now() + totalDuration + 0.15,
        execute: fallback
      )
    } catch {
      completion()
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    finishPlayback()
  }

  private func finishPlayback() {
    fallback?.cancel()
    fallback = nil
    player?.stop()
    player = nil
    let callback = completion
    completion = nil
    callback?()
  }

  private func waveData(
    segments: [(frequency: Double, duration: Double)]
  ) -> Data {
    let sampleRate = 22_050
    var samples = [Int16]()
    for segment in segments {
      let count = Int(segment.duration * Double(sampleRate))
      for index in 0..<count {
        let progress = Double(index) / Double(max(count - 1, 1))
        let envelope = min(min(progress / 0.12, (1 - progress) / 0.12), 1)
        let phase = 2 * Double.pi * segment.frequency * Double(index)
          / Double(sampleRate)
        samples.append(Int16(sin(phase) * envelope * 10_000))
      }
    }

    let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    appendLittleEndian(UInt32(36) + byteCount, to: &data)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    appendLittleEndian(UInt32(16), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(UInt32(sampleRate), to: &data)
    appendLittleEndian(UInt32(sampleRate * 2), to: &data)
    appendLittleEndian(UInt16(2), to: &data)
    appendLittleEndian(UInt16(16), to: &data)
    data.append(contentsOf: Array("data".utf8))
    appendLittleEndian(byteCount, to: &data)
    for sample in samples { appendLittleEndian(UInt16(bitPattern: sample), to: &data) }
    return data
  }

  private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
  }
}
