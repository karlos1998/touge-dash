import AVFoundation
import SwiftUI

struct DriveVideoRecordingCard: View {
    @ObservedObject var recorder: DriveVideoRecorder
    @ObservedObject private var settings: DriveVideoSettingsStore

    init(recorder: DriveVideoRecorder) {
        self.recorder = recorder
        _settings = ObservedObject(wrappedValue: recorder.settings)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { recorder.setEnabled($0, activeSessionID: recorder.activeTelemetrySessionID) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill((recorder.isRecording ? Color.tougeRed : Color.tougeCyan).opacity(0.14))
                    Image(systemName: recorder.isRecording ? "record.circle.fill" : "video.fill")
                        .foregroundStyle(recorder.isRecording ? Color.tougeRed : Color.tougeCyan)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("NAGRYWANIE PRZEJAZDU"))
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(recorder.statusLabel)
                        .font(.caption)
                        .foregroundStyle(recorder.isRecording ? Color.tougeRed : .secondary)
                }

                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .tint(.tougeRed)
            }

            if settings.isEnabled {
                VStack(spacing: 0) {
                    cameraPicker
                    Divider().overlay(Color.white.opacity(0.06))
                    qualityPicker
                    Divider().overlay(Color.white.opacity(0.06))
                    Toggle(isOn: audioBinding) {
                        settingLabel(
                            title: localized("Dźwięk z mikrofonu"),
                            subtitle: localized("Możesz nagrywać również bez dźwięku"),
                            icon: "mic.fill",
                            tint: .tougeOrange
                        )
                    }
                    .tint(.tougeCyan)
                    .padding(.vertical, 11)
                }
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                Label(localized("TYLKO LOKALNIE"), systemImage: "iphone")
                    .foregroundStyle(Color.tougeMint)
                Spacer()
                if let free = recorder.freeDiskBytes {
                    Text(String(format: localized("Wolne: %@"), DriveVideoFileStore.formattedSize(free)))
                }
            }
            .font(.system(size: 9, weight: .black))
            .tracking(0.6)

            Text(localized("Film rozpoczyna się automatycznie z pierwszą próbką przejazdu i kończy po rozłączeniu. Pliki nie są wysyłane do Touge Dash Cloud."))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if case .failed(let message) = recorder.state {
                HStack {
                    Text(message)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.tougeOrange)
                    Spacer()
                    Button(localized("Spróbuj ponownie")) {
                        recorder.setEnabled(true, activeSessionID: recorder.activeTelemetrySessionID)
                    }
                    .font(.caption2.weight(.bold))
                }
            }
        }
        .padding(16)
        .cardSurface(warning: recorder.isRecording, accent: recorder.isRecording ? .tougeRed : .tougeCyan)
        .onAppear { recorder.refreshCameras() }
    }

    private var cameraPicker: some View {
        Picker(selection: cameraBinding) {
            if recorder.cameras.isEmpty {
                Text(localized("Brak dostępnej kamery")).tag("")
            } else {
                ForEach(recorder.cameras) { camera in
                    Label(camera.name, systemImage: camera.symbol).tag(camera.id)
                }
            }
        } label: {
            settingLabel(
                title: localized("Kamera"),
                subtitle: recorder.selectedCamera?.name ?? localized("Brak dostępnej kamery"),
                icon: "camera.fill",
                tint: .tougeCyan
            )
        }
        .pickerStyle(.menu)
        .padding(.vertical, 8)
    }

    private var qualityPicker: some View {
        Picker(selection: qualityBinding) {
            ForEach(DriveVideoQuality.allCases) { quality in
                Text(quality.title).tag(quality)
            }
        } label: {
            settingLabel(
                title: localized("Jakość nagrania"),
                subtitle: settings.quality.title,
                icon: "4k.tv.fill",
                tint: .tougeIce
            )
        }
        .pickerStyle(.menu)
        .padding(.vertical, 8)
    }

    private func settingLabel(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .foregroundStyle(tint)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var cameraBinding: Binding<String> {
        Binding(
            get: { recorder.selectedCamera?.id ?? "" },
            set: { recorder.selectCamera($0, activeSessionID: recorder.activeTelemetrySessionID) }
        )
    }

    private var qualityBinding: Binding<DriveVideoQuality> {
        Binding(
            get: { settings.quality },
            set: { recorder.updateQuality($0, activeSessionID: recorder.activeTelemetrySessionID) }
        )
    }

    private var audioBinding: Binding<Bool> {
        Binding(
            get: { settings.recordsAudio },
            set: { recorder.updateAudio($0, activeSessionID: recorder.activeTelemetrySessionID) }
        )
    }
}
