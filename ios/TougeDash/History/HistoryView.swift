import Charts
import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [DriveSession]
    @Query private var incidents: [DriveIncident]
    @Query private var videos: [DriveVideoRecording]
    let locationTracker: LocationTrackingService
    let cloudAccount: CloudAccountService
    let cloudSync: CloudSyncManager
    let videoRecorder: DriveVideoRecorder
    let videoOverlays: VideoOverlayTemplateStore
    let segmentSettings: DriveSegmentSettingsStore
    let activeSessionID: UUID?
    let canSplitActiveDrive: Bool
    let onSplitActiveDrive: () -> Bool
    let onShowDashboard: (() -> Void)?
    @State private var showingSplitConfirmation = false
    @State private var splitFeedback = 0
    @State private var pendingDeletion: HistoryDeletionCandidate?
    @State private var deletingItems: Set<HistoryDeletionKey> = []
    @State private var deletedItems: Set<HistoryDeletionKey> = []
    @State private var deletionToast: HistoryDeletionToast?
    @State private var deletionError: String?
    @State private var localArchiveBytes: Int64 = 0

    init(
        locationTracker: LocationTrackingService,
        cloudAccount: CloudAccountService,
        cloudSync: CloudSyncManager,
        videoRecorder: DriveVideoRecorder,
        videoOverlays: VideoOverlayTemplateStore,
        segmentSettings: DriveSegmentSettingsStore,
        activeSessionID: UUID?,
        canSplitActiveDrive: Bool,
        onSplitActiveDrive: @escaping () -> Bool,
        onShowDashboard: (() -> Void)?
    ) {
        var sessionDescriptor = FetchDescriptor<DriveSession>(
            sortBy: [SortDescriptor(\DriveSession.startedAt, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = HistoryPresentationPolicy.maximumVisibleSessions
        _sessions = Query(sessionDescriptor)

        var incidentDescriptor = FetchDescriptor<DriveIncident>(
            sortBy: [SortDescriptor(\DriveIncident.triggeredAt, order: .reverse)]
        )
        incidentDescriptor.fetchLimit = HistoryPresentationPolicy.maximumVisibleIncidents
        _incidents = Query(incidentDescriptor)

        var videoDescriptor = FetchDescriptor<DriveVideoRecording>(
            sortBy: [SortDescriptor(\DriveVideoRecording.startedAt, order: .reverse)]
        )
        videoDescriptor.fetchLimit = HistoryPresentationPolicy.maximumVisibleVideoRecords
        _videos = Query(videoDescriptor)

        self.locationTracker = locationTracker
        self.cloudAccount = cloudAccount
        self.cloudSync = cloudSync
        self.videoRecorder = videoRecorder
        self.videoOverlays = videoOverlays
        self.segmentSettings = segmentSettings
        self.activeSessionID = activeSessionID
        self.canSplitActiveDrive = canSplitActiveDrive
        self.onSplitActiveDrive = onSplitActiveDrive
        self.onShowDashboard = onShowDashboard
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        CloudSyncCard(account: cloudAccount, sync: cloudSync)
                        if canSplitActiveDrive {
                            ManualSessionSplitCard {
                                showingSplitConfirmation = true
                            }
                        }
                        DriveSegmentationCard(settings: segmentSettings)
                        LocationRecordingCard(locationTracker: locationTracker)
                        DriveVideoRecordingCard(recorder: videoRecorder)

                        if !incidents.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("RAPORTY INCYDENTÓW")
                                        .font(.system(size: 13, weight: .black))
                                        .tracking(1.4)
                                    Text("30 sekund przed · 60 sekund po zdarzeniu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(incidents.count.formatted())
                                    .font(.headline.monospacedDigit().weight(.black))
                                    .foregroundStyle(Color.tougeRed)
                            }
                            .padding(.top, 4)

                            ForEach(incidents.filter { !deletedItems.contains(.incident($0.id)) }) { incident in
                                let isDeleting = deletingItems.contains(.incident(incident.id))
                                SwipeToDeleteRow(isEnabled: !isDeleting) {
                                    pendingDeletion = .incident(incident)
                                } content: {
                                    NavigationLink {
                                        IncidentReportView(
                                            incident: incident,
                                            cloudAccount: cloudAccount,
                                            cloudSync: cloudSync
                                        )
                                    } label: {
                                        IncidentListRow(incident: incident, cloudSync: cloudSync)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isDeleting)
                                    .opacity(isDeleting ? 0.42 : 1)
                                    .overlay {
                                        if isDeleting { HistoryDeletingOverlay() }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            pendingDeletion = .incident(incident)
                                        } label: {
                                            Label(localized("Usuń raport"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        if sessions.isEmpty {
                            HistoryEmptyState()
                        } else {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("PRZEJAZDY")
                                        .font(.system(size: 13, weight: .black))
                                        .tracking(1.4)
                                    Text("Lokalne archiwum telemetrii")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(sessions.count)")
                                    .font(.headline.monospacedDigit().weight(.black))
                                    .foregroundStyle(Color.tougeCyan)
                            }
                            .padding(.top, 4)

                            ForEach(sessions.filter { !deletedItems.contains(.session($0.id)) }) { session in
                                let isDeleting = deletingItems.contains(.session(session.id))
                                SwipeToDeleteRow(isEnabled: session.id != activeSessionID && !isDeleting) {
                                    pendingDeletion = .session(session)
                                } content: {
                                    NavigationLink {
                                        DriveSessionDetailView(
                                            session: session,
                                            cloudAccount: cloudAccount,
                                            cloudSync: cloudSync,
                                            videoOverlays: videoOverlays
                                        )
                                    } label: {
                                        DriveSessionRow(
                                            session: session,
                                            recordings: videos.filter { $0.sessionID == session.id },
                                            cloudSync: cloudSync
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isDeleting)
                                    .opacity(isDeleting ? 0.42 : 1)
                                    .overlay {
                                        if isDeleting { HistoryDeletingOverlay() }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            pendingDeletion = .session(session)
                                        } label: {
                                            Label(localized("Usuń przejazd"), systemImage: "trash")
                                        }
                                        .disabled(session.id == activeSessionID)
                                    }
                                }
                            }

                            LocalArchiveStorageFooter(bytes: localArchiveBytes)
                        }

                        ProductCreditFooter()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 1_000)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }

                if let deletionToast {
                    HistoryDeletionToastView(message: deletionToast.message)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(20)
                }
            }
            .navigationTitle("Historia")
            .navigationBarTitleDisplayMode(.inline)
            .alert(localized("Podziel bieżący przejazd?"), isPresented: $showingSplitConfirmation) {
                Button(localized("Anuluj"), role: .cancel) {}
                Button(localized("Zapisz i rozpocznij nowy")) {
                    if onSplitActiveDrive() { splitFeedback += 1 }
                }
            } message: {
                Text(localized("Dotychczasowe dane pozostaną w pierwszym przejeździe. Bluetooth pozostanie połączony, a kolejne próbki trafią do nowego przejazdu. Aktywne nagranie i trwający pomiar zostaną rozdzielone w tym samym miejscu."))
            }
            .confirmationDialog(
                localized("Usunąć ten element?"),
                isPresented: deletionDialogBinding,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { candidate in
                if candidate.isStoredInCloud {
                    Button(localized("Usuń z iPhone’a i chmury"), role: .destructive) {
                        Task { await delete(candidate, includingCloud: true) }
                    }
                    Button(localized("Usuń tylko z iPhone’a"), role: .destructive) {
                        Task { await delete(candidate, includingCloud: false) }
                    }
                } else {
                    Button(localized("Usuń z iPhone’a"), role: .destructive) {
                        Task { await delete(candidate, includingCloud: false) }
                    }
                }
                Button(localized("Anuluj"), role: .cancel) {}
            } message: { candidate in
                Text(candidate.deletionMessage)
            }
            .alert(
                localized("Nie udało się usunąć danych"),
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .sensoryFeedback(.success, trigger: splitFeedback)
            .task(id: localStorageRevision) {
                localArchiveBytes = await Task.detached(priority: .utility) {
                    HistoryLocalStore.storageBytes()
                }.value
            }
            .task(id: deletionToast?.id) {
                guard let toastID = deletionToast?.id else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, deletionToast?.id == toastID else { return }
                withAnimation(.easeOut(duration: 0.2)) { deletionToast = nil }
            }
            .toolbar {
                if let onShowDashboard {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onShowDashboard) {
                            Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                        }
                    }
                }
            }
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var localStorageRevision: Int64 {
        let sessionRevision = sessions.reduce(Int64(sessions.count)) { partial, session in
            partial &+ Int64(session.sampleCount) &+ Int64(session.modifiedAt.timeIntervalSince1970)
        }
        let incidentRevision = incidents.reduce(Int64(incidents.count)) { partial, incident in
            partial &+ Int64(incident.encodedSamples.count) &+ Int64(incident.triggeredAt.timeIntervalSince1970)
        }
        return videos.reduce(sessionRevision &+ incidentRevision) { partial, video in
            partial &+ video.fileSizeBytes &+ Int64(video.createdAt.timeIntervalSince1970)
        }
    }

    @MainActor
    private func delete(_ candidate: HistoryDeletionCandidate, includingCloud: Bool) async {
        let key = candidate.key
        let successMessage = candidate.successMessage
        pendingDeletion = nil
        withAnimation(.easeOut(duration: 0.18)) {
            _ = deletingItems.insert(key)
        }

        do {
            if includingCloud {
                switch candidate {
                case .session(let session): try await cloudSync.deleteRemote(session: session)
                case .incident(let incident): try await cloudSync.deleteRemote(incident: incident)
                }
            }
            let worker = HistoryDeletionWorker(modelContainer: modelContext.container)
            switch key {
            case .session(let id): try await worker.deleteSession(id: id)
            case .incident(let id): try await worker.deleteIncident(id: id)
            }
            cloudSync.localHistoryDidChange()
            withAnimation(.easeOut(duration: 0.2)) {
                deletingItems.remove(key)
                deletedItems.insert(key)
                deletionToast = HistoryDeletionToast(message: successMessage)
            }
        } catch {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = deletingItems.remove(key)
            }
            deletionError = error.localizedDescription
        }
    }
}

private struct DriveSegmentationCard: View {
    @ObservedObject var settings: DriveSegmentSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeYellow.opacity(0.13))
                    Image(systemName: "rectangle.split.3x1.fill")
                        .foregroundStyle(Color.tougeYellow)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("DŁUGOŚĆ ODCINKA"))
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(localized("Automatyczne dzielenie przejazdu"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "repeat")
                    .foregroundStyle(Color.tougeYellow)
            }

            Picker(localized("Maksymalna długość przejazdu"), selection: $settings.length) {
                ForEach(DriveSegmentLength.allCases) { length in
                    Text(length.title).tag(length)
                }
            }
            .pickerStyle(.segmented)

            Text(localized("Po osiągnięciu limitu Touge Dash zapisze odcinek i bez rozłączania rozpocznie następny. Telemetria i film są cięte na tej samej osi czasu."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .cardSurface(accent: .tougeYellow)
    }
}

private enum HistoryDeletionCandidate {
    case session(DriveSession)
    case incident(DriveIncident)

    var isStoredInCloud: Bool {
        switch self {
        case .session(let session): session.remoteID != nil || session.syncState == .synced
        case .incident(let incident): incident.remoteID != nil || incident.syncState == .synced
        }
    }

    var key: HistoryDeletionKey {
        switch self {
        case .session(let session): .session(session.id)
        case .incident(let incident): .incident(incident.id)
        }
    }

    var successMessage: String {
        switch self {
        case .session(let session):
            String(
                format: localized("Usunięto: Przejazd · %@"),
                session.startedAt.formatted(date: .abbreviated, time: .shortened)
            )
        case .incident(let incident):
            String(
                format: localized("Usunięto: %@ · %@"),
                incident.kind.title,
                incident.triggeredAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }

    var deletionMessage: String {
        switch self {
        case .session:
            localized("Usunięcie przejazdu z iPhone’a skasuje także jego próbki, raporty, notatki i lokalne nagrania wideo.")
        case .incident:
            localized("Usunięcie raportu skasuje jego zapisane próbki i powiązane notatki.")
        }
    }
}

private enum HistoryDeletionKey: Hashable, Sendable {
    case session(UUID)
    case incident(UUID)
}

private struct HistoryDeletionToast: Identifiable {
    let id = UUID()
    let message: String
}

private struct HistoryDeletingOverlay: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text(localized("Usuwanie…"))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: Capsule())
    }
}

private struct HistoryDeletionToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
            Text(message)
                .font(.caption.weight(.bold))
                .lineLimit(2)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.tougeMint, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    private let actionWidth: CGFloat = 82
    let isEnabled: Bool
    let action: () -> Void
    let content: Content
    @State private var offset: CGFloat = 0
    @State private var isRevealed = false

    init(
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isEnabled {
                Button(role: .destructive) {
                    close()
                    action()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.headline)
                        Text(localized("Usuń"))
                            .font(.caption2.weight(.black))
                    }
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(Color.tougeRed, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .mask(alignment: .trailing) {
                    Rectangle()
                        .frame(width: max(0, -offset))
                }
                .allowsHitTesting(isRevealed)
                .zIndex(1)
            }

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .gesture(
                    HorizontalSwipeGesture(
                        onChanged: updateOffset,
                        onEnded: finishSwipe
                    )
                )
        }
        .clipped()
        .accessibilityAction(named: localized("Usuń")) {
            guard isEnabled else { return }
            action()
        }
    }

    private func updateOffset(_ translation: CGFloat) {
        guard isEnabled else { return }
        let startingOffset = isRevealed ? -actionWidth : 0
        offset = min(0, max(-actionWidth, startingOffset + translation))
    }

    private func finishSwipe(_ translation: CGFloat, velocity: CGFloat) {
        guard isEnabled else { return }
        let startingOffset = isRevealed ? -actionWidth : 0
        let projectedOffset = startingOffset + translation + velocity * 0.12
        isRevealed = projectedOffset < -actionWidth * 0.45
        withAnimation(.snappy(duration: 0.22)) {
            offset = isRevealed ? -actionWidth : 0
        }
    }

    private func close() {
        isRevealed = false
        withAnimation(.snappy(duration: 0.18)) { offset = 0 }
    }
}

private struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x ?? 0
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, context.converter.localVelocity?.x ?? 0)
        case .cancelled, .failed:
            onEnded(translation, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.15
        }
    }
}

private struct ManualSessionSplitCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeCyan.opacity(0.13))
                    Image(systemName: "scissors")
                        .foregroundStyle(Color.tougeCyan)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("BIEŻĄCY PRZEJAZD"))
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(localized("Zapis trwa · możesz rozpocząć nowy odcinek"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(Color.tougeMint)
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.tougeMint.opacity(0.7), radius: 5)
            }

            Text(localized("Zamknij bieżący zapis bez rozłączania EMULOGGERA. Następna próbka rozpocznie osobny przejazd."))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button(action: action) {
                Label(localized("Zapisz i rozpocznij nowy"), systemImage: "scissors")
                    .font(.caption.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black)
            .background(Color.tougeCyan, in: CutCornerPanel(cut: 8))
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct LocationRecordingCard: View {
    @ObservedObject var locationTracker: LocationTrackingService

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { locationTracker.isEnabled },
            set: { locationTracker.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeBlue.opacity(0.14))
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.tougeIce)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("ZAPIS TRASY")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(localized(locationTracker.isTracking ? "GPS aktywny · zapis działa w tle" : locationTracker.authorizationLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .tint(.tougeCyan)
            }

            Text("Po włączeniu każda próbka przejazdu może zawierać pozycję. Dane są przechowywane lokalnie, a przy aktywnym koncie także synchronizowane z Touge Dash Cloud.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error = locationTracker.lastError {
                Text(error)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.tougeOrange)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
    }
}

private struct HistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.tougeCyan)
            Text("Pierwszy wykres powstanie sam")
                .font(.headline.weight(.black))
            Text("Touge Dash rozpocznie przejazd po odebraniu danych z EMU i zapisze 10 próbek na sekundę.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct LocalArchiveStorageFooter: View {
    let bytes: Int64

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .foregroundStyle(Color.tougeCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("LOKALNE ARCHIWUM"))
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                Text(localized("Telemetria i filmy z przejazdów na tym urządzeniu"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DriveVideoFileStore.formattedSize(bytes))
                .font(.subheadline.monospacedDigit().weight(.black))
                .foregroundStyle(Color.tougeMint)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.025), in: CutCornerPanel(cut: 8))
        .overlay(CutCornerPanel(cut: 8).stroke(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

private struct DriveSessionRow: View {
    let session: DriveSession
    let recordings: [DriveVideoRecording]
    @ObservedObject var cloudSync: CloudSyncManager

    private var videoBytes: Int64 { recordings.reduce(0) { $0 + $1.fileSizeBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.customName ?? session.startedAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                    ))
                        .font(.headline.weight(.black))
                    if session.customName != nil {
                        Text(session.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(
                        format: localized("%@ · %@ próbek"),
                        formatDuration(session.duration),
                        session.sampleCount.formatted()
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.containsLocation {
                    Label("TRASA", systemImage: "location.fill")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(Color.tougeIce)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.tougeBlue.opacity(0.12), in: Capsule())
                }
                CloudSyncItemBadge(status: cloudSync.sessionStatus(for: session))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                SessionStat(title: "MAX BOOST", value: session.maxBoostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: .tougeCyan)
                SessionStat(title: "MAX SPEED", value: Int(session.maxSpeedKPH).formatted(), unit: "km/h", tint: .tougeIce)
                SessionStat(title: "OIL MAX", value: Int(session.maxOilTemperatureCelsius).formatted(), unit: "°C", tint: .tougeOrange)
                SessionStat(title: "COOLANT", value: Int(session.maxCoolantCelsius).formatted(), unit: "°C", tint: .tougeMint)
            }

            if !session.driveTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.driveTags) { DriveTagPill(tag: $0) }
                    }
                }
            }

            if session.distanceMeters > 0 {
                Label(
                    String(
                        format: localized("%@ km zapisanej trasy"),
                        (session.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1)))
                    ),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            }

            if !recordings.isEmpty {
                Label(
                    String(
                        format: localized("Nagrania: %@ · %@ lokalnie"),
                        recordings.count.formatted(),
                        DriveVideoFileStore.formattedSize(videoBytes)
                    ),
                    systemImage: "video.fill"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.tougeRed)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct SessionStat: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(unit)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let session: DriveSession
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var videoOverlays: VideoOverlayTemplateStore
    @Query(sort: \DriveIncident.triggeredAt) private var allIncidents: [DriveIncident]
    @Query(sort: \TimelineAnnotation.timestamp) private var allAnnotations: [TimelineAnnotation]
    @Query(sort: \DriveVideoRecording.startedAt) private var allVideos: [DriveVideoRecording]
    @Query(sort: \AccelerationAttempt.startedAt) private var allAccelerationAttempts: [AccelerationAttempt]
    @State private var selectedTime: Date?
    @State private var cachedSamples: [TelemetryHistorySample] = []
    @State private var chartSamples: [TelemetryHistorySample] = []
    @State private var locatedSamples: [TelemetryHistorySample] = []
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeHasMovement = false
    @State private var showingNoteComposer = false
    @State private var showingMetadataEditor = false
    @State private var showingDriveShare = false
    private let chartColumns = [GridItem(.adaptive(minimum: 460), spacing: 14)]

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return cachedSamples.last }
        return cachedSamples.nearest(to: selectedTime)
    }

    private var incidents: [DriveIncident] {
        allIncidents.filter { $0.sessionID == session.id }
    }

    private var notes: [TimelineAnnotation] {
        allAnnotations.filter { $0.sessionID == session.id && $0.incidentID == nil }
    }

    private var recordings: [DriveVideoRecording] {
        allVideos.filter { $0.sessionID == session.id }
    }

    private var accelerationAttempts: [AccelerationAttempt] {
        allAccelerationAttempts.filter { $0.sessionID == session.id }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let selectedTime,
              let sample = locatedSamples.nearest(to: selectedTime),
              let latitude = sample.latitude,
              let longitude = sample.longitude else { return routeCoordinates.last }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SessionDetailHeader(session: session)

                    HStack(spacing: 10) {
                        Button { showingMetadataEditor = true } label: {
                            Label("Edytuj nazwę i tagi", systemImage: "tag.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.tougeCyan)

                        Button { showingDriveShare = true } label: {
                            Label("Udostępnij link", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.tougeMint)
                    }

                    if !session.driveTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(session.driveTags) { DriveTagPill(tag: $0) }
                            }
                        }
                    }

                    CloudSyncItemCard(
                        itemName: "PRZEJAZD",
                        sampleCount: session.sampleCount,
                        status: cloudSync.sessionStatus(for: session),
                        onRetry: { Task { await cloudSync.retrySynchronization() } }
                    )

                    DriveVideoHistorySection(
                        session: session,
                        recordings: recordings,
                        samples: cachedSamples,
                        selectedTime: $selectedTime,
                        overlayStore: videoOverlays,
                        onDelete: deleteVideo
                    )

                    if let selectedSample {
                        SelectedTelemetryStrip(sample: selectedSample, startedAt: session.startedAt)

                        Button {
                            showingNoteComposer = true
                        } label: {
                            Label("Dodaj notatkę do wybranego momentu", systemImage: "note.text.badge.plus")
                                .font(.subheadline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(.tougeCyan)
                    }

                    if !incidents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INCYDENTY W TYM PRZEJEŹDZIE")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.1)
                            ForEach(incidents) { incident in
                                NavigationLink {
                                    IncidentReportView(
                                        incident: incident,
                                        cloudAccount: cloudAccount,
                                        cloudSync: cloudSync
                                    )
                                } label: {
                                    IncidentListRow(incident: incident, cloudSync: cloudSync)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !accelerationAttempts.isEmpty {
                        AccelerationAttemptsCard(attempts: accelerationAttempts, selectedTime: $selectedTime)
                    }

                    LazyVGrid(columns: chartColumns, spacing: 14) {
                        HistoryChartCard(
                            title: "TEMPERATURY",
                            subtitle: "Olej i płyn chłodniczy",
                            unit: "°C",
                            startedAt: session.startedAt,
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [
                                HistoryChartSeries(name: "Olej", color: .tougeOrange, value: { $0.oilTemperatureCelsius }),
                                HistoryChartSeries(name: "Płyn", color: .tougeIce, value: { $0.coolantCelsius })
                            ],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "EGT",
                            subtitle: "Temperatura spalin",
                            unit: "°C",
                            startedAt: session.startedAt,
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [
                                HistoryChartSeries(name: "EGT 1", color: .tougeOrange, value: { $0.egt1Celsius }),
                                HistoryChartSeries(name: "EGT 2", color: .tougeRed, value: { $0.egt2Celsius })
                            ],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "CIŚNIENIA",
                            subtitle: "Boost i ciśnienie oleju",
                            unit: "bar",
                            startedAt: session.startedAt,
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [
                                HistoryChartSeries(name: "Boost", color: .tougeCyan, value: { $0.boostBar }),
                                HistoryChartSeries(name: "Olej", color: .tougeMint, value: { $0.oilPressureBar })
                            ],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "PRĘDKOŚĆ",
                            subtitle: "Prędkość pojazdu",
                            unit: "km/h",
                            startedAt: session.startedAt,
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [HistoryChartSeries(name: "Prędkość", color: .tougeIce, value: { $0.speedKPH })],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "OBROTY SILNIKA",
                            subtitle: "RPM w czasie",
                            unit: "rpm",
                            startedAt: session.startedAt,
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [HistoryChartSeries(name: "RPM", color: .tougeYellow, value: { $0.rpm })],
                            selectedTime: $selectedTime
                        )
                    }

                    if session.containsLocation {
                        SessionRouteMap(
                            coordinates: routeCoordinates,
                            selectedCoordinate: selectedCoordinate,
                            hasMovement: routeHasMovement
                        )
                    }

                    IncidentNotesCard(notes: notes)

                    ProductCreditFooter()
                        .padding(.top, 8)
                }
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(session.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
        ))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMetadataEditor) {
            DriveMetadataEditor(session: session, cloudAccount: cloudAccount, cloudSync: cloudSync)
        }
        .sheet(isPresented: $showingDriveShare) {
            DriveShareSheet(session: session, samples: cachedSamples, cloudAccount: cloudAccount, cloudSync: cloudSync)
        }
        .task {
            let sessionID = session.id
            let descriptor = FetchDescriptor<TelemetryHistorySample>(
                predicate: #Predicate { sample in
                    sample.session?.id == sessionID && sample.chartEligible == true
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let previewSamples = (try? modelContext.fetch(descriptor)) ?? []
            // Records created by versions predating the preview flag use the
            // old relationship fallback once. New 10 Hz drives stay lightweight.
            let sorted = previewSamples.isEmpty
                ? session.samples.sorted { $0.timestamp < $1.timestamp }.downsampled(maxPoints: 7_200)
                : previewSamples.downsampled(maxPoints: 7_200)
            cachedSamples = sorted
            chartSamples = sorted.downsampled(maxPoints: 300)
            locatedSamples = sorted.filter { $0.latitude != nil && $0.longitude != nil }
            routeCoordinates = locatedSamples.downsampled(maxPoints: 2_000).compactMap { sample in
                guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            routeHasMovement = Set(routeCoordinates.map {
                "\($0.latitude.formatted(.number.precision(.fractionLength(5)))):\($0.longitude.formatted(.number.precision(.fractionLength(5))))"
            }).count > 1
            if selectedTime == nil {
                selectedTime = sorted.last?.timestamp
            }
        }
        .sheet(isPresented: $showingNoteComposer) {
            if let selectedSample {
                TimelineNoteComposer(
                    vehicleID: session.vehicleID,
                    sessionID: session.id,
                    incidentID: nil,
                    timestamp: selectedSample.timestamp,
                    cloudSync: cloudSync
                )
            }
        }
    }

    private func deleteVideo(_ recording: DriveVideoRecording) {
        try? DriveVideoFileStore.delete(recording)
        modelContext.delete(recording)
        try? modelContext.save()
    }
}

private struct SessionDetailHeader: View {
    let session: DriveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DRIVE SESSION")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(Color.tougeCyan)
                    Text(session.customName ?? session.startedAt.formatted(
                        Date.FormatStyle(date: .complete, time: .shortened)
                    ))
                        .font(.title3.weight(.black))
                    if session.customName != nil {
                        Text(session.startedAt.formatted(Date.FormatStyle(date: .complete, time: .shortened)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.tougeCyan)
            }

            HStack(spacing: 10) {
                HeaderSummary(title: "CZAS", value: formatDuration(session.duration), tint: .white)
                HeaderSummary(title: "DYSTANS", value: session.distanceMeters > 0 ? (session.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km" : "—", tint: .tougeIce)
                HeaderSummary(title: "MAX BOOST", value: session.maxBoostBar.formatted(.number.precision(.fractionLength(2))) + " bar", tint: .tougeCyan)
                HeaderSummary(title: "MAX RPM", value: Int(session.maxRPM).formatted(), tint: .tougeYellow)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct HeaderSummary: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveTagPill: View {
    let tag: CloudDriveTag

    var body: some View {
        let tint = Color.driveTag(hex: tag.color)
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(tag.name)
                .font(.system(size: 9, weight: .black))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.35)))
    }
}

private struct DriveMetadataEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DriveSession
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @State private var name: String
    @State private var tags: [CloudDriveTag] = []
    @State private var selectedIDs: Set<UUID>
    @State private var newTagName = ""
    @State private var newTagColor = "#18D7E3"
    @State private var working = false
    @State private var error: String?
    private let palette = ["#18D7E3", "#45E6A8", "#FF9D44", "#FF5C58", "#A879FF", "#F5D547"]

    init(session: DriveSession, cloudAccount: CloudAccountService, cloudSync: CloudSyncManager) {
        self.session = session
        self.cloudAccount = cloudAccount
        self.cloudSync = cloudSync
        _name = State(initialValue: session.customName ?? "")
        _selectedIDs = State(initialValue: Set(session.driveTags.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("np. Próba boostu po strojeniu"), text: $name)
                        .textInputAutocapitalization(.sentences)
                        .onChange(of: name) { _, value in name = String(value.prefix(120)) }
                    Text(localized("Pusta nazwa przywróci automatyczną datę i godzinę."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: { Text(localized("WŁASNA NAZWA")) }

                Section {
                    if tags.isEmpty {
                        Text(cloudAccount.isAuthenticated
                             ? localized("Nie masz jeszcze żadnych tagów.")
                             : localized("Zaloguj się, aby zarządzać tagami."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tags) { tag in
                        Button {
                            if selectedIDs.contains(tag.id) { selectedIDs.remove(tag.id) }
                            else { selectedIDs.insert(tag.id) }
                        } label: {
                            HStack {
                                DriveTagPill(tag: tag)
                                Spacer()
                                Image(systemName: selectedIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(tag.id) ? Color.tougeMint : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text(localized("TAGI PRZEJAZDU")) }

                if cloudAccount.isAuthenticated {
                    Section {
                        TextField(localized("Nazwa tagu"), text: $newTagName)
                            .onChange(of: newTagName) { _, value in newTagName = String(value.prefix(40)) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(palette, id: \.self) { hex in
                                    Circle()
                                        .fill(Color.driveTag(hex: hex))
                                        .frame(width: newTagColor == hex ? 36 : 30, height: newTagColor == hex ? 36 : 30)
                                        .overlay(Circle().stroke(.white, lineWidth: newTagColor == hex ? 2 : 0))
                                        .onTapGesture { newTagColor = hex }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        Button(localized("Utwórz i przypisz")) { createTag() }
                            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                    } header: { Text(localized("NOWY TAG")) }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Color.tougeRed) }
                }
            }
            .navigationTitle(localized("Nazwa i tagi przejazdu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("Anuluj")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? localized("Zapisywanie…") : localized("Zapisz")) { save() }
                        .disabled(working)
                }
            }
            .task {
                guard cloudAccount.isAuthenticated else {
                    tags = session.driveTags
                    return
                }
                do { tags = try await cloudSync.driveTags() }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func createTag() {
        working = true
        error = nil
        Task {
            do {
                let tag = try await cloudSync.createDriveTag(name: newTagName, color: newTagColor)
                tags = (tags + [tag]).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                selectedIDs.insert(tag.id)
                newTagName = ""
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }

    private func save() {
        working = true
        error = nil
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let assigned = tags.filter { selectedIDs.contains($0.id) }
        session.customName = normalizedName.isEmpty ? nil : String(normalizedName.prefix(120))
        session.driveTags = assigned
        session.metadataDirty = true
        if session.syncState == .synced { session.syncState = .changedAfterSync }
        do { try modelContext.save() }
        catch {
            self.error = error.localizedDescription
            working = false
            return
        }
        guard cloudAccount.isAuthenticated else {
            working = false
            dismiss()
            return
        }
        Task {
            do {
                try await cloudSync.updateDriveMetadata(
                    sessionID: session.id,
                    vehicleID: session.vehicleID,
                    customName: session.customName,
                    tags: assigned
                )
                dismiss()
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

private struct DriveShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: DriveSession
    let samples: [TelemetryHistorySample]
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @State private var sharesFragment = false
    @State private var startSeconds = 0.0
    @State private var endSeconds: Double
    @State private var unit = "DAYS"
    @State private var amount = 7
    @State private var working = false
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var links: [CloudDriveShareLink] = []

    init(session: DriveSession, samples: [TelemetryHistorySample], cloudAccount: CloudAccountService, cloudSync: CloudSyncManager) {
        self.session = session
        self.samples = samples
        self.cloudAccount = cloudAccount
        self.cloudSync = cloudSync
        let prefix = "TougeDash.driveShare.\(session.id.uuidString)"
        let defaults = UserDefaults.standard
        _sharesFragment = State(initialValue: defaults.bool(forKey: prefix + ".fragment"))
        _startSeconds = State(initialValue: min(max(0, defaults.double(forKey: prefix + ".start")), max(0, session.duration - 1)))
        let storedEnd = defaults.double(forKey: prefix + ".end")
        _endSeconds = State(initialValue: storedEnd > 0 ? min(max(1, storedEnd), max(1, session.duration)) : max(1, session.duration))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(localized("Zakres"), selection: $sharesFragment) {
                        Text(localized("Cały przejazd")).tag(false)
                        Text(localized("Wybrany fragment")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    if sharesFragment {
                        Text(localized("Wybierz początek i koniec tak jak przy przycinaniu filmu."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatDuration(startSeconds))  →  \(formatDuration(endSeconds))")
                            .font(.headline.monospacedDigit().weight(.black))
                            .foregroundStyle(Color.tougeMint)
                        LabeledContent(localized("Początek")) {
                            Slider(value: Binding(get: { startSeconds }, set: { startSeconds = min($0, endSeconds - 1) }), in: 0...max(1, session.duration))
                        }
                        LabeledContent(localized("Koniec")) {
                            Slider(value: Binding(get: { endSeconds }, set: { endSeconds = max($0, startSeconds + 1) }), in: 0...max(1, session.duration))
                        }
                    }
                    if !previewSamples.isEmpty {
                        HStack(spacing: 8) {
                            HeaderSummary(title: "PRÓBKI", value: previewSamples.count.formatted(), tint: .tougeCyan)
                            HeaderSummary(title: "MAX BOOST", value: (previewSamples.map(\.boostBar).max() ?? 0).formatted(.number.precision(.fractionLength(2))) + " bar", tint: .tougeMint)
                            HeaderSummary(title: "MAX SPEED", value: Int(previewSamples.map(\.speedKPH).max() ?? 0).formatted() + " km/h", tint: .tougeOrange)
                        }
                        Text(String(format: localized("Podgląd obejmuje %@ punktów GPS."), previewSamples.filter { $0.latitude != nil }.count.formatted()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: { Text(localized("UDOSTĘPNIANY ZAKRES")) }

                Section {
                    Picker(localized("Ważność"), selection: $unit) {
                        Text(localized("Godziny")).tag("HOURS")
                        Text(localized("Dni")).tag("DAYS")
                        Text(localized("Bezterminowo")).tag("FOREVER")
                    }
                    .pickerStyle(.segmented)
                    if unit != "FOREVER" {
                        Stepper(value: $amount, in: 1...(unit == "HOURS" ? 168 : 365)) {
                            Text("\(amount) \(unit == "HOURS" ? localized("godz.") : localized("dni"))")
                        }
                    }
                } header: { Text(localized("WAŻNOŚĆ LINKU")) }

                if let shareURL {
                    Section {
                        Text(shareURL.absoluteString)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        ShareLink(item: shareURL) {
                            Label(localized("Wyślij link"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.tougeMint)
                    } header: { Text(localized("LINK JEST GOTOWY")) }
                }

                if !links.isEmpty {
                    Section {
                        ForEach(links) { link in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(link.expiresAt?.formatted(date: .abbreviated, time: .shortened) ?? localized("Bezterminowo"))
                                        .font(.subheadline.weight(.bold))
                                    if let range = link.range {
                                        Text("\(formatDuration(Double(range.startOffsetMillis) / 1_000)) → \(formatDuration(Double(range.endOffsetMillis) / 1_000))")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Color.tougeMint)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) { revoke(link) } label: {
                                    Image(systemName: "link.badge.minus")
                                }
                                .disabled(working)
                            }
                        }
                    } header: { Text(localized("AKTYWNE LINKI")) }
                }

                if !cloudAccount.isAuthenticated {
                    Section { Text(localized("Zaloguj się do Touge Dash Cloud, aby utworzyć link.")).foregroundStyle(Color.tougeOrange) }
                }
                if let error { Section { Text(error).foregroundStyle(Color.tougeRed) } }
            }
            .navigationTitle(localized("Udostępnij przejazd"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("Zamknij")) { dismiss() } }
                if shareURL == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(working ? localized("Tworzenie linku…") : localized("Utwórz link")) { createLink() }
                            .disabled(working || !cloudAccount.isAuthenticated)
                    }
                }
            }
            .task { await loadLinks() }
            .onChange(of: sharesFragment) { _, _ in persistRange() }
            .onChange(of: startSeconds) { _, _ in persistRange() }
            .onChange(of: endSeconds) { _, _ in persistRange() }
        }
    }

    private var previewSamples: [TelemetryHistorySample] {
        guard sharesFragment else { return samples }
        let start = session.startedAt.addingTimeInterval(startSeconds)
        let end = session.startedAt.addingTimeInterval(endSeconds)
        return samples.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private func persistRange() {
        let prefix = "TougeDash.driveShare.\(session.id.uuidString)"
        UserDefaults.standard.set(sharesFragment, forKey: prefix + ".fragment")
        UserDefaults.standard.set(startSeconds, forKey: prefix + ".start")
        UserDefaults.standard.set(endSeconds, forKey: prefix + ".end")
    }

    private func createLink() {
        working = true
        error = nil
        Task {
            do {
                let range = sharesFragment ? DriveShareSelection.normalized(
                    driveDurationMillis: Int64((session.duration * 1_000).rounded()),
                    startOffsetMillis: Int64((startSeconds * 1_000).rounded()),
                    endOffsetMillis: Int64((endSeconds * 1_000).rounded())
                ) : nil
                shareURL = try await cloudSync.createDriveShare(
                    sessionID: session.id,
                    vehicleID: session.vehicleID,
                    unit: unit,
                    amount: unit == "FOREVER" ? nil : amount,
                    startOffsetMillis: range?.startOffsetMillis,
                    endOffsetMillis: range?.endOffsetMillis
                )
                await loadLinks()
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }

    private func loadLinks() async {
        guard cloudAccount.isAuthenticated else { return }
        do { links = try await cloudSync.driveShares(sessionID: session.id, vehicleID: session.vehicleID) }
        catch { self.error = error.localizedDescription }
    }

    private func revoke(_ link: CloudDriveShareLink) {
        working = true
        error = nil
        Task {
            do {
                try await cloudSync.revokeDriveShare(
                    sessionID: session.id,
                    vehicleID: session.vehicleID,
                    shareID: link.id
                )
                links.removeAll { $0.id == link.id }
            } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

private extension Color {
    static func driveTag(hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        return Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

private struct SelectedTelemetryStrip: View {
    let sample: TelemetryHistorySample
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WYBRANY MOMENT")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+" + formatDuration(sample.timestamp.timeIntervalSince(startedAt)))
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(Color.tougeCyan)
            }

            HStack(spacing: 7) {
                MomentValue(title: "SPEED", value: Int(sample.speedKPH).formatted(), unit: "km/h", tint: .tougeIce)
                MomentValue(title: "RPM", value: Int(sample.rpm).formatted(), unit: "rpm", tint: .tougeYellow)
                MomentValue(title: "BOOST", value: sample.boostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: .tougeCyan)
                MomentValue(title: "OIL", value: Int(sample.oilTemperatureCelsius).formatted(), unit: "°C", tint: .tougeOrange)
                MomentValue(title: "COOLANT", value: Int(sample.coolantCelsius).formatted(), unit: "°C", tint: .tougeMint)
                MomentValue(title: "AFR", value: sample.afr.formatted(.number.precision(.fractionLength(1))), unit: "", tint: .white)
            }
        }
        .padding(14)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct MomentValue: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryChartSeries: Identifiable {
    let name: String
    let color: Color
    let value: (TelemetryHistorySample) -> Double

    var id: String { name }
}

private struct HistoryChartCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let startedAt: Date
    let samples: [TelemetryHistorySample]
    let attempts: [AccelerationAttempt]
    let series: [HistoryChartSeries]
    @Binding var selectedTime: Date?

    private var yDomain: ClosedRange<Double> {
        let values = series.flatMap { item in samples.map(item.value) }.filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = max(0.1, maximum - minimum)
        let padding = max(unit == "°C" ? 3 : 0.1, span * 0.12)
        return (minimum - padding)...(maximum + padding)
    }

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return samples.last }
        return samples.nearest(to: selectedTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(title))
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(localized(subtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(series) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(localized(item.name))
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                ForEach(attempts) { attempt in
                    RectangleMark(
                        xStart: .value(localized("Początek pomiaru"), attempt.startedAt),
                        xEnd: .value(localized("Koniec pomiaru"), attempt.endedAt),
                        yStart: .value(localized("Minimum"), yDomain.lowerBound),
                        yEnd: .value(localized("Maksimum"), yDomain.upperBound)
                    )
                    .foregroundStyle(accelerationColor(attempt.type).opacity(0.12))
                }
                ForEach(series) { item in
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value(localized("Czas"), sample.timestamp),
                            y: .value(item.name, item.value(sample)),
                            series: .value(localized("Seria"), localized(item.name))
                        )
                        .foregroundStyle(item.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    }
                }

                if let selectedTime {
                    RuleMark(x: .value(localized("Wybrany czas"), selectedTime))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(preset: .inset, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.055))
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.055))
                    AxisValueLabel().foregroundStyle(Color.secondary)
                }
            }
            .chartYAxisLabel(unit, position: .top, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                    selectTimestamp(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    selectTimestamp(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
            .frame(height: 210)

            if let selectedSample {
                HStack(spacing: 12) {
                    chartMoment(
                        title: localized("CZAS"),
                        value: "+" + formatDuration(selectedSample.timestamp.timeIntervalSince(startedAt)),
                        color: .tougeCyan
                    )
                    ForEach(series) { item in
                        chartMoment(
                            title: localized(item.name),
                            value: formatted(item.value(selectedSample)) + " " + unit,
                            color: item.color
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(16)
        .cardSurface(accent: series.first?.color ?? .tougeCyan)
    }

    private func selectTimestamp(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let xPosition = location.x - frame.origin.x
        guard xPosition >= 0,
              xPosition <= frame.width,
              let timestamp: Date = proxy.value(atX: xPosition) else { return }
        selectedTime = timestamp
    }

    private func formatted(_ value: Double) -> String {
        switch unit {
        case "bar": return value.formatted(.number.precision(.fractionLength(2)))
        case "°C", "km/h", "rpm": return Int(value.rounded()).formatted()
        default: return value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private func chartMoment(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccelerationAttemptsCard: View {
    let attempts: [AccelerationAttempt]
    @Binding var selectedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("POMIARY PRZYSPIESZENIA"), systemImage: "stopwatch.fill")
                    .font(.system(size: 11, weight: .black)).tracking(1)
                Spacer()
                Text(localized("Dotknij, aby przejść na oś czasu"))
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            ForEach(AccelerationType.allCases) { type in
                let values = attempts.filter { $0.type == type }
                if let best = values.min(by: { $0.durationMillis < $1.durationMillis }) {
                    attemptRow(type: type, attempts: values, best: best)
                }
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }

    private func attemptRow(
        type: AccelerationType,
        attempts: [AccelerationAttempt],
        best: AccelerationAttempt
    ) -> some View {
        let color = accelerationColor(type)
        let duration = (Double(best.durationMillis) / 1_000)
            .formatted(.number.precision(.fractionLength(2))) + " s"
        let orderedAttempts = attempts.sorted { $0.startedAt < $1.startedAt }

        return VStack(alignment: .leading, spacing: 8) {
            Button { selectedTime = best.startedAt } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(type.label) km/h")
                            .font(.headline.weight(.black))
                            .foregroundStyle(color)
                        Text("\(attempts.count) \(localized("prób")) · \(localized("najlepszy czas"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(duration)
                        .font(.title3.monospacedDigit().weight(.black))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(orderedAttempts.enumerated()), id: \.element.id) { index, attempt in
                        Button { selectedTime = attempt.startedAt } label: {
                            Text("#\(index + 1)  \((Double(attempt.durationMillis) / 1_000).formatted(.number.precision(.fractionLength(2)))) s")
                                .font(.caption2.monospacedDigit().weight(.black))
                                .foregroundStyle(attempt.id == best.id ? Color.black : Color.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(attempt.id == best.id ? color : color.opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.08), in: CutCornerPanel(cut: 8))
    }
}

private func accelerationColor(_ type: AccelerationType) -> Color {
    switch type {
    case .zeroTo100: .tougeMint
    case .hundredTo200: .tougeCyan
    case .twoHundredTo250: .tougeOrange
    }
}

private struct SessionRouteMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let selectedCoordinate: CLLocationCoordinate2D?
    let hasMovement: Bool
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRASA")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(localized(hasMovement ? "Pozycja jest zsynchronizowana z kursorem wykresów" : "Zapisano pozycję postoju · trasa pojawi się po ruszeniu"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(coordinates.count)", systemImage: "map.fill")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color.tougeIce)
            }

            Map(position: $cameraPosition) {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.tougeCyan, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let selectedCoordinate {
                    Annotation("Wybrany moment", coordinate: selectedCoordinate) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.72)).frame(width: 28, height: 28)
                            Circle().fill(Color.tougeRed).frame(width: 12, height: 12)
                        }
                        .shadow(color: Color.tougeRed.opacity(0.7), radius: 6)
                    }
                }
            }
            .mapStyle(.standard)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onAppear(perform: updateCamera)
            .onChange(of: coordinates.count) { _, _ in updateCamera() }
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
    }

    private func updateCamera() {
        guard let first = coordinates.first else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minimumLatitude = latitudes.min(), let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(), let maximumLongitude = longitudes.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let latitudeDelta = max(0.004, (maximumLatitude - minimumLatitude) * 1.35)
        let longitudeDelta = max(0.004, (maximumLongitude - minimumLongitude) * 1.35)
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinates.count == 1 ? first : center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }
}

private extension Array where Element == TelemetryHistorySample {
    func downsampled(maxPoints: Int) -> [TelemetryHistorySample] {
        guard count > maxPoints, maxPoints > 2 else { return self }
        let stride = Double(count - 1) / Double(maxPoints - 1)
        var result: [TelemetryHistorySample] = []
        result.reserveCapacity(maxPoints)
        for index in 0..<maxPoints {
            result.append(self[Swift.min(count - 1, Int((Double(index) * stride).rounded()))])
        }
        return result
    }

    func nearest(to timestamp: Date) -> TelemetryHistorySample? {
        guard !isEmpty else { return nil }
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if self[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower == 0 { return self[0] }
        if lower == count { return self[count - 1] }
        let before = self[lower - 1]
        let after = self[lower]
        return abs(before.timestamp.timeIntervalSince(timestamp)) <= abs(after.timestamp.timeIntervalSince(timestamp))
            ? before
            : after
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
