import CarPlay
import Foundation
import UIKit

struct CarPlayTelemetryPresentation: Equatable {
    enum Status: Equatable {
        case live
        case stale
        case temperatureAlert
        case criticalAlert
    }

    let status: Status
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
        guard let dashboardTemplate, let interfaceController else { return }
        let presentation = CarPlayTelemetryPresentation(snapshot: SharedTelemetryStore.load())
        guard presentation != lastPresentation else { return }
        let statusChanged = presentation.status != lastPresentation?.status
        lastPresentation = presentation
        if statusChanged {
            let replacement = makeDashboardTemplate(for: presentation)
            self.dashboardTemplate = replacement
            interfaceController.setRootTemplate(replacement, animated: false, completion: nil)
        } else {
            dashboardTemplate.updateSections([makeSection(for: presentation)])
        }
    }

    private func makeDashboardTemplate(for presentation: CarPlayTelemetryPresentation) -> CPListTemplate {
        CPListTemplate(
            title: "Touge Dash · \(statusTitle(for: presentation.status))",
            sections: [makeSection(for: presentation)]
        )
    }

    private func makeSection(for presentation: CarPlayTelemetryPresentation) -> CPListSection {
        CPListSection(items: [
            makeListItem(
                label: "AFR",
                value: presentation.afr,
                systemImage: "gauge.with.dots.needle.50percent"
            ),
            makeListItem(
                label: localized("OIL PRESSURE"),
                value: presentation.oilPressure,
                systemImage: "drop.fill"
            ),
            makeListItem(
                label: localized("OIL TEMP"),
                value: presentation.oilTemperature,
                systemImage: "thermometer.high"
            ),
            makeListItem(
                label: localized("COOLANT"),
                value: presentation.coolantTemperature,
                systemImage: "thermometer.and.liquid.waves"
            )
        ])
    }

    private func makeListItem(
        label: String,
        value: String,
        systemImage: String
    ) -> CPListItem {
        CPListItem(
            text: value,
            detailText: label,
            image: UIImage(systemName: systemImage) ?? UIImage(systemName: "gauge")!
        )
    }

    private func statusTitle(for status: CarPlayTelemetryPresentation.Status) -> String {
        switch status {
        case .live:
            "LIVE"
        case .stale:
            "OFFLINE"
        case .temperatureAlert:
            localized("TEMP ALERT")
        case .criticalAlert:
            localized("CHECK ENGINE")
        }
    }
}
