# App Store release checklist

## Build

- [x] Production bundle identifiers and App Group are configured.
- [x] `ITSAppUsesNonExemptEncryption` is set to `NO`.
- [x] Bluetooth and optional location usage descriptions are present in English and Polish.
- [x] Privacy manifests are embedded in the iOS app, widget extension and watchOS app.
- [x] Account deletion is available inside the app and backed by `DELETE /api/v1/me`.
- [x] iOS tests pass.
- [x] Release archive validates without errors.
- [x] App Store Connect record is created for Apple ID `6797608558`.
- [x] Version and build number are confirmed as `1.4.2 (21)`.
- [x] App Store Connect archive and IPA export succeed with distribution signing.
- [ ] Uploaded build `1.4.2 (21)` finishes processing and is selected for version `1.4.2`.

## Production services

- [x] `https://touge-dash.letscode.it/privacy` is publicly accessible.
- [x] `https://touge-dash.letscode.it/support` is publicly accessible.
- [x] Production API exposes and verifies account deletion.
- [ ] Sign in with Apple callback and production domain are verified.
- [x] Dedicated review account is created and contains representative data.

## Product page

- [x] Polish and English name, subtitle, description, promotional text and keywords are updated for `1.4.2`.
- [x] Support, marketing and privacy URLs are selected.
- [x] App Privacy answers are documented.
- [x] App Privacy answers and privacy policy URL are published in App Store Connect.
- [x] iPhone 6.9-inch screenshots are prepared without an alpha channel.
- [x] iPad 13-inch screenshots are prepared without an alpha channel.
- [x] Apple Watch screenshots are prepared without an alpha channel.
- [x] iPhone and iPad screenshots are regenerated for the current four-tab `1.4.2 (21)` UI; Apple Watch screenshots are checked against the current Watch UI.
- [x] Age rating questionnaire is completed with a `4+` result.
- [x] Availability in 175 countries or regions, free price and manual release are configured.

## App Review

- [x] Hardware-specific review notes are prepared.
- [x] Physical ECU/EMULOGGER demonstration video is recorded and attached privately.
- [x] Review account credentials are entered only in App Store Connect.
- [x] Review contact is available by phone and email.
- [x] Review notes explain the optional persistent background GPS flow and current Settings path.
- [ ] Physical-device background-location recording is attached to App Review Information.
- [ ] Final build and all metadata are checked once more before `Submit for Review`.
- [ ] Build `1.4.2 (21)` is submitted for review.
