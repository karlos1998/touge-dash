# App Store release checklist

## Build

- [x] Production bundle identifiers and App Group are configured.
- [x] `ITSAppUsesNonExemptEncryption` is set to `NO`.
- [x] Bluetooth and optional location usage descriptions are present in Polish.
- [x] Privacy manifests are embedded in the iOS app, widget extension and watchOS app.
- [x] Account deletion is available inside the app and backed by `DELETE /api/v1/me`.
- [x] iOS tests pass.
- [x] Release archive validates without errors.
- [x] App Store Connect record is created for Apple ID `6797608558`.
- [x] Version and build number are confirmed as `1.0 (2)`.
- [x] App Store Connect IPA export succeeds with distribution signing.
- [ ] Uploaded build `1.0 (2)` finishes processing in App Store Connect.

## Production services

- [x] `https://touge-dash.letscode.it/privacy` is publicly accessible.
- [x] `https://touge-dash.letscode.it/support` is publicly accessible.
- [x] Production API exposes and verifies account deletion.
- [ ] Sign in with Apple callback and production domain are verified.
- [x] Dedicated review account is created and contains representative data.

## Product page

- [x] Polish name, subtitle, description, promotional text and keywords are prepared.
- [x] Support, marketing and privacy URLs are selected.
- [x] App Privacy answers are documented.
- [x] iPhone 6.9-inch screenshots are prepared without an alpha channel.
- [x] iPad 13-inch screenshots are prepared without an alpha channel.
- [x] Apple Watch screenshots are prepared without an alpha channel.
- [x] iPhone, iPad and Apple Watch screenshots are uploaded to version `1.0`.
- [ ] Age rating questionnaire is completed.
- [ ] Availability, price and manual release are configured.

## App Review

- [x] Hardware-specific review notes are prepared.
- [ ] Physical ECU/EMULOGGER demonstration video is recorded and attached.
- [ ] Review account credentials are entered only in App Store Connect.
- [ ] Review contact is available by phone and email.
- [ ] Final build and all metadata are checked once more before `Submit for Review`.
