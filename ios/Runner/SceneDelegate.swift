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

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    CarPlaySessionCoordinator.shared.disconnect(interfaceController)
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
  private struct PendingAlert {
    let payload: [String: Any]
    let queuedAt: Date
  }

  static let shared = CarPlaySessionCoordinator()
  private weak var interfaceController: CPInterfaceController?
  private weak var carPlayScene: CPTemplateApplicationScene?
  private var homeTemplate: CPTemplate?
  private var latestPayload: [String: Any]?
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var listenAfterSpeech = false
  private var changingRootTemplate = false
  private var pendingRootTemplate: CPTemplate?
  private var pendingAlerts: [PendingAlert] = []
  private var presentingAlert = false
  private var activePrayer: [String: Any]?
  private var pendingAutomaticPrayer: [String: Any]?
  private var prayerPaused = false
  private(set) var shouldCapturePrayerText = false
  private var processingTimer: Timer?
  private weak var processingItem: CPListItem?
  private var processingPhase = 0
  private var responseAudioHasStarted = false
  private let alertLifetime: TimeInterval = 5 * 60

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
    presentNextAlertIfPossible()
  }

  func disconnect(_ interfaceController: CPInterfaceController) {
    guard self.interfaceController === interfaceController else { return }
    self.interfaceController = nil
    carPlayScene = nil
    homeTemplate = nil
    presentingAlert = false
    stopProcessingAnimation()
    stopPrayer()
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
    startProcessingAnimation(transcript: transcript)
  }

  func showRecognitionError(_ message: String) {
    stopProcessingAnimation()
    showMessage("Charon couldn't listen", detail: message, showBack: true)
  }

  func showAlert(payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.pendingAlerts.append(PendingAlert(payload: payload, queuedAt: Date()))
      if self.pendingAlerts.count > 5 {
        self.pendingAlerts.removeFirst(self.pendingAlerts.count - 5)
      }
      self.presentNextAlertIfPossible()
    }
  }

  private func presentNextAlertIfPossible() {
    guard !presentingAlert, let interfaceController else { return }
    let now = Date()
    pendingAlerts.removeAll { now.timeIntervalSince($0.queuedAt) > alertLifetime }
    guard !pendingAlerts.isEmpty else { return }
    let alertPayload = pendingAlerts.removeFirst().payload
    presentingAlert = true
    let title = alertPayload["title"] as? String ?? "Charon"
    let body = alertPayload["body"] as? String ?? ""
    let dismiss = CPAlertAction(title: "Dismiss", style: .default) { [weak self] _ in
      guard let self else { return }
      interfaceController.dismissTemplate(animated: true) { [weak self] _, _ in
        guard let self else { return }
        self.presentingAlert = false
        self.presentNextAlertIfPossible()
      }
    }
    let message = body.isEmpty ? title : "\(title)\n\(body)"
    let alert = CPAlertTemplate(titleVariants: [message], actions: [dismiss])
    interfaceController.presentTemplate(alert, animated: true) { [weak self] presented, error in
      guard let self else { return }
      if !presented || error != nil {
        self.presentingAlert = false
        self.showAlertAsList(title: title, body: body)
      }
    }
  }

  private func showAlertAsList(title: String, body: String) {
    guard let interfaceController else { return }
    let message = CPListItem(text: title, detailText: body)
    message.handler = { _, completion in completion() }
    let dismiss = CPListItem(text: "Dismiss", detailText: nil)
    dismiss.handler = { [weak self] _, completion in
      guard let self else {
        completion()
        return
      }
      self.presentingAlert = false
      self.showHome()
      completion()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.presentNextAlertIfPossible()
      }
    }
    let template = CPListTemplate(
      title: "Private Concierge",
      sections: [CPListSection(items: [message, dismiss])]
    )
    setRootTemplate(template, animated: true)
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
    stopProcessingAnimation()
    stopPrayer()
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
    responseAudioHasStarted = false
    shouldCapturePrayerText = payload["capturePrayerText"] as? Bool ?? false
    let prayerChoices = payload["prayerChoices"] as? [[String: Any]] ?? []
    let context = payload["context"] as? [String: Any]
    if context?["lastIntent"] as? String == "playPrayer", prayerChoices.count == 1 {
      var automaticPrayer = prayerChoices[0]
      automaticPrayer["announce"] = false
      pendingAutomaticPrayer = automaticPrayer
    } else {
      pendingAutomaticPrayer = nil
    }
    listenAfterSpeech = shouldCapturePrayerText || response
      .trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    if isNavigation {
      stopProcessingAnimation()
      listenAfterSpeech = false
      releaseResponseAudioRoute()
      if let place = places.first {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          self?.navigate(to: place)
        }
      }
      renderLatestResult()
    } else {
      CarAudioCuePlayer.shared.playResponseCue { [weak self] in
        // CarPlay/HFP needs a moment after acquiring the route. Without this
        // guard interval, the head unit can clip the first spoken words.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
          guard let self else { return }
          (UIApplication.shared.delegate as? AppDelegate)?.speakCarResponse(response) {
            [weak self] succeeded in
            guard let self else { return }
            if !succeeded && !self.responseAudioHasStarted {
              self.stopProcessingAnimation()
              self.renderLatestResult()
            }
            self.responseSpeechFinished()
          }
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
  }

  func responseAudioStarted() {
    guard !responseAudioHasStarted else { return }
    responseAudioHasStarted = true
    stopProcessingAnimation()
    renderLatestResult()
  }

  private func startProcessingAnimation(transcript: String) {
    stopProcessingAnimation()
    processingPhase = 0
    let item = CPListItem(
      text: "Thinking, please wait…",
      detailText: processingDetail(transcript: transcript)
    )
    if #available(iOS 15.0, *) { item.isEnabled = false }
    else { item.handler = { _, completion in completion() } }
    processingItem = item
    setRootTemplate(
      CPListTemplate(
        title: "Private Concierge",
        sections: [CPListSection(items: [item])]
      ),
      animated: true
    )
    processingTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) {
      [weak self] _ in
      guard let self, let item = self.processingItem else { return }
      self.processingPhase = (self.processingPhase + 1) % 4
      item.setDetailText(self.processingDetail(transcript: transcript))
    }
  }

  private func processingDetail(transcript: String) -> String {
    let pulse = ["●  ○  ○", "○  ●  ○", "○  ○  ●", "○  ●  ○"][processingPhase]
    return "\(pulse)\nYou said: \(transcript)"
  }

  private func stopProcessingAnimation() {
    processingTimer?.invalidate()
    processingTimer = nil
    processingItem = nil
    processingPhase = 0
  }

  private func responseSpeechFinished() {
    if let prayer = pendingAutomaticPrayer {
      pendingAutomaticPrayer = nil
      playPrayer(prayer)
      return
    }
    guard listenAfterSpeech else { return }
    listenAfterSpeech = false
    showMessage("Your turn…", detail: "Charon will listen after the tone.")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
      (UIApplication.shared.delegate as? AppDelegate)?.requestTalkFromCar()
    }
  }

  func updatePrayerPlayback(_ payload: [String: Any]) {
    let state = payload["state"] as? String ?? ""
    if payload["id"] != nil { activePrayer = payload }
    prayerPaused = state == "paused"
    if state == "stopped" || state == "completed" {
      activePrayer = nil
      prayerPaused = false
    }
    renderPrayerPlayback(state: state)
  }

  private func playPrayer(_ prayer: [String: Any]) {
    activePrayer = prayer
    prayerPaused = false
    renderPrayerPlayback(state: "playing")
    (UIApplication.shared.delegate as? AppDelegate)?.playCarPrayer(prayer) {}
  }

  private func togglePrayerPause() {
    guard activePrayer != nil else { return }
    prayerPaused.toggle()
    let method = prayerPaused ? "pauseCarPrayer" : "resumeCarPrayer"
    (UIApplication.shared.delegate as? AppDelegate)?.controlCarPrayer(method)
    renderPrayerPlayback(state: prayerPaused ? "paused" : "playing")
  }

  private func stopPrayer() {
    guard activePrayer != nil else { return }
    (UIApplication.shared.delegate as? AppDelegate)?.controlCarPrayer("stopCarPrayer")
    activePrayer = nil
    prayerPaused = false
  }

  private func renderPrayerPlayback(state: String) {
    guard let prayer = activePrayer else {
      renderLatestResult()
      return
    }
    let name = prayer["name"] as? String ?? "Prayer"
    let status = CPListItem(
      text: state == "paused" ? "Paused" : "Now praying",
      detailText: name
    )
    if #available(iOS 15.0, *) { status.isEnabled = false }
    else { status.handler = { _, completion in completion() } }
    let pause = CPListItem(text: prayerPaused ? "Continue" : "Pause", detailText: nil)
    pause.handler = { [weak self] _, completion in
      self?.togglePrayerPause()
      completion()
    }
    let stop = CPListItem(text: "Stop", detailText: nil)
    stop.handler = { [weak self] _, completion in
      self?.stopPrayer()
      self?.renderLatestResult()
      completion()
    }
    setRootTemplate(
      CPListTemplate(
        title: "Private Concierge",
        sections: [CPListSection(items: [status, pause, stop])]
      ),
      animated: true
    )
  }

  private func renderLatestResult() {
    guard let latestPayload else {
      showHome()
      return
    }
    let template = CPListTemplate(
      title: "Private Concierge",
      sections: [CPListSection(items: resultItems(payload: latestPayload))]
    )
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

  private func resultItems(payload: [String: Any]) -> [CPListItem] {
    let response = payload["response"] as? String ?? "Charon finished the request."
    let places = payload["places"] as? [[String: Any]] ?? []
    let responseItem = CPListItem(text: response, detailText: nil)
    responseItem.handler = { _, completion in completion() }
    var items = [responseItem]
    for prayer in (payload["prayerChoices"] as? [[String: Any]] ?? []).prefix(9) {
      let name = prayer["name"] as? String ?? "Prayer"
      let kind = (prayer["isRoutine"] as? Bool) == true ? "Prayer routine" : "Prayer"
      let item = CPListItem(text: name, detailText: "Play \(kind.lowercased())")
      item.handler = { [weak self] _, completion in
        self?.playPrayer(prayer)
        completion()
      }
      items.append(item)
    }
    // CarPlay allows twelve rows here: the response, up to ten places, and Go Back.
    for place in places.prefix(max(0, 10 - items.count)) {
      let name = place["name"] as? String ?? "Place"
      let address = place["address"] as? String ?? ""
      let distance = (place["distanceMeters"] as? NSNumber)?.doubleValue
      let miles = distance.map { String(format: "%.1f miles", $0 / 1609.344) }
      let detail = [miles, address.isEmpty ? nil : address]
        .compactMap { $0 }
        .joined(separator: " · ")
      let visitTimes = visitTimeDetail(place)
      let fullDetail = [detail.isEmpty ? nil : detail, visitTimes]
        .compactMap { $0 }
        .joined(separator: "\n")
      let item = CPListItem(text: name, detailText: fullDetail)
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

  private func visitTimeDetail(_ place: [String: Any]) -> String? {
    guard let arrivalMs = (place["arrivalMs"] as? NSNumber)?.doubleValue else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd h:mm a"
    let arrival = formatter.string(from: Date(timeIntervalSince1970: arrivalMs / 1000))
    let departure = (place["departureMs"] as? NSNumber).map {
      formatter.string(from: Date(timeIntervalSince1970: $0.doubleValue / 1000))
    } ?? "Still there"
    return "Arrived: \(arrival)  Left: \(departure)"
  }

  private func showPlace(_ place: [String: Any]) {
    guard let interfaceController else { return }
    let name = place["name"] as? String ?? "Place"
    let address = place["address"] as? String ?? ""
    let detailText = [address.isEmpty ? nil : address, visitTimeDetail(place)]
      .compactMap { $0 }
      .joined(separator: "\n")
    let detail = CPListItem(text: name, detailText: detailText)
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
      preparePlaybackRoute: true,
      completion: completion
    )
  }

  private func play(
    segments: [(frequency: Double, duration: Double)],
    preparePlaybackRoute: Bool = false,
    completion: @escaping () -> Void
  ) {
    finishPlayback()
    do {
      let session = AVAudioSession.sharedInstance()
      if preparePlaybackRoute {
        try? session.setCategory(
          .playback,
          mode: .spokenAudio,
          options: [.duckOthers]
        )
      }
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
