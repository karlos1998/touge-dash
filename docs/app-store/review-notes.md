# App Review notes

Touge Dash is an independent telemetry dashboard for compatible Bluetooth Low Energy interfaces connected to an ECUMaster EMU Black ECU. It does not contain or reuse code or assets from ECUMaster eDash.

## Important hardware information

Live engine values require all of the following:

1. an ECUMaster EMU Black ECU installed in a vehicle,
2. a compatible BLE data interface advertising as `EMULOGGER`,
3. Bluetooth access on the iPhone.

The app automatically discovers and reconnects to the compatible interface. It intentionally does not present the reviewer with a list of unrelated Bluetooth devices.

Because this hardware and a running vehicle are difficult to provide to App Review, a screen recording made with the physical ECU, EMULOGGER and iPhone will be attached in App Store Connect. The recording demonstrates automatic connection, live dashboard updates, history recording, Live Activity and Apple Watch updates.

The app remains usable without the hardware: the reviewer can inspect navigation, account functionality, permissions, existing synchronized vehicle data in the web dashboard and account deletion. No feature requires payment or an in-app purchase.

## Review account

A dedicated production review account will be entered in the App Review Information fields in App Store Connect. Its password is intentionally not stored in this repository.

The account uses the same production environment as the submitted build and contains a sample vehicle and recorded session. It can be used through email and password without access to a third-party social account.

## Suggested review flow

1. Launch the app and allow Bluetooth access. Without the required interface, the dashboard correctly shows a disconnected state.
2. Open `Historia` to inspect the local history and optional GPS controls.
3. Select `Włącz synchronizację online`, then sign in with the review credentials supplied in App Store Connect.
4. Open the account menu to inspect the privacy policy, sign out and account deletion entry point.
5. The matching web dashboard is available at `https://touge-dash.letscode.it/`.

Account deletion is available in the app under `Historia` → `Touge Dash Cloud` → account menu → `Usuń konto`. The operation permanently removes server-side account data. Local, offline history remains on the user's device until the user removes it or uninstalls the app.

GPS recording is off by default. Location is requested only after the user explicitly enables route recording. Notifications are used for high oil-temperature and coolant-temperature alerts.

Touge Dash is not a certified gauge. The app tells users to compare readings with the ECU manufacturer's software and not to interact with the app in a way that distracts them while driving.

## Attachments before submission

- physical-hardware review video URL or App Review attachment,
- review account email and password,
- contact phone number available during the review window.

