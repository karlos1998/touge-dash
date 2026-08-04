# Critical Alerts

Touge Dash uses Time Sensitive notifications as the safe fallback. True Critical Alerts are enabled only after Apple approves the restricted entitlement for `it.letscode.touge-dash`.

After approval:

1. Add `com.apple.developer.usernotifications.critical-alerts = true` to the iPhone entitlement in `ios/Config/TougeDash.entitlements` and `ios/project.yml`. Add it to the Watch target too if Apple grants the entitlement for the Watch app identifier.
2. Set `TOUGE_DASH_CRITICAL_ALERTS_ENABLED = YES` in `ios/project.yml`.
3. Regenerate the project with `xcodegen generate --spec ios/project.yml` and refresh the provisioning profile.
4. Verify the system Critical Alerts consent prompt on a physical device before submitting the build.

Apple entitlement request: https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/
