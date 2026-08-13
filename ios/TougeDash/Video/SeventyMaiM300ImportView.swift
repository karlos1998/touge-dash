@preconcurrency import ActivityKit
import NetworkExtension
import SwiftUI

@MainActor
private final class SeventyMaiImportActivityManager {
    private var activity: Activity<DashcamImportActivityAttributes>?
    private var lastState: DashcamImportActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private var pendingState: DashcamImportActivityAttributes.ContentState?
    private var updateTask: Task<Void, Never>?

    func start(totalClips: Int, firstFileName: String, cameraName: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<DashcamImportActivityAttributes>.activities.first {
            activity = existing
        }
        let state = DashcamImportActivityAttributes.ContentState(
            phase: .downloading,
            currentClip: min(1, totalClips),
            totalClips: totalClips,
            fileName: firstFileName,
            receivedBytes: 0,
            expectedBytes: 0
        )
        lastState = state
        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(20)))
            return
        }
        activity = try? Activity.request(
            attributes: DashcamImportActivityAttributes(cameraName: cameraName),
            content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(20)),
            pushType: nil
        )
    }

    func consume(_ progress: SeventyMaiM300Progress) {
        let state: DashcamImportActivityAttributes.ContentState?
        switch progress {
        case .downloading(let current, let total, let name, let received, let expected):
            state = DashcamImportActivityAttributes.ContentState(
                phase: .downloading,
                currentClip: current,
                totalClips: total,
                fileName: name,
                receivedBytes: received,
                expectedBytes: expected
            )
        case .joining, .inspecting:
            guard var processing = lastState else { return }
            processing.phase = .processing
            state = processing
        default:
            state = nil
        }
        guard let state else { return }
        lastState = state
        pendingState = state
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.flushUpdates()
        }
    }

    func finish(succeeded: Bool) async {
        updateTask?.cancel()
        updateTask = nil
        pendingState = nil
        guard let activity, var state = lastState else { return }
        state.phase = succeeded ? .completed : .failed
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: succeeded ? .after(.now.addingTimeInterval(10)) : .default
        )
        self.activity = nil
        lastState = nil
    }

    private func flushUpdates() async {
        while !Task.isCancelled, pendingState != nil {
            let delay = 1 - Date().timeIntervalSince(lastUpdate)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let state = pendingState, let activity else { break }
            pendingState = nil
            lastUpdate = .now
            await activity.update(ActivityContent(state: state, staleDate: .now.addingTimeInterval(20)))
        }
        updateTask = nil
    }
}

@MainActor
final class SeventyMaiM300ImportViewModel: ObservableObject {
    @Published private(set) var scanResult: SeventyMaiM300ScanResult?
    @Published private(set) var progress: SeventyMaiM300Progress?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorTitle = localized("Nie udało się połączyć z kamerą 70mai")
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var activeCameraModel: SeventyMaiCameraModel = .m300

    private let client = SeventyMaiM300Client()
    private let activityManager = SeventyMaiImportActivityManager()

    var statusTitle: String {
        guard let progress else { return localized("Gotowe do połączenia") }
        switch progress {
        case .probing: return localized("Szukanie kamery…")
        case .requestingAuthorization: return localized("Rozpoczynanie autoryzacji…")
        case .waitingForButton: return localized("Potwierdź na kamerze")
        case .readingClock: return localized("Synchronizowanie zegara…")
        case .readingRecordings: return localized("Odczytywanie nagrań…")
        case .enteringAlbum: return localized("Otwieranie pamięci kamery…")
        case .downloading(let current, let total, _, let received, let expected):
            guard expected > 0 else {
                return String(format: localized("Pobieranie klipu %d z %d…"), current, total)
            }
            let percent = min(100, max(0, Int((Double(received) / Double(expected) * 100).rounded())))
            return String(format: localized("Pobieranie klipu %d z %d · %d%%"), current, total, percent)
        case .joining: return localized("Łączenie klipów…")
        case .inspecting: return localized("Sprawdzanie gotowego filmu…")
        }
    }

    var statusDetail: String {
        guard let progress else {
            return String(
                format: localized("Włącz Wi‑Fi w %@. Nazwę hotspotu znajdziesz na kamerze lub jej ekranie."),
                activeCameraModel.displayName
            )
        }
        switch progress {
        case .probing(let host):
            return String(format: localized("Sprawdzanie %@ w lokalnej sieci Wi‑Fi."), host)
        case .requestingAuthorization:
            return localized("Touge Dash wysyła do kamery żądanie bezpiecznego połączenia.")
        case .waitingForButton:
            return localized("Potwierdź połączenie przyciskiem lub na ekranie kamery, zgodnie z jej komunikatem.")
        case .readingClock:
            return localized("Porównywanie czasu kamery z czasem iPhone’a.")
        case .readingRecordings(let page):
            return String(format: localized("Strona nagrań: %d"), page)
        case .enteringAlbum:
            return localized("W tym trybie kamera może chwilowo wstrzymać nagrywanie.")
        case .downloading(_, _, let name, let received, let expected):
            guard expected > 0 else { return name }
            return String(
                format: localized("%@ · %@ z %@"),
                name,
                DriveVideoFileStore.formattedSize(received),
                DriveVideoFileStore.formattedSize(expected)
            )
        case .joining:
            return localized("Zachowywanie kolejności klipów i wycinanie zakresu przejazdu.")
        case .inspecting:
            return localized("Odczytywanie rozdzielczości, dźwięku i dokładnej długości.")
        }
    }

    var downloadFraction: Double? {
        guard case .downloading(_, _, _, let received, let expected) = progress,
              expected > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(expected)))
    }

    func connectAndScan(
        ssid: String,
        password: String,
        cameraModel: SeventyMaiCameraModel,
        channel: SeventyMaiCameraChannel,
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) async {
        activeCameraModel = cameraModel
        let cleanSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSSID.isEmpty else {
            errorTitle = localized("Nie udało się połączyć z kamerą 70mai")
            errorMessage = String(format: localized("Podaj pełną nazwę hotspotu, np. %@."), cameraModel.ssidPlaceholder)
            return
        }
        await runScan(
            cameraModel: cameraModel,
            channel: channel,
            sessionStartedAt: sessionStartedAt,
            sessionEndedAt: sessionEndedAt
        ) {
            try await Self.joinHotspot(ssid: cleanSSID, password: password)
            diagnostics.append("Wi‑Fi: \(cleanSSID)")
        }
    }

    func scanCurrentConnection(
        cameraModel: SeventyMaiCameraModel,
        channel: SeventyMaiCameraChannel,
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) async {
        activeCameraModel = cameraModel
        await runScan(
            cameraModel: cameraModel,
            channel: channel,
            sessionStartedAt: sessionStartedAt,
            sessionEndedAt: sessionEndedAt,
            beforeScan: {}
        )
    }

    func importVideo(
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) async -> PreparedSeventyMaiImport? {
        guard let scanResult, !isBusy else { return nil }
        isBusy = true
        errorMessage = nil
        errorTitle = localized("Nie udało się ukończyć importu")
        defer {
            isBusy = false
            progress = nil
        }
        await activityManager.start(
            totalClips: scanResult.clips.count,
            firstFileName: scanResult.clips.first?.name ?? "",
            cameraName: scanResult.cameraModel.displayName
        )
        do {
            let prepared = try await client.importClips(
                scanResult,
                sessionStartedAt: sessionStartedAt,
                sessionEndedAt: sessionEndedAt,
                progress: progressHandler
            )
            diagnostics.append("Gotowy film: \(prepared.metadata.duration.formatted(.number.precision(.fractionLength(1)))) s")
            await activityManager.finish(succeeded: true)
            return prepared
        } catch {
            errorMessage = error.localizedDescription
            diagnostics.append("Błąd importu: \(error.localizedDescription)")
            await activityManager.finish(succeeded: false)
            return nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func resetSelection(cameraModel: SeventyMaiCameraModel) {
        guard !isBusy else { return }
        activeCameraModel = cameraModel
        scanResult = nil
        progress = nil
        errorMessage = nil
        diagnostics = []
    }

    private func runScan(
        cameraModel: SeventyMaiCameraModel,
        channel: SeventyMaiCameraChannel,
        sessionStartedAt: Date,
        sessionEndedAt: Date,
        beforeScan: () async throws -> Void
    ) async {
        guard !isBusy else { return }
        isBusy = true
        scanResult = nil
        errorMessage = nil
        errorTitle = localized("Nie udało się połączyć z kamerą 70mai")
        diagnostics = []
        defer { isBusy = false }
        do {
            try await beforeScan()
            let result = try await client.scan(
                cameraModel: cameraModel,
                channel: channel,
                sessionStartedAt: sessionStartedAt,
                sessionEndedAt: sessionEndedAt,
                progress: progressHandler
            )
            scanResult = result
            diagnostics.append("Model: \(cameraModel.displayName)")
            diagnostics.append("Kanał: \(channel.displayName) · typ \(cameraModel.recordingType(for: channel) ?? "?")")
            diagnostics.append("Host: \(result.host)")
            if let offset = result.clockOffsetSeconds {
                diagnostics.append("Różnica zegara: \(String(format: "%+.2f", offset)) s")
            } else {
                diagnostics.append("Różnica zegara: niedostępna")
            }
            diagnostics.append("Pasujące klipy: \(result.clips.count)")
            progress = nil
        } catch {
            errorMessage = error.localizedDescription
            diagnostics.append("Błąd skanowania: \(error.localizedDescription)")
            progress = nil
        }
    }

    private var progressHandler: SeventyMaiM300Client.ProgressHandler {
        { [weak self] progress in
            guard let self, shouldAccept(progress) else { return }
            self.progress = progress
            self.activityManager.consume(progress)
            if case .waitingForButton = progress,
               diagnostics.last != "Oczekiwanie na przycisk kamery" {
                diagnostics.append("Oczekiwanie na przycisk kamery")
            }
        }
    }

    private func shouldAccept(_ newProgress: SeventyMaiM300Progress) -> Bool {
        guard case .downloading(
            let newCurrent,
            _,
            _,
            let newReceived,
            _
        ) = newProgress,
        case .downloading(
            let current,
            _,
            _,
            let received,
            _
        ) = progress else { return true }
        if newCurrent != current { return newCurrent > current }
        return newReceived >= received
    }

    private static func joinHotspot(ssid: String, password: String) async throws {
        let configuration: NEHotspotConfiguration
        if password.isEmpty {
            configuration = NEHotspotConfiguration(ssid: ssid)
        } else {
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        }
        configuration.joinOnce = false
        try await withCheckedThrowingContinuation { continuation in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                if let nsError = error as NSError?,
                   nsError.domain == NEHotspotConfigurationErrorDomain,
                   nsError.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
                    continuation.resume()
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

struct SeventyMaiImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let session: DriveSession
    let onImported: (PreparedSeventyMaiImport) -> Void

    @StateObject private var model = SeventyMaiM300ImportViewModel()
    @AppStorage("TougeDash.dashcam.m300.ssid") private var ssid = ""
    @AppStorage("TougeDash.dashcam.70mai.model") private var cameraModelRawValue = SeventyMaiCameraModel.m300.rawValue
    @State private var selectedChannel = SeventyMaiCameraChannel.front
    @State private var password = "12345678"
    @State private var showsPassword = false
    @State private var showsDiagnostics = false
    @State private var showsMissingCameraAlert = false

    private var selectedCameraModel: SeventyMaiCameraModel {
        SeventyMaiCameraModel(rawValue: cameraModelRawValue) ?? .m300
    }

    private var cameraModelBinding: Binding<SeventyMaiCameraModel> {
        Binding(
            get: { selectedCameraModel },
            set: { newValue in
                cameraModelRawValue = newValue.rawValue
                selectedChannel = newValue.channels.first ?? .front
                model.resetSelection(cameraModel: newValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cameraModelCard
                    warningCard
                    connectionCard
                    statusCard
                    if let result = model.scanResult { recordingsCard(result) }
                    if !model.diagnostics.isEmpty { diagnosticsCard }
                }
                .padding()
            }
            .background(DashboardBackground())
            .navigationTitle(localized("Kamera 70mai"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Zamknij")) { dismiss() }
                        .disabled(model.isBusy)
                }
            }
            .alert(model.errorTitle, isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )) {
                Button(localized("OK"), role: .cancel) { model.clearError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(model.isBusy)
        .onAppear {
            model.resetSelection(cameraModel: selectedCameraModel)
        }
    }

    private var cameraModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized("MODEL I KANAŁ"), systemImage: "car.side.front.open")
                .font(.system(size: 11, weight: .black))
                .tracking(1.1)
                .foregroundStyle(Color.tougeCyan)

            Picker(localized("Model kamery"), selection: cameraModelBinding) {
                ForEach(SeventyMaiCameraModel.allCases) { camera in
                    Text(camera.displayName).tag(camera)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isBusy)

            if selectedCameraModel.channels.count > 1 {
                Picker(localized("Kanał nagrania"), selection: $selectedChannel) {
                    ForEach(selectedCameraModel.channels) { channel in
                        Label(channel.displayName, systemImage: channel.systemImage).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isBusy)
                .onChange(of: selectedChannel) { _, _ in
                    model.resetSelection(cameraModel: selectedCameraModel)
                }

                Text(localized("Wybierz kamerę, której obraz ma zostać nałożony na telemetrię. Kanał tylny wymaga podłączonej kamery tylnej."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(localized("Nie ma Twojej kamery na liście?")) {
                showsMissingCameraAlert = true
            }
            .font(.caption.weight(.bold))
            .disabled(model.isBusy)
            .alert(localized("Dodajmy obsługę Twojej kamery"), isPresented: $showsMissingCameraAlert) {
                Button(localized("Instagram: WWY_SUPRA")) {
                    openURL(URL(string: "https://www.instagram.com/wwy_supra/")!)
                }
                Button(localized("E-mail: kontakt@letscode.it")) {
                    openURL(URL(string: "mailto:kontakt@letscode.it?subject=Obs%C5%82uga%20kamery%2070mai%20w%20Touge%20Dash")!)
                }
                Button(localized("Anuluj"), role: .cancel) {}
            } message: {
                Text(localized("Napisz do nas i podaj dokładny model kamery oraz wersję firmware. Sprawdzimy, czy możemy dodać jej obsługę."))
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("Importuj po zakończeniu jazdy"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.tougeYellow)
            Text(localized("Podczas przeglądania pamięci kamera może wstrzymać bieżące nagrywanie. Touge Dash nie usuwa plików ani nie zmienia ustawień kamery."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.tougeYellow.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized("HOTSPOT KAMERY"), systemImage: "wifi")
                .font(.system(size: 11, weight: .black))
                .tracking(1.1)
                .foregroundStyle(Color.tougeMint)

            TextField(selectedCameraModel.ssidPlaceholder, text: $ssid)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            HStack {
                Group {
                    if showsPassword {
                        TextField(localized("Hasło Wi‑Fi"), text: $password)
                    } else {
                        SecureField(localized("Hasło Wi‑Fi"), text: $password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button { showsPassword.toggle() } label: {
                    Image(systemName: showsPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            Text(localized("Pełną nazwę hotspotu znajdziesz na kamerze, jej ekranie lub w instrukcji. Fabryczne hasło większości modeli to 12345678."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await model.connectAndScan(
                        ssid: ssid,
                        password: password,
                        cameraModel: selectedCameraModel,
                        channel: selectedChannel,
                        sessionStartedAt: session.startedAt,
                        sessionEndedAt: session.endedAt
                    )
                }
            } label: {
                Label(localized("Połącz i znajdź nagrania"), systemImage: "wifi.circle.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(.tougeMint)
            .disabled(model.isBusy)

            Button {
                Task {
                    await model.scanCurrentConnection(
                        cameraModel: selectedCameraModel,
                        channel: selectedChannel,
                        sessionStartedAt: session.startedAt,
                        sessionEndedAt: session.endedAt
                    )
                }
            } label: {
                Text(localized("iPhone jest już połączony — tylko sprawdź kamerę"))
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.tougeCyan)
            .disabled(model.isBusy)
        }
        .padding(16)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if model.isBusy {
                    ProgressView()
                        .tint(.tougeMint)
                } else {
                    Image(systemName: model.scanResult == nil ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
                        .foregroundStyle(model.scanResult == nil ? Color.secondary : Color.tougeMint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusTitle)
                        .font(.subheadline.weight(.black))
                    Text(model.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = model.downloadFraction {
                ProgressView(value: fraction)
                    .tint(.tougeMint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func recordingsCard(_ result: SeventyMaiM300ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("DOPASOWANE NAGRANIA"), systemImage: "film.stack.fill")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(Color.tougeCyan)
                Spacer()
                Text(result.clips.count.formatted())
                    .font(.headline.monospacedDigit().weight(.black))
            }

            ForEach(result.clips) { clip in
                recordingRow(clip)
            }

            importButton
        }
        .padding(16)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }

    private func recordingRow(_ clip: SeventyMaiM300Clip) -> some View {
        let time = clip.correctedStartedAt.formatted(date: .omitted, time: .standard)
        let totalSeconds = max(0, Int(clip.duration.rounded()))
        let duration = String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
        let details = duration + " · " + DriveVideoFileStore.formattedSize(clip.sizeBytes)
        return HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .foregroundStyle(Color.tougeCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.caption.weight(.black).monospacedDigit())
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if clip.width > 0, clip.height > 0 {
                Text("\(clip.width)×\(clip.height)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private var importButton: some View {
        Button {
            Task {
                let prepared = await model.importVideo(
                    sessionStartedAt: session.startedAt,
                    sessionEndedAt: session.endedAt
                )
                guard let prepared else { return }
                onImported(prepared)
                dismiss()
            }
        } label: {
            Label(localized("Pobierz i utwórz montaż"), systemImage: "arrow.down.to.line.compact")
                .font(.subheadline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
        }
        .buttonStyle(.borderedProminent)
        .tint(.tougeCyan)
        .disabled(model.isBusy)
    }

    private var diagnosticsCard: some View {
        DisclosureGroup(isExpanded: $showsDiagnostics) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label(localized("Diagnostyka połączenia"), systemImage: "stethoscope")
                .font(.caption.weight(.bold))
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}
