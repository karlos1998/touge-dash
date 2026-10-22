# Critical Alerts

Touge Dash uses Time Sensitive notifications as the safe fallback. True Critical Alerts are enabled only after Apple approves the restricted entitlement for `it.letscode.touge-dash`.

After approval:

1. Add `com.apple.developer.usernotifications.critical-alerts = true` to the iPhone entitlement in `ios/Config/TougeDash.entitlements` and `ios/project.yml`. Add it to the Watch target too if Apple grants the entitlement for the Watch app identifier.
2. Set `TOUGE_DASH_CRITICAL_ALERTS_ENABLED = YES` in `ios/project.yml`.
3. Regenerate the project with `xcodegen generate --spec ios/project.yml` and refresh the provisioning profile.
4. Verify the system Critical Alerts consent prompt on a physical device before submitting the build.

Apple entitlement request: https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/

## Request prepared on 2026-10-22

Apple Developer → Identifiers → `it.letscode.touge-dash` → Capability Requests
shows **Critical Alerts: No Requests**. Both the direct request URL and the
request link for this App ID redirect the currently signed-in App Manager to
`https://developer.apple.com/unauthorized/`. No request has been submitted.
Apple requires the Account Holder to submit managed capability requests for an organization; granting Admin access is not sufficient. The Account Holder should open the request link.
Official role requirement: https://developer.apple.com/help/account/capabilities/capability-requests
The account also displays a separate license-update notice with an October 29,
2026 deadline; the Account Holder must handle acceptance. The portal does not
establish whether that notice is the cause of the request-access denial.

### Text to submit to Apple

App: Touge Dash — https://apps.apple.com/app/id6797608558
Bundle ID: `it.letscode.touge-dash`
Team ID: `UCT44QZ8L4`
Requested capability: `com.apple.developer.usernotifications.critical-alerts`
Platforms: iOS and iPadOS (the companion Watch mirrors iPhone notifications).

Touge Dash receives live engine telemetry over Bluetooth Low Energy from a
compatible ECUMaster Data Logger EDL-1 connected to an EMU Black ECU. We request
Critical Alerts for confirmed engine conditions requiring prompt driver
attention: loss of oil or fuel pressure under engine load, excessively lean AFR
under boost, overboost, and excessive coolant or oil temperature. These
conditions can precede engine damage or a sudden loss of propulsion. The driver
may have the phone locked, silenced or in Driving Focus and must not need to
look continuously at the phone to notice such an event.

These notifications are generated locally from live telemetry. Each rule has
configurable thresholds, load/RPM gates and a confirmation duration; transient
outliers do not trigger an alert. Events are latched while the condition remains
active and have a repeat cooldown. Low battery voltage remains a noncritical
warning. We will not use Critical Alerts for marketing, account, synchronization
or routine connection notifications.

After Apple grants the entitlement, the app will explicitly request the user's
Critical Alerts authorization. When the user does not grant or disables that
permission, alerts fall back to Time Sensitive notifications. The notification
identifies the engine condition and asks the driver to pull over safely and
check the engine. Touge Dash is an auxiliary telemetry display and does not
claim to be a certified vehicle safety system or replace the vehicle's own
warning systems.

The app is available without an account, works offline with compatible hardware,
and already has the CarPlay Driving Task entitlement. A hardware demonstration
can be provided if requested.
