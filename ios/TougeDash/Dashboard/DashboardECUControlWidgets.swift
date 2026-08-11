import SwiftUI

struct DashboardECUSwitchWidget: View {
    let widget: DashboardWidget
    @ObservedObject var controls: ECUControlCoordinator
    let compact: Bool
    let interactionEnabled: Bool

    private var channel: Int { min(8, max(1, widget.controlChannel ?? 1)) }
    private var value: Bool? { controls.switchValue(channel: channel) }
    private var isPending: Bool { controls.isPending(kind: .switchValue, channel: channel) }

    var body: some View {
        Button {
            _ = controls.toggleSwitch(channel: channel)
        } label: {
            HStack(spacing: compact ? 9 : 14) {
                VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                    Label(widget.displayTitle.uppercased(), systemImage: widget.displayIcon)
                        .font(.system(size: compact ? 8 : 10, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(stateTitle)
                        .font(.system(size: compact ? 24 : 35, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                        .foregroundStyle(value == true ? widget.accent.color : Color.primary)
                    Text(isPending ? localized("WYSYŁANIE PEŁNEGO STANU") : controls.availabilityLabel)
                        .font(.system(size: compact ? 6 : 8, weight: .black))
                        .tracking(0.55)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ZStack(alignment: value == true ? .trailing : .leading) {
                    Capsule()
                        .fill(value == true ? widget.accent.color.opacity(0.32) : Color.primary.opacity(0.08))
                        .frame(width: compact ? 48 : 64, height: compact ? 27 : 36)
                    Circle()
                        .fill(value == true ? widget.accent.color : Color.secondary.opacity(0.7))
                        .frame(width: compact ? 21 : 28, height: compact ? 21 : 28)
                        .padding(4)
                        .shadow(color: value == true ? widget.accent.color.opacity(0.55) : .clear, radius: 7)
                }
                .opacity(value == nil ? 0.38 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(compact ? 11 : 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interactionEnabled || !controls.isReady)
        .cardSurface(accent: value == true ? widget.accent.color : widget.accent.color.opacity(0.55))
        .accessibilityLabel(widget.displayTitle)
        .accessibilityValue(stateTitle)
        .accessibilityHint(controls.availabilityLabel)
    }

    private var stateTitle: String {
        guard let value else { return "—" }
        return value ? localized("WŁĄCZONY") : localized("WYŁĄCZONY")
    }

    private var statusTint: Color {
        if controls.errorMessage != nil { return .tougeRed }
        if isPending { return .tougeOrange }
        return controls.isReady ? .tougeMint : .secondary
    }
}

struct DashboardECURotaryWidget: View {
    let widget: DashboardWidget
    @ObservedObject var controls: ECUControlCoordinator
    let compact: Bool
    let interactionEnabled: Bool

    private var channel: Int { min(8, max(1, widget.controlChannel ?? 1)) }
    private var value: Int? { controls.rotaryValue(channel: channel) }
    private var isPending: Bool { controls.isPending(kind: .rotary, channel: channel) }

    var body: some View {
        Menu {
            ForEach(ECUControlSnapshot.rotaryValueRange, id: \.self) { option in
                Button {
                    _ = controls.setRotary(channel: channel, value: option)
                } label: {
                    if option == value {
                        Label("\(option)", systemImage: "checkmark")
                    } else {
                        Text("\(option)")
                    }
                }
            }
        } label: {
            HStack(spacing: compact ? 9 : 14) {
                VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                    Label(widget.displayTitle.uppercased(), systemImage: widget.displayIcon)
                        .font(.system(size: compact ? 8 : 10, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(value.map(String.init) ?? "—")
                        .font(.system(size: compact ? 27 : 39, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                        .foregroundStyle(widget.accent.color)
                    Text(isPending ? localized("WYSYŁANIE PEŁNEGO STANU") : controls.availabilityLabel)
                        .font(.system(size: compact ? 6 : 8, weight: .black))
                        .tracking(0.55)
                        .foregroundStyle(isPending ? Color.tougeOrange : (controls.isReady ? Color.tougeMint : Color.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: compact ? 15 : 20, weight: .black))
                    .foregroundStyle(controls.isReady ? widget.accent.color : Color.secondary)
                    .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
                    .background(widget.accent.color.opacity(0.1), in: Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(compact ? 11 : 15)
            .contentShape(Rectangle())
        }
        .disabled(!interactionEnabled || !controls.isReady)
        .cardSurface(accent: widget.accent.color)
        .accessibilityLabel(widget.displayTitle)
        .accessibilityValue(value.map(String.init) ?? localized("Brak zsynchronizowanej wartości"))
    }
}
