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
    let template = CPGridTemplate(title: "Charon", gridButtons: [talk])
    interfaceController.setRootTemplate(template, animated: false, completion: nil)
    CarPlaySessionCoordinator.shared.connect(interfaceController)
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
final class CarPlaySessionCoordinator {
  static let shared = CarPlaySessionCoordinator()
  private weak var interfaceController: CPInterfaceController?
  private var latestPayload: [String: Any]?
  private let speechSynthesizer = AVSpeechSynthesizer()

  private init() {}

  func connect(_ interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    if let latestPayload { show(payload: latestPayload) }
  }

  func show(payload: [String: Any]) {
    latestPayload = payload
    guard let interfaceController else { return }
    let response = payload["spokenResponse"] as? String
      ?? payload["response"] as? String
      ?? "Charon finished the request."
    speechSynthesizer.stopSpeaking(at: .immediate)
    speechSynthesizer.speak(AVSpeechUtterance(string: response))
    let places = payload["places"] as? [[String: Any]] ?? []
    if payload["type"] as? String == "navigation", let place = places.first {
      navigate(to: place)
    }
    let list = CPListSection(items: resultItems(response: response, places: places))
    let template = CPListTemplate(title: "Charon", sections: [list])
    interfaceController.setRootTemplate(template, animated: true, completion: nil)
  }

  private func resultItems(
    response: String,
    places: [[String: Any]]
  ) -> [CPListItem] {
    var items = [CPListItem(text: response, detailText: nil)]
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
    let talkAgain = CPListItem(text: "Talk to Charon", detailText: "Ask a follow-up")
    talkAgain.handler = { _, completion in
      (UIApplication.shared.delegate as? AppDelegate)?.requestTalkFromCar()
      completion()
    }
    items.append(talkAgain)
    return items
  }

  private func showPlace(_ place: [String: Any]) {
    guard let interfaceController else { return }
    let name = place["name"] as? String ?? "Place"
    let address = place["address"] as? String ?? ""
    let detail = CPListItem(text: name, detailText: address)
    let navigate = CPListItem(text: "Navigate", detailText: "Open directions in Maps")
    navigate.handler = { [weak self] _, completion in
      self?.navigate(to: place)
      completion()
    }
    let template = CPListTemplate(
      title: name,
      sections: [CPListSection(items: [detail, navigate])]
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
    item.openInMaps(launchOptions: [
      MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
    ])
  }
}
