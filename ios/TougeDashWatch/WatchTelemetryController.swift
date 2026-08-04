@preconcurrency import WatchConnectivity
@preconcurrency import UserNotifications
import Combine
import Foundation
import WatchKit

@MainActor
final class WatchTelemetryController: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = WatchTelemetryPayload.empty
    @Published private(set) var isReachable = false

    private static let storedSnapshotKey = "watchTelemetrySnapshot"
    private static let handledAlertIDsKey = "watchHandledAlertIDs"
    private static let notifiedAlertIDsKey = "watchNotifiedAlertIDs"
    private let session: WCSession?
    private let notificationCenter = UNUserNotificationCenter.current()
    private var handledAlertIDs: Set<UUID>
    private var notifiedAlertIDs: Set<UUID>

    override init() {
        handledAlertIDs = Set(
            (UserDefaults.standard.array(forKey: Self.handledAlertIDsKey) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        )
        notifiedAlertIDs = Set(
            (UserDefaults.standard.array(forKey: Self.notifiedAlertIDsKey) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        )
        if let data = UserDefaults.standard.data(forKey: Self.storedSnapshotKey),
           let stored = try? JSONDecoder().decode(WatchTelemetryPayload.self, from: data) {
            snapshot = stored
        }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let showsPreview = environment["TOUGE_DASH_WATCH_PREVIEW"] == "1"
            || arguments.contains("--touge-watch-preview")
        let showsAlertPreview = environment["TOUGE_DASH_WATCH_ALERT_PREVIEW"] == "1"
            || arguments.contains("--touge-watch-alert-preview")
        if showsPreview || showsAlertPreview {
            var preview = WatchTelemetryPayload.preview
            if showsAlertPreview {
                preview.coolantCelsius = 112
                preview.oilTemperatureCelsius = 124
                preview.hasCriticalWarning = true
                preview.activeAlerts = [EngineAlertEvent(
                    id: UUID(uuidString: "DEADBEEF-0000-4000-8000-000000000001")!,
                    kind: .highCoolantTemperature,
                    severity: .critical,
                    value: 112,
                    threshold: 110,
                    unit: "°C",
                    triggeredAt: .now
                )]
            }
            preview.updatedAt = .now.addingTimeInterval(300)
            snapshot = preview
        }
        #endif

        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()
        #if DEBUG
        if !showsPreview, !showsAlertPreview {
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        #else
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
        session?.delegate = self
        session?.activate()
    }

    private func ingest(_ data: Data, isAlertDelivery: Bool = false) {
        guard let value = try? JSONDecoder().decode(WatchTelemetryPayload.self, from: data) else { return }
        let newAlerts = value.engineAlerts.filter { !handledAlertIDs.contains($0.id) }
        let notificationAlerts = isAlertDelivery
            ? value.engineAlerts.filter { !notifiedAlertIDs.contains($0.id) }
            : []
        let shouldPlayTemperatureAlert = value.hasTemperatureWarning && !snapshot.hasTemperatureWarning
        let shouldPlayEngineAlert = value.hasCriticalWarning && !snapshot.hasCriticalWarning
        snapshot = value
        UserDefaults.standard.set(data, forKey: Self.storedSnapshotKey)
        if !newAlerts.isEmpty {
            handledAlertIDs.formUnion(newAlerts.map(\.id))
            persistHandledAlertIDs()
            WKInterfaceDevice.current().play(.failure)
        } else if shouldPlayTemperatureAlert {
            WKInterfaceDevice.current().play(.failure)
        } else if shouldPlayEngineAlert {
            WKInterfaceDevice.current().play(.notification)
        }
        if !notificationAlerts.isEmpty {
            notifiedAlertIDs.formUnion(notificationAlerts.map(\.id))
            persistNotifiedAlertIDs()
            postAlertNotification(notificationAlerts)
        }
    }

    private func postAlertNotification(_ alerts: [EngineAlertEvent]) {
        let content = UNMutableNotificationContent()
        content.title = localized("Krytyczny alert silnika")
        content.body = alerts.map { title(for: $0.kind) }.joined(separator: " • ")
            + ". " + localized("Zatrzymaj auto i sprawdź silnik.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        notificationCenter.add(UNNotificationRequest(
            identifier: "touge-dash-watch-alert-" + alerts.map(\.id.uuidString).joined(separator: "-"),
            content: content,
            trigger: nil
        ))
    }

    private func title(for kind: EngineAlertKind) -> String {
        switch kind {
        case .lowOilPressure: localized("Niskie ciśnienie oleju")
        case .leanUnderBoost: localized("Uboga mieszanka pod boostem")
        case .overboost: localized("Przekroczone doładowanie")
        case .highCoolantTemperature: localized("Wysoka temperatura płynu")
        case .highOilTemperature: localized("Wysoka temperatura oleju")
        case .lowFuelPressure: localized("Niskie ciśnienie paliwa")
        case .lowBatteryVoltage: localized("Niskie napięcie")
        }
    }

    private func persistHandledAlertIDs() {
        if handledAlertIDs.count > 64 {
            handledAlertIDs = Set(handledAlertIDs.prefix(64))
        }
        UserDefaults.standard.set(handledAlertIDs.map(\.uuidString), forKey: Self.handledAlertIDsKey)
    }

    private func persistNotifiedAlertIDs() {
        if notifiedAlertIDs.count > 64 {
            notifiedAlertIDs = Set(notifiedAlertIDs.prefix(64))
        }
        UserDefaults.standard.set(notifiedAlertIDs.map(\.uuidString), forKey: Self.notifiedAlertIDsKey)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let data = context[WatchTelemetryPayload.contextKey] as? Data
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if let data {
                self?.ingest(data)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor [weak self] in
            self?.ingest(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchTelemetryPayload.contextKey] as? Data else { return }
        let isAlert = message["tougeDashAlertEvent"] as? Bool == true
        Task { @MainActor [weak self] in
            self?.ingest(data, isAlertDelivery: isAlert)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchTelemetryPayload.contextKey] as? Data else { return }
        let isAlert = userInfo["tougeDashAlertEvent"] as? Bool == true
        Task { @MainActor [weak self] in
            self?.ingest(data, isAlertDelivery: isAlert)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchTelemetryPayload.contextKey] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.ingest(data)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }
}
