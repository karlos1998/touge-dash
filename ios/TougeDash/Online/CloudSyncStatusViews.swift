import SwiftUI

struct CloudSyncItemBadge: View {
    let status: CloudSyncItemStatus

    var body: some View {
        HStack(spacing: 5) {
            if case .uploading = status {
                ProgressView()
                    .controlSize(.mini)
                    .tint(color)
            } else {
                Image(systemName: icon)
            }
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: 8, weight: .black))
        .tracking(0.55)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch status {
        case .queued: localized("OCZEKUJE")
        case let .uploading(completed, total, _):
            String(format: localized("%@ / %@"), completed.formatted(), total.formatted())
        case .synced: localized("W CHMURZE")
        case .blocked(.simulatorData): localized("DANE TESTOWE")
        case .blocked: localized("WYMAGA UWAGI")
        case .failed: localized("BŁĄD SYNC")
        }
    }

    private var icon: String {
        switch status {
        case .queued: "icloud.and.arrow.up"
        case .uploading: "arrow.up.circle.fill"
        case .synced: "icloud.fill"
        case .blocked(.simulatorData): "testtube.2"
        case .blocked: "exclamationmark.triangle.fill"
        case .failed: "xmark.icloud.fill"
        }
    }

    private var color: Color {
        switch status {
        case .queued, .uploading: .tougeCyan
        case .synced: .tougeMint
        case .blocked(.simulatorData): .tougeYellow
        case .blocked, .failed: .tougeOrange
        }
    }
}

struct CloudSyncItemCard: View {
    let itemName: String
    let sampleCount: Int
    let status: CloudSyncItemStatus
    let activeVehicleName: String?
    let onRetry: () -> Void
    let onAssignTestData: (() -> Void)?
    @State private var showingAssignmentConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SYNCHRONIZACJA")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(accent)
                    Text(localized(itemName))
                        .font(.subheadline.weight(.black))
                }
                Spacer()
                CloudSyncItemBadge(status: status)
            }

            content
        }
        .padding(16)
        .cardSurface(accent: accent)
        .confirmationDialog(
            localized("Przypisać dane testowe do auta?"),
            isPresented: $showingAssignmentConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(
                format: localized("Przypisz do %@ i synchronizuj"),
                activeVehicleName ?? localized("wybranego auta")
            )) {
                onAssignTestData?()
            }
            Button(localized("Anuluj"), role: .cancel) {}
        } message: {
            Text("Przejazd oraz wszystkie jego raporty zostaną zapisane w chmurze jako historia wybranego auta. Nie zmienia to żadnych danych w ECU ani EMULOGGERZE.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .synced:
            Label("Wszystkie dane tego elementu są zapisane w Touge Dash Cloud.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.tougeMint)
                .font(.caption.weight(.bold))

        case .queued:
            ProgressView(value: 0)
                .tint(.tougeCyan)
            HStack {
                Text("Oczekuje na wysłanie")
                Spacer()
                Text(String(format: localized("%@ próbek"), sampleCount.formatted()))
            }
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(.secondary)

        case let .uploading(completed, total, bytes):
            ProgressView(value: status.fraction ?? 0)
                .tint(.tougeCyan)
            HStack {
                Text(String(format: localized("%@ / %@ próbek"), completed.formatted(), total.formatted()))
                Spacer()
                Text(String(format: localized("%@ wysłano"), byteCount(bytes)))
            }
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.secondary)

        case .blocked(.simulatorData):
            Text("Ten przejazd powstał z programu EMULOGGER SIM na Macu. Dane testowe nie są automatycznie mieszane z historią prawdziwego auta.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if onAssignTestData != nil, activeVehicleName != nil {
                Button {
                    showingAssignmentConfirmation = true
                } label: {
                    Label(
                        String(format: localized("Przypisz do %@"), activeVehicleName ?? ""),
                        systemImage: "car.side.fill"
                    )
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.tougeYellow)
                .foregroundStyle(.black)
            } else {
                Text("Zaloguj się i wybierz auto, aby przypisać ten materiał ręcznie.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

        case .blocked(.vehicleNotLinked):
            Label("Logger użyty podczas tego przejazdu nie jest przypisany do auta na bieżącym koncie.", systemImage: "link.badge.plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.tougeOrange)

        case .blocked(.parentVehicleMismatch):
            Label("Raport i jego przejazd mają różne przypisanie auta. Przypisz przejazd ponownie, aby naprawić komplet danych.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.tougeOrange)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.tougeOrange)
                .textSelection(.enabled)
            Button(action: onRetry) {
                Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.tougeOrange)
        }
    }

    private var accent: Color {
        switch status {
        case .synced: .tougeMint
        case .blocked(.simulatorData): .tougeYellow
        case .blocked, .failed: .tougeOrange
        case .queued, .uploading: .tougeCyan
        }
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
