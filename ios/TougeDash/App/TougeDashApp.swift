import SwiftData
import SwiftUI
import UIKit

@MainActor
final class TougeDashAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == SeventyMaiBackgroundDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        SeventyMaiBackgroundDownloadCoordinator.shared.storeBackgroundCompletionHandler(completionHandler)
    }
}

@main
@MainActor
struct TougeDashApp: App {
    @UIApplicationDelegateAdaptor(TougeDashAppDelegate.self) private var appDelegate
    @AppStorage(AppAppearance.defaultsKey) private var appearanceValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.defaultsKey) private var languageValue = AppLanguage.system.rawValue
    @AppStorage(CompatibilityOnboarding.acceptanceKey) private var compatibilityAccepted = false
    private let modelContainer: ModelContainer
    @State private var controller: TelemetryController
    @State private var cloudAccount: CloudAccountService
    @State private var cloudSync: CloudSyncManager
    @State private var dashboardTemplates: DashboardTemplateStore
    @State private var dashboardBuffer: DashboardTelemetryBuffer
    @State private var videoRecorder: DriveVideoRecorder
    @State private var videoOverlays: VideoOverlayTemplateStore

    init() {
        PerformanceDiagnostics.shared.start()
        do {
            let container = try ModelContainer(
                for: DriveSession.self,
                TelemetryHistorySample.self,
                DriveVideoRecording.self,
                DriveIncident.self,
                TimelineAnnotation.self,
                AccelerationAttempt.self
            )
            let locationTracker = LocationTrackingService()
            let historyRecorder = TelemetryHistoryRecorder(
                container: container,
                locationTracker: locationTracker
            )
            let accelerationEngine = AccelerationEngine()
            let account = CloudAccountService()
            let alertRules = VehicleAlertRuleStore()
            let templates = DashboardTemplateStore()
            let dashboardBuffer = DashboardTelemetryBuffer()
            let videoSettings = DriveVideoSettingsStore()
            let videoRecorder = DriveVideoRecorder(container: container, settings: videoSettings)
            let videoOverlays = VideoOverlayTemplateStore()
            let sync = CloudSyncManager(
                container: container,
                account: account,
                locationTracker: locationTracker,
                dashboardTemplates: templates,
                alertRules: alertRules
            )
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1" {
                historyRecorder.seedPreviewDataIfNeeded()
                Task { await historyRecorder.seedPreviewVideoIfNeeded() }
            }
            #endif
            modelContainer = container
            _cloudAccount = State(initialValue: account)
            _cloudSync = State(initialValue: sync)
            _dashboardTemplates = State(initialValue: templates)
            _dashboardBuffer = State(initialValue: dashboardBuffer)
            _videoRecorder = State(initialValue: videoRecorder)
            _videoOverlays = State(initialValue: videoOverlays)
            let incidentRecorder = TelemetryIncidentRecorder(
                container: container,
                locationTracker: locationTracker,
                alertRules: alertRules
            )
            incidentRecorder.onIncidentStored = { sampleCount in
                sync.noteLocalIncidentRecorded(sampleCount: sampleCount)
            }
            _controller = State(initialValue: TelemetryController(
                historyRecorder: historyRecorder,
                incidentRecorder: incidentRecorder,
                cloudSync: sync,
                videoRecorder: videoRecorder,
                accelerationEngine: accelerationEngine,
                startTelemetryOnLaunch: UserDefaults.standard.bool(
                    forKey: CompatibilityOnboarding.acceptanceKey
                )
            ))
        } catch {
            fatalError("Unable to create telemetry history store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TougeDashRootView(
                controller: controller,
                cloudAccount: cloudAccount,
                cloudSync: cloudSync,
                dashboardTemplates: dashboardTemplates,
                dashboardBuffer: dashboardBuffer,
                videoRecorder: videoRecorder,
                videoOverlays: videoOverlays,
                appearance: appearanceBinding,
                language: languageBinding
            )
                .fullScreenCover(isPresented: compatibilityOnboardingPresented) {
                    CompatibilityOnboarding {
                        compatibilityAccepted = true
                        controller.startTelemetryIfNeeded()
                    }
                    .interactiveDismissDisabled()
                }
                .preferredColorScheme(appearance.colorScheme)
                .environment(\.locale, language.locale)
        }
        .modelContainer(modelContainer)
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceValue) ?? .system
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearance },
            set: { appearanceValue = $0.rawValue }
        )
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageValue) ?? .system
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { languageValue = $0.rawValue }
        )
    }

    private var compatibilityOnboardingPresented: Binding<Bool> {
        Binding(
            get: { !compatibilityAccepted },
            set: { _ in }
        )
    }
}

private struct CompatibilityOnboarding: View {
    static let acceptanceKey = "tougeDash.compatibilityAccepted.v1"

    let onContinue: () -> Void
    @State private var confirmed = false

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 18)

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.tougeCyan)
                        .frame(width: 64, height: 64)
                        .background(Color.tougeCyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(localized("ZANIM ZACZNIESZ"))
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                            .foregroundStyle(Color.tougeCyan)
                        Text(localized("Touge Dash nie jest aplikacją OBD2"))
                            .font(.largeTitle.weight(.black))
                        Text(localized("Aplikacja jest przeznaczona dla użytkowników ECUMaster i łączy się z Data Loggerem EDL-1 obsługującym Bluetooth Low Energy (BLE)."))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        requirement("antenna.radiowaves.left.and.right", localized("Wymagany: ECUMaster Data Logger EDL-1 z BLE"))
                        requirement("car.side.fill", localized("To nie jest uniwersalny interfejs do każdego auta"))
                        requirement("cable.connector", localized("Aplikacja nie odczytuje danych z gniazda OBD2"))
                    }
                    .padding(18)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))

                    Button {
                        confirmed.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(confirmed ? Color.tougeCyan : Color.secondary)
                            Text(localized("Rozumiem wymagania i mam zgodny Data Logger EDL-1 z BLE."))
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: onContinue) {
                        Text(localized("Przejdź do aplikacji"))
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.tougeCyan)
                    .foregroundStyle(.black)
                    .disabled(!confirmed)

                    Spacer(minLength: 18)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func requirement(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.tougeCyan)
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    static let defaultsKey = "tougeDash.appearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: localized("Systemowy")
        case .light: localized("Jasny")
        case .dark: localized("Ciemny")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
