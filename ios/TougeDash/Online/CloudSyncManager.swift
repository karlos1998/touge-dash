import Foundation
import Network
import SwiftData

@MainActor
final class CloudSyncManager: ObservableObject {
    enum State: Equatable {
        case offline
        case signedOut
        case waitingForVehicleName
        case ready
        case syncing
        case failed(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var activeVehicle: CloudVehicle?
    @Published private(set) var pendingHardwareIdentifier: UUID?
    @Published private(set) var pendingSessions = 0
    @Published private(set) var lastSynchronizedAt: Date?

    private let account: CloudAccountService
    private let locationTracker: LocationTrackingService
    private let context: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "it.letscode.touge-dash.cloud-network")
    private var isNetworkAvailable = true
    private var vehicleLinks: [String: CloudVehicle]
    private var lastLiveUpload = Date.distantPast
    private var periodicTask: Task<Void, Never>?
    private static let vehicleLinksKey = "TougeDash.cloud.vehicleLinks"

    init(container: ModelContainer, account: CloudAccountService, locationTracker: LocationTrackingService) {
        self.account = account
        self.locationTracker = locationTracker
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let data = UserDefaults.standard.data(forKey: Self.vehicleLinksKey),
           let links = try? JSONDecoder.tougeDashCloud().decode([String: CloudVehicle].self, from: data) {
            vehicleLinks = links
        } else {
            vehicleLinks = [:]
        }
        state = account.isAuthenticated ? .ready : .signedOut
        updatePendingCount()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isNetworkAvailable = path.status == .satisfied
                if isNetworkAvailable {
                    if account.isAuthenticated, activeVehicle != nil { await syncNow() }
                } else {
                    state = .offline
                }
            }
        }
        monitor.start(queue: monitorQueue)
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                if self.account.isAuthenticated, self.activeVehicle != nil, self.isNetworkAvailable {
                    await self.syncNow()
                }
            }
        }
    }

    deinit {
        monitor.cancel()
        periodicTask?.cancel()
    }

    var statusLabel: String {
        switch state {
        case .offline: "Brak internetu · dane zostają na iPhonie"
        case .signedOut: "Synchronizacja online jest wyłączona"
        case .waitingForVehicleName: "Nadaj nazwę podłączonemu autu"
        case .ready: lastSynchronizedAt.map { "Ostatnia synchronizacja \($0.formatted(date: .omitted, time: .shortened))" } ?? "Gotowy do synchronizacji"
        case .syncing: "Synchronizuję archiwum…"
        case .failed(let message): message
        }
    }

    func accountDidChange() async {
        guard account.isAuthenticated else {
            activeVehicle = nil
            state = .signedOut
            return
        }
        if let pendingHardwareIdentifier { await prepareVehicle(hardwareIdentifier: pendingHardwareIdentifier) }
        else if activeVehicle != nil { await syncNow() }
        else { state = .ready }
    }

    func prepareVehicle(hardwareIdentifier: UUID) async {
        pendingHardwareIdentifier = hardwareIdentifier
        if let linked = vehicleLinks[vehicleLinkKey(hardwareIdentifier)] {
            activeVehicle = linked
            state = account.isAuthenticated ? .ready : .signedOut
            if account.isAuthenticated { await syncNow() }
        } else {
            activeVehicle = nil
            state = account.isAuthenticated ? .waitingForVehicleName : .signedOut
        }
    }

    func confirmVehicle(name: String) async {
        guard account.isAuthenticated, let hardwareIdentifier = pendingHardwareIdentifier else { return }
        struct Request: Encodable { let hardwareIdentifier: String; let proposedName: String }
        do {
            state = .syncing
            let vehicle: CloudVehicle = try await account.send(
                endpoint: "/api/v1/vehicles/discover",
                body: Request(hardwareIdentifier: hardwareIdentifier.uuidString, proposedName: name)
            )
            activeVehicle = vehicle
            vehicleLinks[vehicleLinkKey(hardwareIdentifier)] = vehicle
            persistVehicleLinks()
            await syncNow()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard account.isAuthenticated else { state = .signedOut; return }
        guard isNetworkAvailable else { state = .offline; return }
        guard let vehicle = activeVehicle, let hardwareIdentifier = pendingHardwareIdentifier else {
            state = pendingHardwareIdentifier == nil ? .ready : .waitingForVehicleName
            return
        }
        guard state != .syncing else { return }
        state = .syncing
        do {
            let vehicleID = hardwareIdentifier
            let descriptor = FetchDescriptor<DriveSession>(
                predicate: #Predicate { session in
                    session.vehicleID == vehicleID && session.syncStateRaw != "synced"
                },
                sortBy: [SortDescriptor(\DriveSession.startedAt)]
            )
            let sessions = try context.fetch(descriptor)
            for session in sessions {
                try await upload(session: session, vehicleID: vehicle.id)
            }
            try context.save()
            lastSynchronizedAt = .now
            state = .ready
            updatePendingCount()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func publishLive(_ snapshot: TelemetrySnapshot) {
        guard account.isAuthenticated,
              let vehicleID = activeVehicle?.id,
              isNetworkAvailable,
              Date.now.timeIntervalSince(lastLiveUpload) >= 1 else { return }
        lastLiveUpload = .now
        let location = locationTracker.latestLocation.flatMap { location in
            abs(Date.now.timeIntervalSince(location.timestamp)) <= 15 ? location : nil
        }
        let payload = CloudLiveUpload(
            recordedAt: snapshot.updatedAt,
            rpm: snapshot.rpm,
            boostBar: snapshot.boostBar,
            mapKpa: snapshot.mapKPa,
            throttlePercent: snapshot.throttlePercent,
            coolantCelsius: snapshot.coolantCelsius,
            intakeCelsius: snapshot.intakeCelsius,
            oilTemperatureCelsius: snapshot.oilTemperatureCelsius,
            oilPressureBar: snapshot.oilPressureBar,
            fuelPressureBar: snapshot.fuelPressureBar,
            afr: snapshot.afr,
            lambda: snapshot.lambda,
            batteryVoltage: snapshot.batteryVoltage,
            ignitionDegrees: snapshot.ignitionDegrees,
            injectorDutyPercent: snapshot.injectorDutyPercent,
            speedKph: snapshot.speedKPH,
            checkEngineMask: Int(snapshot.checkEngineMask),
            latitude: location?.latitude,
            longitude: location?.longitude
        )
        Task {
            do {
                let _: EmptyCloudResponse = try await account.send(
                    endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/live",
                    body: payload
                )
            } catch {
                // Live frames are ephemeral. The full session remains queued locally.
            }
        }
    }

    private func upload(session: DriveSession, vehicleID: UUID) async throws {
        let samples = session.samples.sorted { $0.timestamp < $1.timestamp }
        let chunks = samples.isEmpty ? [[]] : stride(from: 0, to: samples.count, by: 2_000).map {
            Array(samples[$0..<min($0 + 2_000, samples.count)])
        }
        for chunk in chunks {
            let request = CloudSessionUpload(
                id: session.id,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                revision: max(1, session.revision),
                sampleCount: session.sampleCount,
                distanceMeters: session.distanceMeters,
                maxRpm: session.maxRPM,
                maxSpeedKph: session.maxSpeedKPH,
                maxBoostBar: session.maxBoostBar,
                maxCoolantCelsius: session.maxCoolantCelsius,
                maxOilTemperatureCelsius: session.maxOilTemperatureCelsius,
                minimumOilPressureBar: session.minimumOilPressureBar,
                containsLocation: session.containsLocation,
                samples: chunk.map(makeUpload)
            )
            let result: CloudSyncResult = try await account.send(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/sessions/sync",
                body: request
            )
            session.remoteID = result.sessionId.uuidString
        }
        session.syncState = .synced
        for sample in samples {
            sample.remoteID = sample.id.uuidString
            sample.syncState = .synced
        }
    }

    private func makeUpload(_ sample: TelemetryHistorySample) -> CloudSampleUpload {
        CloudSampleUpload(
            id: sample.id,
            recordedAt: sample.timestamp,
            revision: 1,
            rpm: sample.rpm,
            boostBar: sample.boostBar,
            mapKpa: sample.mapKPa,
            throttlePercent: sample.throttlePercent,
            coolantCelsius: sample.coolantCelsius,
            intakeCelsius: sample.intakeCelsius,
            oilTemperatureCelsius: sample.oilTemperatureCelsius,
            oilPressureBar: sample.oilPressureBar,
            fuelPressureBar: sample.fuelPressureBar,
            afr: sample.afr,
            lambda: sample.lambda,
            batteryVoltage: sample.batteryVoltage,
            ignitionDegrees: sample.ignitionDegrees,
            injectorDutyPercent: sample.injectorDutyPercent,
            speedKph: sample.speedKPH,
            checkEngineMask: sample.checkEngineMask,
            latitude: sample.latitude,
            longitude: sample.longitude,
            horizontalAccuracy: sample.horizontalAccuracy,
            altitude: sample.altitude
        )
    }

    private func vehicleLinkKey(_ hardwareIdentifier: UUID) -> String {
        let accountID = account.account?.id.uuidString.lowercased() ?? "signed-out"
        return "\(accountID):\(hardwareIdentifier.uuidString.lowercased())"
    }

    private func updatePendingCount() {
        let descriptor = FetchDescriptor<DriveSession>(predicate: #Predicate { $0.syncStateRaw != "synced" })
        pendingSessions = (try? context.fetchCount(descriptor)) ?? 0
    }

    private func persistVehicleLinks() {
        if let data = try? JSONEncoder.tougeDashCloud().encode(vehicleLinks) {
            UserDefaults.standard.set(data, forKey: Self.vehicleLinksKey)
        }
    }
}
