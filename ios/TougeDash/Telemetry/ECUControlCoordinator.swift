import Combine
import Foundation
import UIKit

enum ECUControlKind: Equatable, Sendable {
    case switchValue
    case rotary
}

struct PendingECUControl: Equatable, Sendable {
    let kind: ECUControlKind
    let channel: Int
    let targetSnapshot: ECUControlSnapshot
    let startedAt: Date
    let loopbackRevisionAtStart: UInt64
}

@MainActor
final class ECUControlCoordinator: ObservableObject {
    typealias Writer = (Data, @escaping (Result<Void, Error>) -> Void) -> Void

    @Published private(set) var observedSnapshot: ECUControlSnapshot?
    @Published private(set) var pending: PendingECUControl?
    @Published private(set) var isConnected = false
    @Published private(set) var transportAvailable = false
    @Published private(set) var hasFreshLoopback = false
    @Published private(set) var errorMessage: String?

    var writer: Writer?

    private var loopback = ECUControlLoopbackAccumulator()
    private var freshnessTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var isApplicationActive: Bool
    private let notificationCenter: NotificationCenter
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default, applicationIsActive: Bool? = nil) {
        self.notificationCenter = notificationCenter
        isApplicationActive = applicationIsActive ?? (UIApplication.shared.applicationState == .active)
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applicationDidBecomeInactive() }
        })
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applicationDidBecomeActive() }
        })
    }

    deinit {
        freshnessTask?.cancel()
        confirmationTask?.cancel()
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    var isReady: Bool {
        isConnected && transportAvailable && hasFreshLoopback && isApplicationActive && pending == nil
    }

    func connectionChanged(isConnected: Bool) {
        self.isConnected = isConnected
        transportAvailable = false
        observedSnapshot = nil
        hasFreshLoopback = false
        pending = nil
        errorMessage = nil
        loopback.reset()
        confirmationTask?.cancel()
        confirmationTask = nil
        freshnessTask?.cancel()
        freshnessTask = nil

        if isConnected {
            freshnessTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, let self else { return }
                    self.refreshLoopbackState()
                }
            }
        }
    }

    func transportAvailabilityChanged(_ available: Bool) {
        transportAvailable = isConnected && available
        if !transportAvailable {
            failPending(localized("Kanał sterowania ECU jest niedostępny."))
        }
    }

    func ingest(_ frame: EMUFrame, receivedAt: Date = .now) {
        guard isConnected, loopback.apply(frame, receivedAt: receivedAt) else { return }
        refreshLoopbackState(now: receivedAt)
    }

    func switchValue(channel: Int) -> Bool? {
        guard observedSnapshot != nil || pending != nil else { return nil }
        return displaySnapshot.switchValue(channel: channel)
    }

    func rotaryValue(channel: Int) -> Int? {
        guard observedSnapshot != nil || pending != nil else { return nil }
        return displaySnapshot.rotaryValue(channel: channel).map(Int.init)
    }

    func isPending(kind: ECUControlKind, channel: Int) -> Bool {
        pending?.kind == kind && pending?.channel == channel
    }

    @discardableResult
    func toggleSwitch(channel: Int) -> Bool {
        guard isReady, let observedSnapshot,
              let current = observedSnapshot.switchValue(channel: channel),
              let target = observedSnapshot.settingSwitch(channel: channel, to: !current) else {
            return false
        }
        return send(kind: .switchValue, channel: channel, target: target)
    }

    @discardableResult
    func setRotary(channel: Int, value: Int) -> Bool {
        guard isReady, let observedSnapshot,
              observedSnapshot.rotaryValue(channel: channel) != UInt8(value),
              let target = observedSnapshot.settingRotary(channel: channel, to: value) else {
            return false
        }
        return send(kind: .rotary, channel: channel, target: target)
    }

    var availabilityLabel: String {
        if !isConnected { return localized("BRAK POŁĄCZENIA") }
        if !transportAvailable { return localized("TYLKO ODCZYT") }
        if !isApplicationActive { return localized("APLIKACJA W TLE") }
        if !hasFreshLoopback { return localized("SYNCHRONIZACJA ECU") }
        if pending != nil { return localized("OCZEKIWANIE NA EMU") }
        if errorMessage != nil { return localized("BŁĄD STEROWANIA") }
        return localized("POTWIERDZONE PRZEZ EMU")
    }

    private var displaySnapshot: ECUControlSnapshot {
        pending?.targetSnapshot ?? observedSnapshot ?? ECUControlSnapshot()
    }

    private func send(kind: ECUControlKind, channel: Int, target: ECUControlSnapshot) -> Bool {
        guard let writer else { return false }
        errorMessage = nil
        let request = PendingECUControl(
            kind: kind,
            channel: channel,
            targetSnapshot: target,
            startedAt: .now,
            loopbackRevisionAtStart: loopback.currentRevision
        )
        pending = request
        let frame = target.encodedStatusFrame()

        writer(frame) { [weak self] result in
            Task { @MainActor in
                guard let self, self.pending == request else { return }
                if case .failure(let error) = result {
                    self.failPending(String(format: localized("Nie udało się wysłać zmiany: %@"), error.localizedDescription))
                }
            }
        }

        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.pending == request else { return }
            self.failPending(localized("EMU nie potwierdziło zmiany w wymaganym czasie."))
        }
        return true
    }

    private func refreshLoopbackState(now: Date = .now) {
        guard let snapshot = loopback.snapshotIfFresh(at: now) else {
            hasFreshLoopback = false
            return
        }
        observedSnapshot = snapshot
        hasFreshLoopback = true

        let confirmedSnapshot = pending.flatMap {
            loopback.snapshotIfFresh(at: now, receivedAfterRevision: $0.loopbackRevisionAtStart)
        }
        if let pending, confirmedSnapshot == pending.targetSnapshot {
            self.pending = nil
            errorMessage = nil
            confirmationTask?.cancel()
            confirmationTask = nil
        }
    }

    private func failPending(_ message: String) {
        guard pending != nil else { return }
        pending = nil
        confirmationTask?.cancel()
        confirmationTask = nil
        errorMessage = message
    }

    private func applicationDidBecomeInactive() {
        isApplicationActive = false
        failPending(localized("Sterowanie przerwano po przejściu aplikacji w tło."))
    }

    private func applicationDidBecomeActive() {
        isApplicationActive = true
        refreshLoopbackState()
    }
}
