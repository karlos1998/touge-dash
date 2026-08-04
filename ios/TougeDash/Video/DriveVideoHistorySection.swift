import AVFoundation
import AVKit
import SwiftData
import SwiftUI

struct DriveVideoHistorySection: View {
    @Environment(\.modelContext) private var modelContext
    let recordings: [DriveVideoRecording]
    let samples: [TelemetryHistorySample]
    @Binding var selectedTime: Date?
    @ObservedObject var overlayStore: VideoOverlayTemplateStore
    let onDelete: (DriveVideoRecording) -> Void

    @State private var selectedRecordingID: UUID?
    @State private var showsOverlayPreview = true
    @State private var showingOverlayManager = false
    @State private var showingExport = false
    @State private var showingDeleteConfirmation = false

    private var sortedRecordings: [DriveVideoRecording] {
        recordings.sorted { $0.startedAt < $1.startedAt }
    }

    private var selectedRecording: DriveVideoRecording? {
        let requestedID = selectedRecordingID ?? sortedRecordings.first?.id
        return sortedRecordings.first { $0.id == requestedID } ?? sortedRecordings.first
    }

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return samples.first }
        return samples.videoNearest(to: selectedTime)
    }

    private var selectedOverlay: VideoOverlayTemplate {
        overlayStore.template(id: selectedRecording?.preferredOverlayTemplateID)
    }

    var body: some View {
        cardContent
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.36))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.tougeCyan.opacity(0.24), lineWidth: 1)
                    }
            }
            .onAppear {
                if selectedRecordingID == nil {
                    selectedRecordingID = sortedRecordings.first?.id
                }
            }
            .onChange(of: recordings.map(\.id)) { _, ids in
                if let selectedRecordingID, ids.contains(selectedRecordingID) { return }
                self.selectedRecordingID = sortedRecordings.first?.id
            }
            .sheet(isPresented: $showingOverlayManager) {
                VideoOverlayTemplateManagerView(store: overlayStore)
            }
            .sheet(isPresented: $showingExport) {
                if let recording = selectedRecording {
                    DriveVideoExportSheet(
                        recording: recording,
                        samples: samples,
                        sample: selectedSample,
                        overlayStore: overlayStore
                    )
                }
            }
            .confirmationDialog(localized("Usunąć nagranie z urządzenia?"), isPresented: $showingDeleteConfirmation) {
                if let recording = selectedRecording {
                    Button(localized("Usuń film"), role: .destructive) { onDelete(recording) }
                }
                Button(localized("Anuluj"), role: .cancel) { }
            } message: {
                Text(localized("Tej operacji nie można cofnąć. Dane i wykresy przejazdu pozostaną zapisane."))
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(localized("NAGRANIE PRZEJAZDU"), systemImage: "video.fill")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Color.tougeCyan)
                    Text(localized("Film i wykresy korzystają z tej samej osi czasu."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sortedRecordings.count > 1 {
                    Menu {
                        ForEach(Array(sortedRecordings.enumerated()), id: \.element.id) { index, recording in
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
                            String(format: localized("Klipy: %d"), sortedRecordings.count),
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
                    recording: recording,
                    selectedTime: $selectedTime,
                    overlay: showsOverlayPreview ? selectedOverlay : nil,
                    selectedSample: selectedSample
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
                            showingExport = true
                        } label: {
                            Label(localized("Eksportuj do Zdjęć"), systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
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
    let recording: DriveVideoRecording
    @Binding var selectedTime: Date?
    let overlay: VideoOverlayTemplate?
    let selectedSample: TelemetryHistorySample?

    @State private var player: AVPlayer?
    @State private var fileIsMissing = false
    @State private var lastPlayerTimestamp: Date?
    @State private var isFollowingPlayback = false

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                if let overlay {
                    VideoTelemetryOverlayView(template: overlay, sample: selectedSample)
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
            let seconds = newValue.timeIntervalSince(recording.startedAt)
            guard seconds >= -0.15, seconds <= recording.duration + 0.15 else { return }
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
        let initialSeconds = selectedTime.map { $0.timeIntervalSince(recording.startedAt) } ?? 0
        if initialSeconds > 0, initialSeconds <= recording.duration {
            await newPlayer.seek(to: CMTime(seconds: initialSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }

        while !Task.isCancelled, player === newPlayer {
            let seconds = newPlayer.currentTime().seconds
            if seconds.isFinite, seconds >= 0 {
                let timestamp = recording.startedAt.addingTimeInterval(seconds)
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
            .background(Color.white.opacity(0.055), in: Capsule())
    }
}

private struct DriveVideoExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let recording: DriveVideoRecording
    let samples: [TelemetryHistorySample]
    let sample: TelemetryHistorySample?
    @ObservedObject var overlayStore: VideoOverlayTemplateStore

    @StateObject private var exporter = DriveVideoExporter()
    @State private var addsOverlay = true
    @State private var showingOverlayManager = false

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
                        if exporter.state.isWorking { exporter.cancel() }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingOverlayManager) {
                VideoOverlayTemplateManagerView(store: overlayStore)
            }
            .onAppear {
                if let preferred = recording.preferredOverlayTemplateID {
                    overlayStore.select(preferred)
                }
            }
            .onChange(of: overlayStore.selectedTemplateID) { _, templateID in
                recording.preferredOverlayTemplateID = templateID
                try? modelContext.save()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var exportContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            exportPreview
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
            if addsOverlay {
                VideoTelemetryOverlayView(template: overlayStore.selectedTemplate, sample: sample)
                    .padding(5)
            } else {
                Image(systemName: "video.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(exportAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var exportAspectRatio: CGFloat {
        guard recording.pixelWidth > 0, recording.pixelHeight > 0 else { return 16 / 9 }
        return CGFloat(recording.pixelWidth) / CGFloat(recording.pixelHeight)
    }

    private var exportOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(localized("Nanieś parametry na film"), isOn: $addsOverlay)
                .font(.headline)
                .tint(.tougeCyan)

            if addsOverlay {
                Picker(localized("Szablon HUD"), selection: $overlayStore.selectedTemplateID) {
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
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
    }

    private var exportButton: some View {
        Button {
            Task {
                let template = addsOverlay ? overlayStore.selectedTemplate : nil
                await exporter.export(recording: recording, samples: exportSamples(), template: template)
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

    private func exportSamples() -> [TelemetryHistorySample] {
        let sessionID = recording.sessionID
        let startedAt = recording.startedAt.addingTimeInterval(-0.25)
        let endedAt = recording.endedAt.addingTimeInterval(0.25)
        let descriptor = FetchDescriptor<TelemetryHistorySample>(
            predicate: #Predicate { sample in
                sample.session?.id == sessionID && sample.timestamp >= startedAt && sample.timestamp <= endedAt
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? samples
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

private extension Array where Element == TelemetryHistorySample {
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
}
