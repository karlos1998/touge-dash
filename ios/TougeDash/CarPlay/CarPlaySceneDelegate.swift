import CarPlay
import Foundation

struct CarPlayTelemetryPresentation: Equatable {
    enum Status: Equatable {
        case live
        case stale
        case temperatureAlert
        case criticalAlert
    }

    let status: Status
    let rpm: String
    let boost: String
    let afr: String
    let oilPressure: String
    let oilTemperature: String
    let coolantTemperature: String

    init(snapshot: TelemetrySnapshot, now: Date = .now) {
        let isFresh = now.timeIntervalSince(snapshot.updatedAt) < 2.5
        if !isFresh {
            status = .stale
        } else if snapshot.hasCheckEngine {
            status = .criticalAlert
        } else if snapshot.hasTemperatureWarning {
            status = .temperatureAlert
        } else if snapshot.hasCriticalWarning {
            status = .criticalAlert
        } else {
            status = .live
        }

        rpm = Int(snapshot.rpm.rounded()).formatted(.number.grouping(.never)) + " rpm"
        boost = snapshot.boostBar.formatted(.number.precision(.fractionLength(2))) + " bar"
        afr = snapshot.afr.formatted(.number.precision(.fractionLength(1)))
        oilPressure = snapshot.oilPressureBar.formatted(.number.precision(.fractionLength(1))) + " bar"
        oilTemperature = Int(snapshot.oilTemperatureCelsius.rounded()).formatted() + " °C"
        coolantTemperature = Int(snapshot.coolantCelsius.rounded()).formatted() + " °C"
    }
}

@MainActor
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var dashboardTemplate: CPListTemplate?
    private var updateTask: Task<Void, Never>?
    private var lastPresentation: CarPlayTelemetryPresentation?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let presentation = CarPlayTelemetryPresentation(snapshot: SharedTelemetryStore.load())
        let template = makeDashboardTemplate(for: presentation)
        dashboardTemplate = template
        lastPresentation = presentation
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshDashboard()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        updateTask?.cancel()
        updateTask = nil
        dashboardTemplate = nil
        lastPresentation = nil
        self.interfaceController = nil
    }

    private func refreshDashboard() {
        guard let dashboardTemplate else { return }
        let presentation = CarPlayTelemetryPresentation(snapshot: SharedTelemetryStore.load())
        guard presentation != lastPresentation else { return }
        lastPresentation = presentation
        dashboardTemplate.updateSections([makeSection(for: presentation)])
    }

    private func makeDashboardTemplate(for presentation: CarPlayTelemetryPresentation) -> CPListTemplate {
        CPListTemplate(
            title: "Touge Dash",
            sections: [makeSection(for: presentation)]
        )
    }

    private func makeSection(for presentation: CarPlayTelemetryPresentation) -> CPListSection {
        let rows = [
            CPListItem(text: "RPM", detailText: presentation.rpm),
            CPListItem(text: localized("BOOST"), detailText: presentation.boost),
            CPListItem(text: "AFR", detailText: presentation.afr),
            CPListItem(text: localized("OIL PRESSURE"), detailText: presentation.oilPressure),
            CPListItem(text: localized("OIL TEMP"), detailText: presentation.oilTemperature),
            CPListItem(text: localized("COOLANT"), detailText: presentation.coolantTemperature)
        ]
        return CPListSection(
            items: rows,
            header: statusTitle(for: presentation.status),
            sectionIndexTitle: nil
        )
    }

    private func statusTitle(for status: CarPlayTelemetryPresentation.Status) -> String {
        switch status {
        case .live:
            localized("LIVE DATA")
        case .stale:
            localized("Rozłączono")
        case .temperatureAlert:
            localized("TEMP ALERT")
        case .criticalAlert:
            localized("CHECK ENGINE")
        }
    }
}
