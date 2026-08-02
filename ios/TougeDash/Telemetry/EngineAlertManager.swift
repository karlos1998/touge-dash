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

    func evaluate(_ snapshot: TelemetrySnapshot) {
        let coolantIsHot = snapshot.coolantCelsius >= EngineTemperatureLimits.coolantWarningCelsius
        let oilIsHot = snapshot.oilTemperatureCelsius >= EngineTemperatureLimits.oilWarningCelsius
        let shouldNotify = (coolantIsHot && !coolantAlertLatched) || (oilIsHot && !oilAlertLatched)

        if coolantIsHot {
            coolantAlertLatched = true
        } else if snapshot.coolantCelsius <= EngineTemperatureLimits.coolantResetCelsius {
            coolantAlertLatched = false
        }

        if oilIsHot {
            oilAlertLatched = true
        } else if snapshot.oilTemperatureCelsius <= EngineTemperatureLimits.oilResetCelsius {
            oilAlertLatched = false
        }

        guard shouldNotify else { return }
        postTemperatureNotification(snapshot)
    }

    private func postTemperatureNotification(_ snapshot: TelemetrySnapshot) {
        let content = UNMutableNotificationContent()
        content.title = "Touge Dash — wysoka temperatura"
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
        if snapshot.coolantCelsius >= EngineTemperatureLimits.coolantWarningCelsius {
            warnings.append("Płyn chłodniczy: \(Int(snapshot.coolantCelsius))°C")
        }
        if snapshot.oilTemperatureCelsius >= EngineTemperatureLimits.oilWarningCelsius {
            warnings.append("Olej: \(Int(snapshot.oilTemperatureCelsius))°C")
        }
        return warnings.joined(separator: " • ") + ". Zatrzymaj auto i sprawdź silnik."
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
