@preconcurrency import UserNotifications
import Foundation

@MainActor
final class EngineAlertManager: NSObject, UNUserNotificationCenterDelegate {
    private let notificationCenter = UNUserNotificationCenter.current()
    private var coolantAlertLatched = false
    private var oilAlertLatched = false

    override init() {
        super.init()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(_ snapshot: TelemetrySnapshot, rules: VehicleAlertRules) {
        let coolantIsHot = snapshot.hasCoolantWarning
        let oilIsHot = snapshot.hasOilTemperatureWarning
        let shouldNotify = (coolantIsHot && !coolantAlertLatched) || (oilIsHot && !oilAlertLatched)

        if coolantIsHot {
            coolantAlertLatched = true
        } else if !rules.highCoolantTemperatureEnabled ||
                    snapshot.coolantCelsius <= rules.maximumCoolantCelsius - 5 {
            coolantAlertLatched = false
        }

        if oilIsHot {
            oilAlertLatched = true
        } else if !rules.highOilTemperatureEnabled ||
                    snapshot.oilTemperatureCelsius <= rules.maximumOilTemperatureCelsius - 5 {
            oilAlertLatched = false
        }

        guard shouldNotify else { return }
        postTemperatureNotification(snapshot)
    }

    private func postTemperatureNotification(_ snapshot: TelemetrySnapshot) {
        let content = UNMutableNotificationContent()
        content.title = localized("Touge Dash — wysoka temperatura")
        content.body = warningDescription(for: snapshot)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.threadIdentifier = "touge-dash-engine-alerts"

        let identifier = "touge-dash-temperature-alert"
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func warningDescription(for snapshot: TelemetrySnapshot) -> String {
        var warnings: [String] = []
        if snapshot.hasCoolantWarning {
            warnings.append(String(format: localized("Płyn chłodniczy: %d°C"), Int(snapshot.coolantCelsius)))
        }
        if snapshot.hasOilTemperatureWarning {
            warnings.append(String(format: localized("Olej: %d°C"), Int(snapshot.oilTemperatureCelsius)))
        }
        return warnings.joined(separator: " • ") + ". " + localized("Zatrzymaj auto i sprawdź silnik.")
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
