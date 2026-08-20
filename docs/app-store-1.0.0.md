# App Store 1.0.0 release

The repository is configured as version `1.0.0` build `1`, bundle identifier
`com.neotheone.privateconcierge`, and display name **Private Concierge**.

## App Store Connect metadata

- Name: Private Concierge
- Subtitle: Private, on-device assistant
- Primary category: Lifestyle
- Secondary category: Navigation
- Age rating: Complete the current App Store Connect questionnaire based on
  the shipped app; the app contains no advertising, gambling, or unrestricted
  web access.
- App privacy: Personal location, voice input, prayers, and profile data are
  processed only on device and are not collected by the developer. Public map
  and optional model hosts receive normal download requests and IP addresses.
- Encryption: The app uses only exempt encryption for HTTPS and declares
  `ITSAppUsesNonExemptEncryption` as false.

## Suggested description

Private Concierge is a privacy-first personal assistant that remembers places,
answers questions about nearby businesses and your private visit history, and
supports saved prayers and prayer routines. Location history, speech text,
preferences, prayers, and on-device AI processing remain on your device. There
is no account, advertising, analytics SDK, or personal-data backend.

Download offline Overture Maps coverage for nearby-place search, optionally add
an on-device language model and Kokoro voices, and use Private Concierge from
your iPhone or compatible CarPlay interface.

## Review notes

- No account or demo credentials are required.
- Location can be denied, but nearby and visit-history features require it.
- Always location access is used only for private on-device visit recognition.
- Microphone and speech recognition are used for on-device assistant commands
  and prayer dictation. Microphone audio is not retained.
- The optional local AI and Kokoro packages are user-initiated downloads.
- CarPlay requires the approved voice-based conversation entitlement on the
  App ID and distribution provisioning profile.

## Account-owned items still required

- Host the privacy policy on a public HTTPS page and enter that URL in App Store
  Connect. The same policy is available under **Settings → Privacy policy**.
- Supply a public HTTPS support URL and support contact details.
- Create the App Store Connect app record for bundle ID
  `com.neotheone.privateconcierge` if it does not already exist.
- Upload current iPhone and iPad screenshots, complete the age-rating and
  availability questionnaires, and select manual or automatic release.
- Test the archive through TestFlight on a physical iPhone and a real CarPlay
  head unit before submitting for review.

## Verified release artifact

The 1.0.0 release audit produced `build/ios/ipa/private_concierge.ipa` with
Xcode 26.6 and the iOS 26.5 SDK. The exported IPA is signed for App Store
distribution, passes strict code-signature verification, has
`get-task-allow=false`, and contains the approved
`com.apple.developer.carplay-voice-based-conversation` entitlement. Xcode also
generated an active App Store provisioning profile for the bundle identifier.

## Release commands

```sh
flutter analyze
flutter test
flutter build ipa --release --build-name=1.0.0 --build-number=1
```

Upload the generated archive with Xcode Organizer or upload the IPA with an
authorized App Store Connect workflow.
