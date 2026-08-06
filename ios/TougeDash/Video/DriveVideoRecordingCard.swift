import AVFoundation
import SwiftUI

struct DriveVideoRecordingCard: View {
    @ObservedObject var recorder: DriveVideoRecorder
    @ObservedObject private var settings: DriveVideoSettingsStore
    @State private var showingExperimentalWarning = false

    init(recorder: DriveVideoRecorder) {
        self.recorder = recorder
        _settings = ObservedObject(wrappedValue: recorder.settings)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { requestedValue in
                if requestedValue {
                    showingExperimentalWarning = true
                } else {
                    recorder.setEnabled(false, activeSessionID: recorder.activeTelemetrySessionID)
                }
            }
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

            Text(localized("Film rozpoczyna się z pierwszą próbką, jest dzielony razem z przejazdem i kończy po rozłączeniu. Pliki nie są wysyłane do Touge Dash Cloud."))
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
        .sheet(isPresented: $showingExperimentalWarning) {
            DriveVideoExperimentalWarning {
                recorder.setEnabled(true, activeSessionID: recorder.activeTelemetrySessionID)
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_VIDEO_WARNING_PREVIEW"] == "1" {
                showingExperimentalWarning = true
            }
            #endif
        }
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

private struct DriveVideoExperimentalWarning: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var secondsRemaining = 5

    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: compactHeight ? 12 : 22) {
                        header
                        if compactHeight {
                            HStack(alignment: .top, spacing: 12) {
                                performanceWarning
                                purposeExplanation
                            }
                        } else {
                            performanceWarning
                            purposeExplanation
                        }
                        localOnlyNote
                    }
                    .padding(.horizontal, compactHeight ? 18 : 22)
                    .padding(.top, compactHeight ? 8 : 22)
                    .padding(.bottom, compactHeight ? 90 : 150)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(localized("Zostaw wyłączone"))
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0.025, green: 0.035, blue: 0.045))
        .task { await runCountdown() }
    }

    private var compactHeight: Bool {
        verticalSizeClass == .compact
    }

    @ViewBuilder
    private var header: some View {
        if compactHeight {
            HStack(spacing: 13) {
                warningSymbol(size: 42, iconSize: 19)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("FUNKCJA TESTOWA"))
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(Color.tougeOrange)
                    Text(localized("Nagrywanie przejazdu"))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                warningSymbol(size: 58, iconSize: 25)

                VStack(alignment: .leading, spacing: 7) {
                    Text(localized("FUNKCJA TESTOWA"))
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.tougeOrange)
                    Text(localized("Nagrywanie przejazdu"))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                    Text(localized("Przeczytaj przed włączeniem"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func warningSymbol(size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.tougeOrange.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(Color.tougeOrange)
        }
    }

    private var performanceWarning: some View {
        warningPanel(
            icon: "thermometer.high",
            tint: .tougeOrange,
            title: localized("Może mocno obciążyć telefon"),
            text: localized("Jednoczesne nagrywanie obrazu, zapisywanie telemetrii i wyświetlanie dashboardu może nagrzewać urządzenie, zwiększać zużycie baterii oraz powodować spadki płynności. Ta funkcja nie jest jeszcze zalecana do codziennego użycia.")
        )
    }

    private var purposeExplanation: some View {
        warningPanel(
            icon: "video.fill",
            tint: .tougeCyan,
            title: localized("Co otrzymasz?"),
            text: localized("Umieść telefon stabilnie w uchwycie i skieruj kamerę na drogę. Touge Dash nagra obraz razem z logami przejazdu. Później możesz zatrzymać film w dowolnym momencie, sprawdzić odpowiadające mu parametry i wyeksportować nagranie z nakładką dashboardu.")
        )
    }

    private var localOnlyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "iphone")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.tougeMint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Nagranie pozostaje na tym urządzeniu"))
                    .font(.subheadline.weight(.bold))
                Text(localized("Film nie jest wysyłany do Touge Dash Cloud. Przed jazdą upewnij się, że uchwyt jest stabilny i nie obsługuj telefonu podczas prowadzenia."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(Color.tougeMint.opacity(0.07), in: CutCornerPanel(cut: 11))
        .overlay(CutCornerPanel(cut: 11).stroke(Color.tougeMint.opacity(0.22)))
    }

    private func warningPanel(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: compactHeight ? 10 : 13) {
            Image(systemName: icon)
                .font(.system(size: compactHeight ? 15 : 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: compactHeight ? 29 : 34, height: compactHeight ? 29 : 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: compactHeight ? 4 : 7) {
                Text(title)
                    .font(compactHeight ? .subheadline.weight(.bold) : .headline)
                Text(text)
                    .font(compactHeight ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compactHeight ? 12 : 16)
        .background(Color.white.opacity(0.045), in: CutCornerPanel(cut: 12))
        .overlay(CutCornerPanel(cut: 12).stroke(tint.opacity(0.25)))
    }

    @ViewBuilder
    private var actionBar: some View {
        if compactHeight {
            HStack(spacing: 12) {
                cancelButton
                    .frame(width: 145)
                acceptButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        } else {
            VStack(spacing: 10) {
                acceptButton
                cancelButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
    }

    private var acceptButton: some View {
        Button {
            onAccept()
            dismiss()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: secondsRemaining > 0 ? "clock.fill" : "checkmark.shield.fill")
                Text(acceptButtonTitle)
            }
            .font(.system(size: compactHeight ? 12 : 14, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compactHeight ? 11 : 14)
            .foregroundStyle(secondsRemaining > 0 ? Color.white.opacity(0.48) : Color.black)
            .background(
                secondsRemaining > 0 ? Color.white.opacity(0.065) : Color.tougeOrange,
                in: CutCornerPanel(cut: 10)
            )
        }
        .buttonStyle(.plain)
        .disabled(secondsRemaining > 0)
    }

    private var cancelButton: some View {
        Button(localized("Zostaw wyłączone")) {
            dismiss()
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.secondary)
    }

    private var acceptButtonTitle: String {
        if secondsRemaining > 0 {
            return String(format: localized("Rozumiem, włącz nagrywanie (%d)"), secondsRemaining)
        }
        return localized("Rozumiem, włącz nagrywanie")
    }

    private func runCountdown() async {
        secondsRemaining = 5
        for nextValue in stride(from: 4, through: 0, by: -1) {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            secondsRemaining = nextValue
        }
    }
}
