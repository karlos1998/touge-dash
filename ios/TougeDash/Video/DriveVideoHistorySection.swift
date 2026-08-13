import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI

private enum GalleryVideoImportStage: Equatable {
    case retrieving(Double?)
    case inspecting
    case copying(Double)
    case saving

    var step: Int {
        switch self {
        case .retrieving: 1
        case .inspecting: 2
        case .copying: 3
        case .saving: 4
        }
    }

    var title: String {
        switch self {
        case .retrieving: localized("Pobieranie filmu ze Zdjęć…")
        case .inspecting: localized("Analizowanie filmu…")
        case .copying: localized("Tworzenie lokalnej kopii roboczej…")
        case .saving: localized("Zapisywanie projektu…")
        }
    }

    var systemImage: String {
        switch self {
        case .retrieving: "icloud.and.arrow.down.fill"
        case .inspecting: "waveform.badge.magnifyingglass"
        case .copying: "internaldrive.fill"
        case .saving: "checkmark.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .retrieving:
            localized("Jeśli film znajduje się w iCloud, czas zależy od połączenia z internetem.")
        case .inspecting:
            localized("Odczytywanie czasu, obrazu i dźwięku.")
        case .copying:
            localized("Film jest kopiowany do lokalnej przestrzeni Touge Dash.")
        case .saving:
            localized("Przygotowywanie projektu do edycji.")
        }
    }

    var fraction: Double? {
        switch self {
        case .retrieving(let fraction): fraction
        case .copying(let fraction): fraction
        case .inspecting, .saving: nil
        }
    }
}

struct DriveVideoHistorySection: View {
    @Environment(\.modelContext) private var modelContext
    let session: DriveSession
    let recordings: [DriveVideoRecording]
    let samples: [TelemetryHistorySample]
    @Binding var selectedTime: Date?
    @ObservedObject var overlayStore: VideoOverlayTemplateStore
    let onDelete: (DriveVideoRecording) -> Void

    @State private var selectedRecordingID: UUID?
    @State private var showsOverlayPreview = true
    @State private var showingOverlayManager = false
    @State private var exportRecording: DriveVideoRecording?
    @State private var showingDeleteConfirmation = false
    @State private var recordingPendingDeletion: DriveVideoRecording?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingVideo = false
    @State private var importStage: GalleryVideoImportStage = .retrieving(nil)
    @State private var importError: String?

    private var capturedRecordings: [DriveVideoRecording] {
        recordings
            .filter { $0.sourceKind == .camera }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var externalProjects: [DriveVideoRecording] {
        recordings
            .filter { $0.sourceKind == .photoLibrary }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var selectedRecording: DriveVideoRecording? {
        let requestedID = selectedRecordingID ?? capturedRecordings.first?.id
        return capturedRecordings.first { $0.id == requestedID } ?? capturedRecordings.first
    }

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return samples.first }
        return samples.videoNearest(to: selectedTime)
    }

    private var selectedOverlay: VideoOverlayTemplate {
        overlayStore.template(id: selectedRecording?.preferredOverlayTemplateID)
    }

    var body: some View {
        VStack(spacing: 14) {
            capturedVideosSection
            externalProjectsSection
        }
            .onAppear {
                if selectedRecordingID == nil {
                    selectedRecordingID = capturedRecordings.first?.id
                }
            }
            .onChange(of: capturedRecordings.map(\.id)) { _, ids in
                if let selectedRecordingID, ids.contains(selectedRecordingID) { return }
                self.selectedRecordingID = capturedRecordings.first?.id
            }
            .sheet(isPresented: $showingOverlayManager) {
                VideoOverlayTemplateManagerView(store: overlayStore)
            }
            .sheet(item: $exportRecording) { recording in
                DriveVideoExportSheet(
                    session: session,
                    recording: recording,
                    samples: samples,
                    sample: selectedSample,
                    overlayStore: overlayStore
                )
            }
            .alert(localized("Nie udało się dodać filmu"), isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button(localized("OK"), role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await importVideo(from: item) }
            }
            .confirmationDialog(deletionTitle, isPresented: $showingDeleteConfirmation) {
                if let recording = recordingPendingDeletion {
                    Button(deletionActionTitle, role: .destructive) {
                        onDelete(recording)
                        recordingPendingDeletion = nil
                    }
                }
                Button(localized("Anuluj"), role: .cancel) { recordingPendingDeletion = nil }
            } message: {
                Text(deletionMessage)
            }
    }

    private var capturedVideosSection: some View {
        sectionPanel(accent: .tougeCyan) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(localized("NAGRANIA Z APLIKACJI"), systemImage: "video.fill")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Color.tougeCyan)
                    Text(localized("Kamera Touge Dash · automatyczna synchronizacja z przejazdem"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if capturedRecordings.count > 1 {
                    Menu {
                        ForEach(Array(capturedRecordings.enumerated()), id: \.element.id) { index, recording in
                            Button {
                                selectedRecordingID = recording.id
                                selectedTime = recording.startedAt
                            } label: {
                                Label(
                                    clipTitle(recording, at: index),
                                    systemImage: recording.id == selectedRecording?.id ? "checkmark" : "video"
                                )
                            }
                        }
                    } label: {
                        Label(
                            String(format: localized("Klipy: %d"), capturedRecordings.count),
                            systemImage: "rectangle.stack.fill"
                        )
                        .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.tougeCyan)
                }
            }

            if let recording = selectedRecording {
                DriveVideoSynchronizedPlayer(
                    session: session,
                    recording: recording,
                    selectedTime: $selectedTime,
                    overlay: showsOverlayPreview ? selectedOverlay : nil,
                    selectedSample: selectedSample,
                    samples: samples
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                metadata(for: recording)

                HStack(spacing: 9) {
                    Toggle(isOn: $showsOverlayPreview) {
                        Label(localized("Podgląd HUD"), systemImage: "rectangle.inset.filled.and.person.filled")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(.tougeCyan)

                    Menu {
                        ForEach(overlayStore.templates) { template in
                            Button {
                                selectOverlay(template, for: recording)
                            } label: {
                                Label(
                                    template.name,
                                    systemImage: template.id == selectedOverlay.id ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                        Divider()
                        Button {
                            showingOverlayManager = true
                        } label: {
                            Label(localized("Edytuj szablony nakładek"), systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Label(selectedOverlay.name, systemImage: "square.3.layers.3d")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Menu {
                        Button {
                            exportRecording = recording
                        } label: {
                            Label(localized("Eksportuj do Zdjęć"), systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            recordingPendingDeletion = recording
                            showingDeleteConfirmation = true
                        } label: {
                            Label(localized("Usuń lokalny film"), systemImage: "trash")
                        }
                    } label: {
                        Label(localized("Film"), systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.tougeCyan)
                }
                .font(.caption.weight(.bold))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("Brak nagrania z kamery Touge Dash"))
                            .font(.subheadline.weight(.bold))
                        Text(localized("Ten przejazd zachował telemetrię, ale nagrywanie w aplikacji nie było aktywne."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var externalProjectsSection: some View {
        sectionPanel(accent: .tougeMint) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(localized("MONTAŻ Z WŁASNEGO FILMU"), systemImage: "film.stack")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Color.tougeMint)
                    Text(localized("Osobne projekty · ręczne dopasowanie telemetrii"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PhotosPicker(selection: $selectedPhotoItem, matching: .videos, preferredItemEncoding: .current) {
                    Label(localized("Nowy montaż"), systemImage: "plus")
                        .font(.caption.weight(.black))
                }
                .buttonStyle(.borderedProminent)
                .tint(.tougeMint)
                .disabled(isImportingVideo)
            }

            if isImportingVideo {
                importProgressCard
            } else if externalProjects.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(Color.tougeMint)
                    Text(localized("Nie masz jeszcze montażu dla tego przejazdu"))
                        .font(.subheadline.weight(.bold))
                    Text(localized("Wybierz film z galerii, wskaż odpowiadający mu fragment danych i wyeksportuj gotową kopię z HUD-em."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 9) {
                    ForEach(Array(externalProjects.enumerated()), id: \.element.id) { index, project in
                        externalProjectRow(project, index: externalProjects.count - index)
                    }
                }
            }

            Label(
                localized("Touge Dash zapisuje lokalną kopię roboczą filmu, aby projekt pozostał dostępny do edycji. Nie jest ona częścią nagrania przejazdu ani nie trafia do chmury."),
                systemImage: "internaldrive"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var importProgressCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: importStage.systemImage)
                    .foregroundStyle(Color.tougeMint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(importStage.title)
                        .font(.caption.weight(.black))
                    Text(String(format: localized("Etap %d z 4"), importStage.step))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let fraction = importStage.fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(Color.tougeMint)
                } else {
                    ProgressView()
                        .tint(.tougeMint)
                }
            }

            if let fraction = importStage.fraction {
                ProgressView(value: fraction, total: 1)
                    .tint(.tougeMint)
            }

            Text(importStage.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func externalProjectRow(_ project: DriveVideoRecording, index: Int) -> some View {
        let alignment = DriveVideoTimelineAlignment(recording: project, session: session)
        return HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.title3)
                .foregroundStyle(Color.tougeMint)
                .frame(width: 42, height: 42)
                .background(Color.tougeMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: localized("Montaż %d"), index))
                    .font(.subheadline.weight(.black))
                Text("\(project.duration.videoDurationText) · \(DriveVideoFileStore.formattedSize(project.fileSizeBytes))")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(String(
                    format: localized("Dane przejazdu %@–%@"),
                    alignment.telemetryStartSeconds.videoPreciseDurationText,
                    alignment.telemetryEndSeconds.videoPreciseDurationText
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.tougeCyan)
            }

            Spacer(minLength: 4)

            Button {
                exportRecording = project
            } label: {
                Text(localized("Edytuj"))
                    .font(.caption.weight(.black))
            }
            .buttonStyle(.borderedProminent)
            .tint(.tougeMint)

            Menu {
                Button(role: .destructive) {
                    recordingPendingDeletion = project
                    showingDeleteConfirmation = true
                } label: {
                    Label(localized("Usuń projekt i kopię lokalną"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sectionPanel<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.065))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(accent.opacity(0.24), lineWidth: 1)
                    }
            }
    }

    private var deletionTitle: String {
        recordingPendingDeletion?.sourceKind == .photoLibrary
            ? localized("Usunąć projekt montażowy?")
            : localized("Usunąć nagranie z urządzenia?")
    }

    private var deletionMessage: String {
        recordingPendingDeletion?.sourceKind == .photoLibrary
            ? localized("Lokalna kopia robocza zostanie usunięta. Oryginalny film w galerii i dane przejazdu pozostaną bez zmian.")
            : localized("Tej operacji nie można cofnąć. Dane i wykresy przejazdu pozostaną zapisane.")
    }

    private var deletionActionTitle: String {
        recordingPendingDeletion?.sourceKind == .photoLibrary
            ? localized("Usuń projekt")
            : localized("Usuń film")
    }

    @MainActor
    private func importVideo(from item: PhotosPickerItem) async {
        guard !isImportingVideo else { return }
        isImportingVideo = true
        importStage = .retrieving(nil)
        var copiedFileName: String?
        var insertedRecording: DriveVideoRecording?
        defer {
            isImportingVideo = false
            selectedPhotoItem = nil
        }
        do {
            let transfer = try await loadVideoTransfer(from: item)
            let prepared = try await DriveVideoImportService.prepare(from: transfer) { stage in
                switch stage {
                case .inspecting:
                    importStage = .inspecting
                case .copying(let fraction):
                    importStage = .copying(fraction)
                }
            }
            copiedFileName = prepared.fileName
            importStage = .saving
            let recording = DriveVideoRecording(
                sessionID: session.id,
                fileName: prepared.fileName,
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(prepared.metadata.duration),
                duration: prepared.metadata.duration,
                fileSizeBytes: prepared.fileSizeBytes,
                pixelWidth: prepared.metadata.width,
                pixelHeight: prepared.metadata.height,
                framesPerSecond: prepared.metadata.framesPerSecond,
                cameraName: DriveVideoSourceKind.photoLibrary.title,
                hasAudio: prepared.metadata.hasAudio,
                preferredOverlayTemplateID: overlayStore.selectedTemplateID,
                sourceKind: .photoLibrary,
                sourceDisplayName: prepared.displayName,
                telemetryTrimStartSeconds: 0
            )
            insertedRecording = recording
            modelContext.insert(recording)
            try modelContext.save()
            copiedFileName = nil
            exportRecording = recording
        } catch {
            if let copiedFileName,
               let directory = try? DriveVideoFileStore.directoryURL() {
                try? FileManager.default.removeItem(at: directory.appending(path: copiedFileName))
            }
            if let insertedRecording { modelContext.delete(insertedRecording) }
            importError = error.localizedDescription
        }
    }

    @MainActor
    private func loadVideoTransfer(from item: PhotosPickerItem) async throws -> DriveVideoTransfer {
        var monitorTask: Task<Void, Never>?
        defer { monitorTask?.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            let progress = item.loadTransferable(type: DriveVideoTransfer.self) { result in
                switch result {
                case .success(let transfer):
                    if let transfer {
                        continuation.resume(returning: transfer)
                    } else {
                        continuation.resume(throwing: DriveVideoImportError.unavailable)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            let currentFraction: Double? = progress.totalUnitCount > 0
                ? min(1, max(0, progress.fractionCompleted))
                : nil
            importStage = .retrieving(currentFraction)
            monitorTask = Task { @MainActor in
                while !Task.isCancelled, !progress.isFinished {
                    let fraction: Double? = progress.totalUnitCount > 0
                        ? min(1, max(0, progress.fractionCompleted))
                        : nil
                    importStage = .retrieving(fraction)
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
    }

    private func clipTitle(_ recording: DriveVideoRecording, at index: Int) -> String {
        let time = recording.startedAt.formatted(date: .omitted, time: .standard)
        return String(format: localized("Klip %d · %@"), index + 1, time)
    }

    private func selectOverlay(_ template: VideoOverlayTemplate, for recording: DriveVideoRecording) {
        overlayStore.select(template.id)
        recording.preferredOverlayTemplateID = template.id
        try? modelContext.save()
    }

    @ViewBuilder
    private func metadata(for recording: DriveVideoRecording) -> some View {
        let dimensions = recording.pixelWidth > 0 && recording.pixelHeight > 0
            ? "\(recording.pixelWidth)×\(recording.pixelHeight)"
            : localized("nieznana rozdzielczość")
        HStack(spacing: 8) {
            VideoMetadataPill(icon: "internaldrive", text: DriveVideoFileStore.formattedSize(recording.fileSizeBytes))
            VideoMetadataPill(icon: "rectangle.landscape", text: dimensions)
            VideoMetadataPill(icon: "clock", text: recording.duration.videoDurationText)
            VideoMetadataPill(icon: recording.hasAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", text: recording.cameraName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveVideoSynchronizedPlayer: View {
    let session: DriveSession
    let recording: DriveVideoRecording
    @Binding var selectedTime: Date?
    let overlay: VideoOverlayTemplate?
    let selectedSample: TelemetryHistorySample?
    let samples: [TelemetryHistorySample]

    @State private var player: AVPlayer?
    @State private var fileIsMissing = false
    @State private var lastPlayerTimestamp: Date?
    @State private var isFollowingPlayback = false

    private var alignment: DriveVideoTimelineAlignment {
        DriveVideoTimelineAlignment(recording: recording, session: session)
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                if let overlay {
                    VideoTelemetryOverlayView(template: overlay, sample: selectedSample, samples: samples)
                        .padding(5)
                }
            } else if fileIsMissing {
                ContentUnavailableView(
                    localized("Brak lokalnego filmu"),
                    systemImage: "video.slash",
                    description: Text(localized("Plik został usunięty poza aplikacją lub nie jest już dostępny."))
                )
            } else {
                ProgressView()
            }
        }
        .aspectRatio(playerAspectRatio, contentMode: .fit)
        .task(id: recording.id) {
            await prepareAndFollowPlayback()
        }
        .onDisappear { player?.pause() }
        .onChange(of: selectedTime) { _, newValue in
            guard !isFollowingPlayback, let newValue, let player else { return }
            let telemetrySeconds = newValue.timeIntervalSince(session.startedAt)
            let seconds = alignment.videoStartSeconds + telemetrySeconds - alignment.telemetryStartSeconds
            guard seconds >= alignment.videoStartSeconds - 0.15,
                  seconds <= alignment.videoEndSeconds + 0.15 else { return }
            let current = player.currentTime().seconds
            guard !current.isFinite || abs(current - seconds) > 0.28 else { return }
            player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private var playerAspectRatio: CGFloat {
        guard recording.pixelWidth > 0, recording.pixelHeight > 0 else { return 16 / 9 }
        return CGFloat(recording.pixelWidth) / CGFloat(recording.pixelHeight)
    }

    @MainActor
    private func prepareAndFollowPlayback() async {
        player?.pause()
        player = nil
        fileIsMissing = false
        guard let url = try? DriveVideoFileStore.url(for: recording),
              FileManager.default.fileExists(atPath: url.path) else {
            fileIsMissing = true
            return
        }

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        let initialSeconds = selectedTime.map {
            alignment.videoStartSeconds + $0.timeIntervalSince(session.startedAt) - alignment.telemetryStartSeconds
        } ?? alignment.videoStartSeconds
        if initialSeconds >= 0, initialSeconds <= recording.duration {
            await newPlayer.seek(to: CMTime(seconds: initialSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }

        while !Task.isCancelled, player === newPlayer {
            let seconds = newPlayer.currentTime().seconds
            if seconds.isFinite, seconds > alignment.videoEndSeconds + 0.05 {
                newPlayer.pause()
                await newPlayer.seek(
                    to: CMTime(seconds: alignment.videoEndSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                continue
            }
            if seconds.isFinite,
               seconds >= alignment.videoStartSeconds,
               seconds <= alignment.videoEndSeconds + 0.15 {
                let telemetrySeconds = alignment.telemetryStartSeconds + seconds - alignment.videoStartSeconds
                let timestamp = session.startedAt.addingTimeInterval(telemetrySeconds)
                if lastPlayerTimestamp.map({ abs($0.timeIntervalSince(timestamp)) > 0.08 }) ?? true {
                    isFollowingPlayback = true
                    lastPlayerTimestamp = timestamp
                    selectedTime = timestamp
                    await Task.yield()
                    isFollowingPlayback = false
                }
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }
}

private struct VideoMetadataPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct DriveVideoExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DriveSession
    let recording: DriveVideoRecording
    let samples: [TelemetryHistorySample]
    let sample: TelemetryHistorySample?
    @ObservedObject var overlayStore: VideoOverlayTemplateStore
    private let timelineSpeedValues: [Double]

    @ObservedObject private var exporter = DriveVideoExporter.shared
    @State private var addsOverlay = true
    @State private var showingOverlayManager = false
    @State private var alignment: DriveVideoTimelineAlignment
    @State private var overlayDraft: VideoOverlayTemplate
    @State private var selectedElementID: UUID?
    @State private var player: AVPlayer?
    @State private var fileIsMissing = false
    @State private var previewTelemetryTime: Date?
    @State private var previewRelativeSeconds = 0.0
    @State private var isPreviewPlaying = false
    @State private var playsSelectedExportRange = false
    @State private var showsAdvancedAlignment = false
    @State private var thumbnails: [CGImage] = []
    @State private var exportRangeThumbnails: [CGImage] = []
    @State private var exportRangeStart = 0.0
    @State private var exportRangeEnd: Double
    @State private var exportScrubPosition: VideoExportScrubPosition?
    @State private var exportScrubFrame: CGImage?
    @State private var sourceVideoURL: URL?

    init(
        session: DriveSession,
        recording: DriveVideoRecording,
        samples: [TelemetryHistorySample],
        sample: TelemetryHistorySample?,
        overlayStore: VideoOverlayTemplateStore
    ) {
        self.session = session
        self.recording = recording
        self.samples = samples
        self.sample = sample
        self.overlayStore = overlayStore
        timelineSpeedValues = samples.videoTimelineValues(maxPoints: 480)
        let initialAlignment = DriveVideoTimelineAlignment(recording: recording, session: session)
        _alignment = State(initialValue: initialAlignment)
        _overlayDraft = State(initialValue: overlayStore.template(id: recording.preferredOverlayTemplateID))
        _exportRangeEnd = State(initialValue: initialAlignment.duration)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                exportContent.padding(16)
            }
            .background(DashboardBackground())
            .navigationTitle(localized("Eksport filmu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Zamknij")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingOverlayManager) {
                VideoOverlayTemplateManagerView(store: overlayStore)
            }
            .task(id: recording.id) {
                await preparePreview()
            }
            .task(id: recording.id) {
                await loadExportRangeThumbnails()
            }
            .task(id: exportScrubPosition) {
                await loadExportScrubFrame()
            }
            .task(id: showsAdvancedAlignment) {
                guard showsAdvancedAlignment, thumbnails.isEmpty else { return }
                await loadTimelineThumbnails()
            }
            .onDisappear {
                player?.pause()
            }
            .onChange(of: alignment.duration) { previousDuration, newDuration in
                let selectedWholePreviousRange = exportRangeStart <= 0.001
                    && abs(exportRangeEnd - previousDuration) <= 0.05
                exportRangeStart = min(exportRangeStart, max(0, newDuration - minimumExportDuration))
                exportRangeEnd = selectedWholePreviousRange
                    ? newDuration
                    : min(max(exportRangeStart + minimumExportDuration, exportRangeEnd), newDuration)
            }
        }
    }

    private var exportContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            exportPreview
            exportRangeSelector
            previewControls
            synchronizationEditor
            exportOptions
            exportStatus
            exportButton
            Text(localized("Oryginalny film pozostaje wyłącznie na tym urządzeniu. Eksport tworzy kopię w aplikacji Zdjęcia; Touge Dash nie wysyła nagrania na serwer."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var exportPreview: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                if let exportScrubFrame, exportScrubPosition != nil {
                    Image(decorative: exportScrubFrame, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
                if addsOverlay {
                    EditableVideoTelemetryOverlayView(
                        template: $overlayDraft,
                        selectedElementID: $selectedElementID,
                        sample: previewSample,
                        samples: samples,
                        routeTimestamp: previewTelemetryTime
                    )
                    .padding(5)
                }
            } else if fileIsMissing {
                ContentUnavailableView(localized("Brak lokalnego filmu"), systemImage: "video.slash")
            } else {
                ProgressView()
            }
        }
        .aspectRatio(exportAspectRatio, contentMode: .fit)
        .frame(maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(selectedElementID == nil ? Color.white.opacity(0.12) : Color.tougeCyan.opacity(0.7), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if addsOverlay {
                Label(localized("Przeciągnij lub uszczypnij element"), systemImage: "hand.draw.fill")
                    .font(.caption2.weight(.black))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                .padding(9)
            }
        }
        .overlay(alignment: .topTrailing) {
            if addsOverlay {
                Menu {
                    ForEach(overlayStore.templates) { template in
                        Menu(template.name) {
                            ForEach(template.elements) { element in
                                Button {
                                    addWidget(element)
                                } label: {
                                    Label(widgetTitle(element), systemImage: element.kind.icon)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.black))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.tougeCyan.opacity(0.75), lineWidth: 1))
                }
                .accessibilityLabel(localized("Dodaj widget"))
                .padding(9)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let exportScrubPosition {
                HStack(spacing: 7) {
                    Image(systemName: "viewfinder")
                    Text(
                        exportScrubPosition.edge == .start
                            ? localized("Klatka początku")
                            : localized("Klatka końca")
                    )
                    Text(exportScrubPosition.relativeSeconds.videoPreciseDurationText)
                        .foregroundStyle(Color.tougeYellow)
                }
                .font(.caption.monospacedDigit().weight(.black))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
    }

    private var exportAspectRatio: CGFloat {
        guard recording.pixelWidth > 0, recording.pixelHeight > 0 else { return 16 / 9 }
        return CGFloat(recording.pixelWidth) / CGFloat(recording.pixelHeight)
    }

    private func addWidget(_ source: VideoOverlayElement) {
        let widget = VideoOverlayElement(
            metric: source.metric,
            slot: source.slot,
            scale: source.scale,
            sizeMultiplier: source.sizeMultiplier,
            mapZoom: source.mapZoom,
            accent: source.accent,
            kind: source.kind,
            landscapePosition: source.landscapePosition,
            portraitPosition: source.portraitPosition
        )
        overlayDraft.elements.append(widget)
        selectedElementID = widget.id
    }

    private func widgetTitle(_ element: VideoOverlayElement) -> String {
        switch element.kind {
        case .routeMap, .routeMapCircular, .routeMapFollow, .routeMapLight, .routeMapLightCircular, .routeMapAmber:
            element.kind.title
        default:
            "\(element.kind.title) · \(element.metric.shortTitle)"
        }
    }

    private var exportOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(localized("Nanieś parametry na film"), isOn: $addsOverlay)
                .font(.headline)
                .tint(.tougeCyan)

            if addsOverlay {
                Picker(localized("Szablon HUD"), selection: templateSelection) {
                    ForEach(overlayStore.templates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    showingOverlayManager = true
                } label: {
                    Label(localized("Edytuj szablony nakładek"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var exportButton: some View {
        Button {
            Task {
                alignment.persist(to: recording)
                overlayDraft.modifiedAt = .now
                if addsOverlay { overlayStore.save(overlayDraft) }
                recording.preferredOverlayTemplateID = overlayDraft.id
                try? modelContext.save()
                let trimmedAlignment = exportAlignment
                await exporter.export(
                    recording: recording,
                    samples: exportSamples(),
                    template: addsOverlay ? overlayDraft : nil,
                    alignment: trimmedAlignment,
                    telemetryStartDate: trimmedAlignment.telemetryStartDate(session: session)
                )
            }
        } label: {
            Label(localized("Zapisz film w Zdjęciach"), systemImage: "square.and.arrow.down.fill")
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(.tougeCyan)
        .disabled(exporter.state.isWorking)
    }

    private var exportRangeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("WYBIERZ FRAGMENT DO EKSPORTU"))
                        .font(.caption2.weight(.black))
                        .tracking(0.9)
                        .foregroundStyle(Color.tougeYellow)
                    Text(selectedExportDuration.videoPreciseDurationText)
                        .font(.title3.monospacedDigit().weight(.black))
                }
                Spacer()
                Text("\(exportRangeStart.videoPreciseDurationText) – \(exportRangeEnd.videoPreciseDurationText)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Button {
                    toggleExportRangePlayback()
                } label: {
                    Image(systemName: isPreviewPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.black))
                        .frame(width: 54, height: 76)
                        .background(Color.white.opacity(0.13))
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .accessibilityLabel(isPreviewPlaying ? localized("Pauza") : localized("Odtwórz wybrany fragment"))

                VideoExportRangeSelector(
                    start: $exportRangeStart,
                    end: $exportRangeEnd,
                    scrubPosition: $exportScrubPosition,
                    totalDuration: alignment.duration,
                    thumbnails: exportRangeThumbnails,
                    onScrub: scrubExportPreview
                )
                .frame(height: 76)
            }
            Text(localized("Przeciągnij lewy lub prawy uchwyt. Przyciemniony fragment nie trafi do galerii."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(!exporter.state.isWorking)
        .opacity(exporter.state.isWorking ? 0.62 : 1)
    }

    private var minimumExportDuration: Double {
        min(1, max(0.1, alignment.duration))
    }

    private var selectedExportDuration: Double {
        max(0, exportRangeEnd - exportRangeStart)
    }

    private var exportAlignment: DriveVideoTimelineAlignment {
        alignment.trimming(
            relativeStart: exportRangeStart,
            duration: selectedExportDuration,
            videoDuration: recording.duration,
            telemetryDuration: telemetryDuration
        )
    }

    private func exportSamples() -> [TelemetryHistorySample] {
        let sessionID = recording.sessionID
        let startedAt = session.startedAt.addingTimeInterval(-0.25)
        let endedAt = session.endedAt.addingTimeInterval(0.25)
        let descriptor = FetchDescriptor<TelemetryHistorySample>(
            predicate: #Predicate { sample in
                sample.session?.id == sessionID && sample.timestamp >= startedAt && sample.timestamp <= endedAt
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? samples
    }

    private var previewSample: TelemetryHistorySample? {
        guard let previewTelemetryTime else { return sample ?? samples.first }
        return samples.videoNearest(to: previewTelemetryTime)
    }

    private var templateSelection: Binding<UUID> {
        Binding(
            get: { overlayDraft.id },
            set: { id in
                overlayDraft = overlayStore.template(id: id)
                selectedElementID = nil
            }
        )
    }

    private var synchronizationEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(localized("DOPASUJ PARAMETRY DO FILMU"), systemImage: "timeline.selection")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Color.tougeCyan)
                Text(String(
                    format: localized("Film ma %@. Wybierz moment przejazdu, od którego ma rozpocząć się ten fragment parametrów."),
                    alignment.duration.videoPreciseDurationText
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TelemetryFragmentSelector(
                start: telemetryStartBinding,
                duration: alignment.duration,
                totalDuration: telemetryDuration,
                values: timelineSpeedValues
            )

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.tougeMint)
                Text(String(
                    format: localized("Do eksportu: dane %@–%@ z przejazdu %@"),
                    alignment.telemetryStartSeconds.videoPreciseDurationText,
                    alignment.telemetryEndSeconds.videoPreciseDurationText,
                    telemetryDuration.videoPreciseDurationText
                ))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $showsAdvancedAlignment) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(localized("Tutaj możesz dodatkowo przyciąć początek lub koniec filmu oraz niezależnie przesunąć obie osie czasu."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TimelineAlignmentTrack(
                        title: localized("FILM Z GALERII"),
                        icon: "film.stack",
                        totalDuration: recording.duration,
                        start: videoStartBinding,
                        duration: durationBinding
                    ) {
                        VideoTimelineBackdrop(thumbnails: thumbnails)
                    }

                    TimelineAlignmentTrack(
                        title: localized("DANE PRZEJAZDU"),
                        icon: "waveform.path.ecg",
                        totalDuration: telemetryDuration,
                        start: telemetryStartBinding,
                        duration: durationBinding
                    ) {
                        TelemetryTimelineBackdrop(values: timelineSpeedValues)
                    }

                    HStack(spacing: 8) {
                        TimelineNudgeControl(
                            title: localized("Początek filmu"),
                            value: videoStartBinding,
                            maximum: max(0, recording.duration - alignment.duration)
                        )
                        TimelineNudgeControl(
                            title: localized("Początek danych"),
                            value: telemetryStartBinding,
                            maximum: max(0, telemetryDuration - alignment.duration)
                        )
                    }
                }
                .padding(.top, 12)
            } label: {
                Label(localized("Zaawansowane przycinanie obu osi"), systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.black))
            }
            .tint(.tougeCyan)
        }
        .padding(16)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var telemetryDuration: Double {
        max(session.duration, samples.last?.timestamp.timeIntervalSince(session.startedAt) ?? 0, 0.1)
    }

    private var videoStartBinding: Binding<Double> {
        Binding(
            get: { alignment.videoStartSeconds },
            set: { newValue in
                alignment.videoStartSeconds = min(max(0, newValue), max(0, recording.duration - alignment.duration))
                resetPreview()
            }
        )
    }

    private var telemetryStartBinding: Binding<Double> {
        Binding(
            get: { alignment.telemetryStartSeconds },
            set: { newValue in
                alignment.telemetryStartSeconds = min(max(0, newValue), max(0, telemetryDuration - alignment.duration))
                resetPreview(seeksVideo: false)
            }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { alignment.duration },
            set: { newValue in
                let maximum = min(
                    recording.duration - alignment.videoStartSeconds,
                    telemetryDuration - alignment.telemetryStartSeconds
                )
                alignment.duration = min(max(0.1, newValue), max(0.1, maximum))
                resetPreview()
            }
        )
    }

    @MainActor
    private func preparePreview() async {
        player?.pause()
        player = nil
        fileIsMissing = false
        guard let url = try? DriveVideoFileStore.url(for: recording),
              FileManager.default.fileExists(atPath: url.path) else {
            fileIsMissing = true
            sourceVideoURL = nil
            return
        }
        sourceVideoURL = url
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        await newPlayer.seek(
            to: CMTime(seconds: alignment.videoStartSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        previewTelemetryTime = alignment.telemetryStartDate(session: session)
        previewRelativeSeconds = 0
        isPreviewPlaying = false
        while !Task.isCancelled, player === newPlayer {
            let seconds = newPlayer.currentTime().seconds
            let playing = newPlayer.timeControlStatus == .playing
            if isPreviewPlaying != playing {
                isPreviewPlaying = playing
            }
            if playing, seconds.isFinite {
                let relative = min(max(0, seconds - alignment.videoStartSeconds), alignment.duration)
                if abs(previewRelativeSeconds - relative) >= 1.0 / 30.0 {
                    previewRelativeSeconds = relative
                    previewTelemetryTime = session.startedAt.addingTimeInterval(alignment.telemetryStartSeconds + relative)
                }
                let playbackEnd = playsSelectedExportRange ? exportRangeEnd : alignment.duration
                if relative > playbackEnd + 0.05 {
                    newPlayer.pause()
                    let restart = playsSelectedExportRange ? exportRangeStart : 0
                    await newPlayer.seek(
                        to: CMTime(seconds: alignment.videoStartSeconds + restart, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                    previewRelativeSeconds = restart
                    previewTelemetryTime = session.startedAt.addingTimeInterval(
                        alignment.telemetryStartSeconds + restart
                    )
                    isPreviewPlaying = false
                }
            }
            try? await Task.sleep(for: .milliseconds(playing ? 33 : 300))
        }
    }

    @MainActor
    private func loadTimelineThumbnails() async {
        guard let url = try? DriveVideoFileStore.url(for: recording),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let loaded = await VideoTimelineThumbnailLoader.load(
            url: url,
            duration: recording.duration,
            count: recording.pixelHeight > recording.pixelWidth ? 5 : 7
        )
        guard !Task.isCancelled, showsAdvancedAlignment else { return }
        thumbnails = loaded
    }

    @MainActor
    private func loadExportRangeThumbnails() async {
        guard let url = try? DriveVideoFileStore.url(for: recording),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let loaded = await VideoTimelineThumbnailLoader.load(
            url: url,
            start: alignment.videoStartSeconds,
            duration: alignment.duration,
            count: recording.pixelHeight > recording.pixelWidth ? 8 : 10
        )
        guard !Task.isCancelled else { return }
        exportRangeThumbnails = loaded
    }

    @MainActor
    private func loadExportScrubFrame() async {
        guard let position = exportScrubPosition,
              let sourceVideoURL else {
            exportScrubFrame = nil
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(45))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let frame = await VideoTimelineThumbnailLoader.frame(
            url: sourceVideoURL,
            at: alignment.videoStartSeconds + position.relativeSeconds
        )
        guard !Task.isCancelled, exportScrubPosition == position else { return }
        exportScrubFrame = frame
    }

    private func scrubExportPreview(to relativeSeconds: Double) {
        playsSelectedExportRange = false
        previewPositionBinding.wrappedValue = relativeSeconds
    }

    private func seekPreview(to seconds: Double) {
        player?.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private var previewControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Button(action: togglePreviewPlayback) {
                    Label(
                        isPreviewPlaying ? localized("Pauza") : localized("Odtwórz podgląd"),
                        systemImage: isPreviewPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.tougeCyan)
                .disabled(player == nil || alignment.duration <= 0)

                Button(action: resetPreview) {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(localized("Od początku podglądu"))
            }

            HStack(spacing: 10) {
                Text(previewRelativeSeconds.videoPreciseDurationText)
                Slider(value: previewPositionBinding, in: 0...max(0.1, alignment.duration))
                    .tint(.tougeMint)
                Text(alignment.duration.videoPreciseDurationText)
            }
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var previewPositionBinding: Binding<Double> {
        Binding(
            get: { min(previewRelativeSeconds, alignment.duration) },
            set: { relative in
                player?.pause()
                isPreviewPlaying = false
                previewRelativeSeconds = min(max(0, relative), alignment.duration)
                previewTelemetryTime = session.startedAt.addingTimeInterval(
                    alignment.telemetryStartSeconds + previewRelativeSeconds
                )
                seekPreview(to: alignment.videoStartSeconds + previewRelativeSeconds)
            }
        )
    }

    private func togglePreviewPlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPreviewPlaying = false
            return
        }
        if previewRelativeSeconds >= alignment.duration - 0.05 {
            resetPreview()
        }
        playsSelectedExportRange = false
        player.play()
        isPreviewPlaying = true
    }

    private func toggleExportRangePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing, playsSelectedExportRange {
            player.pause()
            isPreviewPlaying = false
            return
        }
        previewPositionBinding.wrappedValue = exportRangeStart
        playsSelectedExportRange = true
        player.play()
        isPreviewPlaying = true
    }

    private func resetPreview() {
        resetPreview(seeksVideo: true)
    }

    private func resetPreview(seeksVideo: Bool) {
        player?.pause()
        isPreviewPlaying = false
        playsSelectedExportRange = false
        previewRelativeSeconds = 0
        previewTelemetryTime = alignment.telemetryStartDate(session: session)
        if seeksVideo { seekPreview(to: alignment.videoStartSeconds) }
    }

    @ViewBuilder
    private var exportStatus: some View {
        switch exporter.state {
        case .idle:
            EmptyView()
        case let .rendering(progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(localized("Renderowanie filmu…"))
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                }
                .font(.caption.weight(.bold))
                ProgressView(value: progress).tint(.tougeCyan)
                Button(localized("Anuluj eksport"), role: .cancel) { exporter.cancel() }
                    .font(.caption.weight(.bold))
            }
        case .savingToPhotos:
            Label(localized("Zapisywanie w aplikacji Zdjęcia…"), systemImage: "photo.badge.arrow.down")
                .font(.caption.weight(.bold))
        case .completed:
            Label(localized("Film został zapisany w aplikacji Zdjęcia."), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.tougeMint)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 5) {
                Label(localized("Nie udało się wyeksportować filmu"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.tougeOrange)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TelemetryFragmentSelector: View {
    @Binding var start: Double
    let duration: Double
    let totalDuration: Double
    let values: [Double]

    private var maximumStart: Double { max(0, totalDuration - duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("POCZĄTEK DANYCH Z PRZEJAZDU"))
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(start.videoPreciseDurationText)
                        .font(.title2.monospacedDigit().weight(.black))
                        .foregroundStyle(Color.tougeCyan)
                }
                Spacer()
                Text("\(start.videoPreciseDurationText) – \((start + duration).videoPreciseDurationText)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.tougeMint)
            }

            TelemetryFragmentOverview(
                values: values,
                start: start,
                duration: duration,
                totalDuration: totalDuration
            )
            .frame(height: 58)

            Slider(
                value: $start,
                in: 0...max(0.001, maximumStart)
            )
            .tint(.tougeCyan)
            .disabled(maximumStart <= 0)

            HStack(spacing: 7) {
                nudgeButton(seconds: -10)
                nudgeButton(seconds: -1)
                Spacer(minLength: 4)
                nudgeButton(seconds: 1)
                nudgeButton(seconds: 10)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private func nudgeButton(seconds: Double) -> some View {
        Button {
            start = min(maximumStart, max(0, start + seconds))
        } label: {
            Text(seconds > 0 ? "+\(Int(seconds)) s" : "\(Int(seconds)) s")
                .font(.caption.monospacedDigit().weight(.black))
                .frame(minWidth: 48)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(
            maximumStart <= 0 ||
            (seconds < 0 && start <= 0) ||
            (seconds > 0 && start >= maximumStart)
        )
    }
}

private struct TelemetryFragmentOverview: View {
    let values: [Double]
    let start: Double
    let duration: Double
    let totalDuration: Double

    var body: some View {
        GeometryReader { proxy in
            let safeTotal = max(0.1, totalDuration)
            let x = proxy.size.width * start / safeTotal
            let width = max(6, proxy.size.width * duration / safeTotal)
            ZStack(alignment: .leading) {
                TelemetryTimelineBackdrop(values: values)
                Color.black.opacity(0.32)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.tougeCyan.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.tougeCyan, lineWidth: 2)
                    }
                    .frame(width: min(width, proxy.size.width - x))
                    .offset(x: x)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct TimelineAlignmentTrack<Backdrop: View>: View {
    let title: String
    let icon: String
    let totalDuration: Double
    @Binding var start: Double
    @Binding var duration: Double
    @ViewBuilder let backdrop: () -> Backdrop

    @State private var dragStart: Double?
    @State private var dragDuration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                Spacer()
                Text("\(start.videoPreciseDurationText) — \((start + duration).videoPreciseDurationText)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let safeTotal = max(0.1, totalDuration)
                let selectionX = proxy.size.width * start / safeTotal
                let selectionWidth = max(18, proxy.size.width * duration / safeTotal)
                ZStack(alignment: .leading) {
                    backdrop()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Color.black.opacity(0.62)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tougeCyan.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.tougeCyan, lineWidth: 2)
                        }
                        .frame(width: min(selectionWidth, proxy.size.width - selectionX))
                        .offset(x: selectionX)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let origin = dragStart ?? start
                                    dragStart = origin
                                    let delta = value.translation.width / max(1, proxy.size.width) * safeTotal
                                    start = min(max(0, origin + delta), max(0, safeTotal - duration))
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 5, height: 38)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .offset(x: min(proxy.size.width - 5, selectionX + selectionWidth - 2.5))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let origin = dragDuration ?? duration
                                    dragDuration = origin
                                    let delta = value.translation.width / max(1, proxy.size.width) * safeTotal
                                    duration = min(max(0.1, origin + delta), max(0.1, safeTotal - start))
                                }
                                .onEnded { _ in dragDuration = nil }
                        )
                }
            }
            .frame(height: 62)
        }
    }
}

private struct VideoTimelineBackdrop: View {
    let thumbnails: [CGImage]

    var body: some View {
        HStack(spacing: 1) {
            if thumbnails.isEmpty {
                ForEach(0..<7, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.08))
                }
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
        }
    }
}

private struct VideoExportScrubPosition: Hashable {
    enum Edge: Hashable {
        case start
        case end
    }

    let edge: Edge
    let relativeSeconds: Double
}

private struct VideoExportRangeSelector: View {
    @Binding var start: Double
    @Binding var end: Double
    @Binding var scrubPosition: VideoExportScrubPosition?
    let totalDuration: Double
    let thumbnails: [CGImage]
    let onScrub: (Double) -> Void

    @State private var initialStart: Double?
    @State private var initialEnd: Double?

    private let handleWidth: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let safeTotal = max(0.1, totalDuration)
            let width = max(1, proxy.size.width)
            let leftX = width * start / safeTotal
            let rightX = width * end / safeTotal
            let minimumDuration = min(1, safeTotal)

            ZStack(alignment: .leading) {
                VideoTimelineBackdrop(thumbnails: thumbnails)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Color.black.opacity(0.65)
                    .frame(width: max(0, leftX))

                Color.black.opacity(0.65)
                    .frame(width: max(0, width - rightX))
                    .offset(x: rightX)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: max(0, rightX - leftX))
                    .overlay {
                        Rectangle().stroke(Color.tougeYellow, lineWidth: 3)
                    }
                    .offset(x: leftX)

                rangeHandle(systemImage: "chevron.compact.left")
                    .offset(x: min(max(0, leftX), max(0, width - handleWidth)))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = initialStart ?? start
                                initialStart = origin
                                let delta = value.translation.width / width * safeTotal
                                start = min(max(0, origin + delta), max(0, end - minimumDuration))
                                scrubPosition = VideoExportScrubPosition(edge: .start, relativeSeconds: start)
                                onScrub(start)
                            }
                            .onEnded { _ in
                                initialStart = nil
                                scrubPosition = nil
                            }
                    )
                    .accessibilityLabel(localized("Początek eksportu"))

                rangeHandle(systemImage: "chevron.compact.right")
                    .offset(x: min(max(0, rightX - handleWidth), max(0, width - handleWidth)))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let origin = initialEnd ?? end
                                initialEnd = origin
                                let delta = value.translation.width / width * safeTotal
                                end = max(min(safeTotal, origin + delta), min(safeTotal, start + minimumDuration))
                                scrubPosition = VideoExportScrubPosition(edge: .end, relativeSeconds: end)
                                onScrub(end)
                            }
                            .onEnded { _ in
                                initialEnd = nil
                                scrubPosition = nil
                            }
                    )
                    .accessibilityLabel(localized("Koniec eksportu"))
            }
            .background(Color.white.opacity(0.08))
            .clipped()
            .overlay(alignment: .topLeading) {
                if let scrubPosition {
                    let anchorX = scrubPosition.edge == .start
                        ? leftX + handleWidth / 2
                        : rightX - handleWidth / 2
                    Text(scrubPosition.relativeSeconds.videoPreciseDurationText)
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.tougeYellow, in: Capsule())
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                        .offset(x: min(max(0, anchorX - 31), max(0, width - 62)), y: -34)
                }
            }
        }
    }

    private func rangeHandle(systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(Color.tougeYellow)
            Image(systemName: systemImage)
                .font(.title2.weight(.black))
                .foregroundStyle(.black)
        }
        .frame(width: handleWidth)
        .contentShape(Rectangle().inset(by: -8))
        .zIndex(2)
    }
}

private struct TelemetryTimelineBackdrop: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let maximum = max(1, values.max() ?? 1)
            var path = Path()
            for index in values.indices {
                let x = size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                let y = size.height * (1 - CGFloat(values[index] / maximum))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.tougeMint), lineWidth: 2)
        }
        .background(Color.tougeMint.opacity(0.08))
    }
}

private struct TimelineNudgeControl: View {
    let title: String
    @Binding var value: Double
    let maximum: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption2.weight(.black)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Button { value = max(0, value - 1) } label: { Image(systemName: "minus") }
                Text(value.videoPreciseDurationText)
                    .font(.caption.monospacedDigit().weight(.black))
                    .frame(minWidth: 54)
                Button { value = min(maximum, value + 1) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum VideoTimelineThumbnailLoader {
    nonisolated static func frame(url: URL, at seconds: Double) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    nonisolated static func load(
        url: URL,
        start: Double = 0,
        duration: Double,
        count: Int
    ) async -> [CGImage] {
        guard duration > 0, count > 0 else { return [] }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 280, height: 140)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)
        var images: [CGImage] = []
        for index in 0..<count {
            guard !Task.isCancelled else { break }
            let fraction = (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: start + duration * fraction, preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                images.append(result.image)
            }
        }
        return images
    }
}

private extension Array where Element == TelemetryHistorySample {
    func videoTimelineValues(maxPoints: Int) -> [Double] {
        guard count > maxPoints, maxPoints > 1 else { return map(\.speedKPH) }
        let step = Double(count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            self[Swift.min(count - 1, Int((Double(index) * step).rounded()))].speedKPH
        }
    }

    func videoNearest(to timestamp: Date) -> TelemetryHistorySample? {
        guard !isEmpty else { return nil }
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if self[middle].timestamp < timestamp { lower = middle + 1 } else { upper = middle }
        }
        if lower == 0 { return self[0] }
        if lower == count { return self[count - 1] }
        let before = self[lower - 1]
        let after = self[lower]
        return abs(before.timestamp.timeIntervalSince(timestamp)) <= abs(after.timestamp.timeIntervalSince(timestamp))
            ? before : after
    }
}

private extension TimeInterval {
    var videoDurationText: String {
        let total = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var videoPreciseDurationText: String {
        let safe = max(0, self)
        let minutes = Int(safe) / 60
        let seconds = safe - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
