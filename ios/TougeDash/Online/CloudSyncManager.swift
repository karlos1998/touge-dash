import Foundation
import Network
import SwiftData

struct CloudPendingSamplePublicationBuffer {
    static let batchSize = 10
    private(set) var pendingDelta = 0

    mutating func record(_ count: Int = 1) -> Int? {
        pendingDelta += count
        guard pendingDelta >= Self.batchSize else { return nil }
        return drain()
    }

    mutating func drain() -> Int? {
        guard pendingDelta > 0 else { return nil }
        defer { pendingDelta = 0 }
        return pendingDelta
    }
}

struct CloudSyncProgress: Equatable, Sendable {
    let totalSessions: Int
    let totalIncidents: Int
    let totalAnnotations: Int
    let totalSamples: Int
    var completedSessions: Int
    var completedIncidents: Int
    var completedAnnotations: Int
    var completedSamples: Int
    var transferredBytes: Int64

    var fraction: Double {
        if totalSamples > 0 {
            return min(1, Double(completedSamples) / Double(totalSamples))
        }
        guard totalSessions > 0 else { return 1 }
        let totalItems = totalSessions + totalIncidents + totalAnnotations
        let completedItems = completedSessions + completedIncidents + completedAnnotations
        guard totalItems > 0 else { return 1 }
        return min(1, Double(completedItems) / Double(totalItems))
    }
}

enum CloudSyncBlockReason: Equatable, Sendable {
    case vehicleNotLinked
    case parentVehicleMismatch
}

enum CloudSyncItemStatus: Equatable, Sendable {
    case queued
    case uploading(completedSamples: Int, totalSamples: Int, transferredBytes: Int64)
    case synced
    case blocked(CloudSyncBlockReason)
    case failed(String)

    var fraction: Double? {
        guard case let .uploading(completedSamples, totalSamples, _) = self else { return nil }
        guard totalSamples > 0 else { return 1 }
        return min(1, Double(completedSamples) / Double(totalSamples))
    }
}

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
    @Published private(set) var pendingSamples = 0
    @Published private(set) var pendingIncidents = 0
    @Published private(set) var pendingAnnotations = 0
    @Published private(set) var estimatedPendingBytes: Int64 = 0
    @Published private(set) var progress: CloudSyncProgress?
    @Published private(set) var lastTransferBytes: Int64 = 0
    @Published private(set) var lastSynchronizedAt: Date?
    @Published private(set) var uploadablePendingItems = 0
    @Published private(set) var sessionStatuses: [UUID: CloudSyncItemStatus] = [:]
    @Published private(set) var incidentStatuses: [UUID: CloudSyncItemStatus] = [:]

    private let account: CloudAccountService
    private let locationTracker: LocationTrackingService
    let dashboardTemplates: DashboardTemplateStore
    let alertRules: VehicleAlertRuleStore
    private let context: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "it.letscode.touge-dash.cloud-network")
    private var isNetworkAvailable = true
    private var vehicleLinks: [String: CloudVehicle]
    private var lastLiveUpload = Date.distantPast
    private var periodicTask: Task<Void, Never>?
    private var isSynchronizing = false
    private var samplePublicationBuffer = CloudPendingSamplePublicationBuffer()
    private static let vehicleLinksKey = "TougeDash.cloud.vehicleLinks"
    private static let lastVehicleIdentifierKey = "TougeDash.cloud.lastVehicleIdentifier"
    private static let estimatedBytesPerSample: Int64 = 420

    private struct VehicleAssociation {
        let hardwareIdentifier: UUID
        let vehicle: CloudVehicle
    }

    init(
        container: ModelContainer,
        account: CloudAccountService,
        locationTracker: LocationTrackingService,
        dashboardTemplates: DashboardTemplateStore,
        alertRules: VehicleAlertRuleStore
    ) {
        self.account = account
        self.locationTracker = locationTracker
        self.dashboardTemplates = dashboardTemplates
        self.alertRules = alertRules
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let data = UserDefaults.standard.data(forKey: Self.vehicleLinksKey),
           let links = try? JSONDecoder.tougeDashCloud().decode([String: CloudVehicle].self, from: data) {
            vehicleLinks = links
        } else {
            vehicleLinks = [:]
        }
        if account.isAuthenticated {
            _ = restoreActiveVehicle()
        }
        state = account.isAuthenticated ? .ready : .signedOut
        repairPendingChildVehicleAssignments()
        updatePendingCount()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isNetworkAvailable = path.status == .satisfied
                if isNetworkAvailable {
                    if account.isAuthenticated { await syncNow() }
                } else {
                    state = .offline
                }
            }
        }
        monitor.start(queue: monitorQueue)
        if account.isAuthenticated {
            Task { [weak self] in
                await Task.yield()
                await self?.syncNow()
            }
        }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                if self.account.isAuthenticated, self.isNetworkAvailable {
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
        case .offline: localized("Brak internetu · dane zostają na iPhonie")
        case .signedOut: localized("Synchronizacja online jest wyłączona")
        case .waitingForVehicleName: localized("Nadaj nazwę podłączonemu autu")
        case .ready: lastSynchronizedAt.map {
            String(format: localized("Ostatnia synchronizacja %@"), $0.formatted(date: .omitted, time: .shortened))
        } ?? localized("Gotowy do synchronizacji")
        case .syncing:
            if let progress {
                String(
                    format: localized("Wysyłam %@ z %@ próbek"),
                    progress.completedSamples.formatted(),
                    progress.totalSamples.formatted()
                )
            } else {
                localized("Przygotowuję synchronizację…")
            }
        case .failed(let message): message
        }
    }

    func accountDidChange() async {
        guard account.isAuthenticated else {
            activeVehicle = nil
            pendingHardwareIdentifier = nil
            progress = nil
            sessionStatuses.removeAll()
            incidentStatuses.removeAll()
            state = .signedOut
            dashboardTemplates.markSignedOut()
            return
        }
        if let pendingHardwareIdentifier { await prepareVehicle(hardwareIdentifier: pendingHardwareIdentifier) }
        else if restoreActiveVehicle() { await syncNow() }
        else { await syncNow() }
    }

    func prepareVehicle(hardwareIdentifier: UUID) async {
        pendingHardwareIdentifier = hardwareIdentifier
        alertRules.activateVehicle(hardwareIdentifier)
        if let linked = vehicleLinks[vehicleLinkKey(hardwareIdentifier)] {
            activeVehicle = linked
            rememberActiveVehicle(hardwareIdentifier)
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
            alertRules.activateVehicle(hardwareIdentifier)
            vehicleLinks[vehicleLinkKey(hardwareIdentifier)] = vehicle
            persistVehicleLinks()
            rememberActiveVehicle(hardwareIdentifier)
            state = .ready
            await syncNow()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func syncNow() async {
        guard account.isAuthenticated else {
            state = .signedOut
            dashboardTemplates.markSignedOut()
            return
        }
        guard isNetworkAvailable else { state = .offline; return }
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        state = .syncing
        var synchronizationErrors: [Error] = []
        do {
            try await synchronizeDashboardTemplates()
        } catch {
            // Dashboard layouts are independent from telemetry. A template error
            // must never strand drives or incident reports behind it.
            synchronizationErrors.append(error)
        }

        let associations = currentAccountAssociations()
        guard !associations.isEmpty else {
            lastSynchronizedAt = .now
            state = synchronizationErrors.first.map { .failed($0.localizedDescription) }
                ?? (pendingHardwareIdentifier == nil ? .ready : .waitingForVehicleName)
            updatePendingCount()
            return
        }

        do {
            let queued = try pendingSessionEntries(for: associations)
            let queuedIncidents = try pendingIncidentEntries(for: associations)
            let queuedAnnotations = try pendingAnnotationEntries(for: associations)
            let totalSamples = queued.reduce(0) { $0 + $1.session.sampleCount } +
                queuedIncidents.reduce(0) { $0 + $1.incident.sampleCount }
            progress = CloudSyncProgress(
                totalSessions: queued.count,
                totalIncidents: queuedIncidents.count,
                totalAnnotations: queuedAnnotations.count,
                totalSamples: totalSamples,
                completedSessions: 0,
                completedIncidents: 0,
                completedAnnotations: 0,
                completedSamples: 0,
                transferredBytes: 0
            )

            for entry in queued {
                sessionStatuses[entry.session.id] = .queued
                do {
                    try await upload(session: entry.session, vehicleID: entry.remoteVehicleID)
                } catch {
                    sessionStatuses[entry.session.id] = .failed(error.localizedDescription)
                    synchronizationErrors.append(error)
                }
            }
            for entry in queuedIncidents {
                incidentStatuses[entry.incident.id] = .queued
                do {
                    try await upload(incident: entry.incident, vehicleID: entry.remoteVehicleID)
                } catch {
                    incidentStatuses[entry.incident.id] = .failed(error.localizedDescription)
                    synchronizationErrors.append(error)
                }
            }
            for entry in queuedAnnotations {
                do {
                    try await upload(annotation: entry.annotation, vehicleID: entry.remoteVehicleID)
                } catch {
                    synchronizationErrors.append(error)
                }
            }
            try context.save()

            // Alert configuration is synchronized after telemetry so a rules-only
            // failure can never prevent a recorded drive from reaching the server.
            for association in associations {
                do {
                    try await synchronizeAlertRules(for: association)
                } catch {
                    synchronizationErrors.append(error)
                }
            }

            lastTransferBytes = progress?.transferredBytes ?? 0
            lastSynchronizedAt = .now
            state = synchronizationErrors.first.map { .failed($0.localizedDescription) } ?? .ready
            updatePendingCount()
        } catch {
            state = .failed(error.localizedDescription)
            updatePendingCount()
        }
    }

    private func synchronizeDashboardTemplates() async throws {
        dashboardTemplates.markSyncing()
        do {
            let payload = CloudDashboardTemplateSyncRequest(
                templates: dashboardTemplates.synchronizationRecords.map(CloudDashboardTemplate.init(record:))
            )
            let response: CloudDashboardTemplateSyncResponse = try await account.send(
                endpoint: "/api/v1/dashboard-templates/sync",
                body: payload
            )
            dashboardTemplates.mergeFromServer(response.templates.map(\.record))
        } catch {
            dashboardTemplates.markSyncFailed(error)
            throw error
        }
    }

    func noteLocalSampleRecorded(sessionID: UUID, sessionBecamePending: Bool) {
        if sessionStatuses[sessionID] != nil {
            sessionStatuses.removeValue(forKey: sessionID)
        }
        if let publishedDelta = samplePublicationBuffer.record() {
            pendingSamples += publishedDelta
            estimatedPendingBytes += Int64(publishedDelta) * Self.estimatedBytesPerSample
        }
        if sessionBecamePending {
            pendingSessions += 1
        }
    }

    func noteLocalIncidentRecorded(sampleCount: Int) {
        publishBufferedSampleCount()
        pendingIncidents += 1
        pendingSamples += sampleCount
        estimatedPendingBytes += Int64(sampleCount) * Self.estimatedBytesPerSample
        if account.isAuthenticated, activeVehicle != nil, isNetworkAvailable {
            Task { await syncNow() }
        }
    }

    func noteLocalAccelerationRecorded(sessionID: UUID) {
        if sessionStatuses[sessionID] != nil {
            sessionStatuses.removeValue(forKey: sessionID)
        }
        pendingSessions = max(1, pendingSessions)
        estimatedPendingBytes += 256
        if account.isAuthenticated, activeVehicle != nil, isNetworkAvailable {
            Task { await syncNow() }
        }
    }

    func noteLocalAnnotationRecorded() {
        pendingAnnotations += 1
        estimatedPendingBytes += 512
        if account.isAuthenticated, activeVehicle != nil, isNetworkAvailable {
            Task { await syncNow() }
        }
    }

    func saveAlertRules(_ rules: VehicleAlertRules) {
        let vehicleID = alertRules.activeVehicleID
        alertRules.saveLocally(rules, for: vehicleID)
        if account.isAuthenticated, activeVehicle != nil, isNetworkAvailable {
            Task { await syncNow() }
        }
    }

    func acceptRemoteAlertRules() {
        alertRules.acceptRemoteConflict(for: alertRules.activeVehicleID)
    }

    func keepLocalAlertRules() {
        alertRules.keepLocalAfterConflict(for: alertRules.activeVehicleID)
        if account.isAuthenticated, activeVehicle != nil, isNetworkAvailable {
            Task { await syncNow() }
        }
    }

    func remoteVehicleID(for localHardwareIdentifier: UUID) -> UUID? {
        currentAccountAssociations()
            .first(where: { $0.hardwareIdentifier == localHardwareIdentifier })?
            .vehicle.id
    }

    func sessionStatus(for session: DriveSession) -> CloudSyncItemStatus {
        if let transient = sessionStatuses[session.id] { return transient }
        if session.syncState == .synced { return .synced }
        if remoteVehicleID(for: session.vehicleID) == nil { return .blocked(.vehicleNotLinked) }
        return .queued
    }

    func incidentStatus(for incident: DriveIncident) -> CloudSyncItemStatus {
        if let transient = incidentStatuses[incident.id] { return transient }
        if incident.syncState == .synced { return .synced }

        let sessionID = incident.sessionID
        var descriptor = FetchDescriptor<DriveSession>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        if let parent = try? context.fetch(descriptor).first {
            if parent.vehicleID != incident.vehicleID {
                return .blocked(.parentVehicleMismatch)
            }
        }
        guard remoteVehicleID(for: incident.vehicleID) != nil else { return .blocked(.vehicleNotLinked) }
        return .queued
    }

    func deleteRemote(session: DriveSession) async throws {
        guard account.isAuthenticated else { throw CloudAPIError.unauthorized }
        guard let vehicleID = remoteVehicleID(for: session.vehicleID) else {
            throw CloudAPIError.server(status: 409, message: localized("Auto nie jest połączone z chmurą."))
        }
        do {
            try await account.delete(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/sessions/\(session.id.uuidString)"
            )
        } catch CloudAPIError.server(let status, _) where status == 404 {
            // Treat an already missing cloud record as a successful deletion.
        }
        sessionStatuses.removeValue(forKey: session.id)
    }

    func deleteRemote(incident: DriveIncident) async throws {
        guard account.isAuthenticated else { throw CloudAPIError.unauthorized }
        guard let vehicleID = remoteVehicleID(for: incident.vehicleID) else {
            throw CloudAPIError.server(status: 409, message: localized("Auto nie jest połączone z chmurą."))
        }
        do {
            try await account.delete(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/incidents/\(incident.id.uuidString)"
            )
        } catch CloudAPIError.server(let status, _) where status == 404 {
            // Treat an already missing cloud record as a successful deletion.
        }
        incidentStatuses.removeValue(forKey: incident.id)
    }

    func localHistoryDidChange() {
        updatePendingCount()
    }

    func retrySynchronization() async {
        await syncNow()
    }

    func publishLive(_ snapshot: TelemetrySnapshot, performance: AccelerationEngine) {
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
            longitude: location?.longitude,
            activeAcceleration: performance.active.map {
                CloudActiveAccelerationUpload(
                    type: $0.type.rawValue,
                    startedAt: $0.startedAt,
                    elapsedMillis: Int64(($0.elapsed * 1_000).rounded()),
                    currentSpeedKph: $0.currentSpeedKPH,
                    progress: $0.progress
                )
            },
            recentAccelerationResults: performance.recentResults.map {
                CloudAccelerationResultUpload(type: $0.typeRaw, durationMillis: $0.durationMillis, endedAt: $0.endedAt)
            }
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
        let uploadedRevision = max(1, session.revision)
        let uploadedStartedAt = session.startedAt
        let uploadedEndedAt = session.endedAt
        let uploadedSampleCount = session.sampleCount
        let uploadedDistanceMeters = session.distanceMeters
        let uploadedMaxRPM = session.maxRPM
        let uploadedMaxSpeedKPH = session.maxSpeedKPH
        let uploadedMaxBoostBar = session.maxBoostBar
        let uploadedMaxCoolantCelsius = session.maxCoolantCelsius
        let uploadedMaxOilTemperatureCelsius = session.maxOilTemperatureCelsius
        let uploadedMinimumOilPressureBar = session.minimumOilPressureBar
        let uploadedContainsLocation = session.containsLocation
        let accelerationAttempts = accelerationAttempts(sessionID: session.id).map(makeUpload)
        var offset = 0
        var sentEmptySession = false
        var itemTransferredBytes: Int64 = 0
        sessionStatuses[session.id] = .uploading(
            completedSamples: 0,
            totalSamples: uploadedSampleCount,
            transferredBytes: 0
        )
        while offset < uploadedSampleCount || (uploadedSampleCount == 0 && !sentEmptySession) {
            let chunk = try sessionSamples(sessionID: session.id, offset: offset, limit: 2_000)
            if uploadedSampleCount > 0 && chunk.isEmpty {
                throw CloudAPIError.localHistoryIncomplete
            }
            let request = CloudSessionUpload(
                id: session.id,
                startedAt: uploadedStartedAt,
                endedAt: uploadedEndedAt,
                revision: uploadedRevision,
                sampleCount: uploadedSampleCount,
                distanceMeters: uploadedDistanceMeters,
                maxRpm: uploadedMaxRPM,
                maxSpeedKph: uploadedMaxSpeedKPH,
                maxBoostBar: uploadedMaxBoostBar,
                maxCoolantCelsius: uploadedMaxCoolantCelsius,
                maxOilTemperatureCelsius: uploadedMaxOilTemperatureCelsius,
                minimumOilPressureBar: uploadedMinimumOilPressureBar,
                containsLocation: uploadedContainsLocation,
                samples: chunk.map(makeUpload),
                accelerationAttempts: accelerationAttempts
            )
            let encodedSize = try JSONEncoder.tougeDashCloud().encode(request).count
            let result: CloudSyncResult = try await account.send(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/sessions/sync",
                body: request
            )
            session.remoteID = result.sessionId.uuidString
            itemTransferredBytes += Int64(encodedSize)
            sessionStatuses[session.id] = .uploading(
                completedSamples: offset + chunk.count,
                totalSamples: uploadedSampleCount,
                transferredBytes: itemTransferredBytes
            )
            if var progress {
                progress.completedSamples += chunk.count
                progress.transferredBytes += Int64(encodedSize)
                self.progress = progress
            }
            for sample in chunk {
                sample.remoteID = sample.id.uuidString
                sample.syncState = .synced
            }
            try context.save()
            offset += chunk.count
            sentEmptySession = true
        }
        session.syncState = session.revision == uploadedRevision ? .synced : .changedAfterSync
        try context.save()
        sessionStatuses[session.id] = session.syncState == .synced ? .synced : .queued
        if var progress {
            progress.completedSessions += 1
            self.progress = progress
        }
    }

    private func synchronizeAlertRules(for association: VehicleAssociation) async throws {
        let endpoint = "/api/v1/vehicles/\(association.vehicle.id.uuidString)/alert-configuration"
        let local = alertRules.record(for: association.hardwareIdentifier)
        if association.vehicle.role == "VIEWER" {
            let remote: CloudVehicleAlertConfiguration = try await account.get(endpoint: endpoint)
            alertRules.markUploaded(remote, for: association.hardwareIdentifier)
            return
        }
        if local.dirty {
            do {
                let remote: CloudVehicleAlertConfiguration = try await account.send(
                    endpoint: endpoint,
                    method: "PUT",
                    body: CloudVehicleAlertConfigurationUpdate(rules: local.rules, revision: local.revision)
                )
                alertRules.markUploaded(remote, for: association.hardwareIdentifier)
                return
            } catch CloudAPIError.server(let status, _) where status == 409 {
                let remote: CloudVehicleAlertConfiguration = try await account.get(endpoint: endpoint)
                alertRules.applyRemote(remote, to: association.hardwareIdentifier)
                return
            }
        }
        let remote: CloudVehicleAlertConfiguration = try await account.get(endpoint: endpoint)
        alertRules.applyRemote(remote, to: association.hardwareIdentifier)
    }

    private func sessionSamples(sessionID: UUID, offset: Int, limit: Int) throws -> [TelemetryHistorySample] {
        var descriptor = FetchDescriptor<TelemetryHistorySample>(
            predicate: #Predicate { sample in sample.session?.id == sessionID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    private func accelerationAttempts(sessionID: UUID) -> [AccelerationAttempt] {
        let descriptor = FetchDescriptor<AccelerationAttempt>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func makeUpload(_ attempt: AccelerationAttempt) -> CloudAccelerationAttemptUpload {
        CloudAccelerationAttemptUpload(
            id: attempt.id, type: attempt.typeRaw, startedAt: attempt.startedAt, endedAt: attempt.endedAt,
            durationMillis: attempt.durationMillis, startSpeedKph: attempt.startSpeedKPH,
            endSpeedKph: attempt.endSpeedKPH, source: attempt.sourceRaw, quality: attempt.qualityRaw,
            sampleRateHz: attempt.sampleRateHz, shiftCount: attempt.shiftCount, revision: attempt.revision
        )
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

    private func upload(incident: DriveIncident, vehicleID: UUID) async throws {
        let samples = incident.samples.sorted { $0.timestamp < $1.timestamp }
        let chunks = samples.isEmpty ? [[]] : stride(from: 0, to: samples.count, by: 2_000).map {
            Array(samples[$0..<min($0 + 2_000, samples.count)])
        }
        var completedSamples = 0
        var itemTransferredBytes: Int64 = 0
        incidentStatuses[incident.id] = .uploading(
            completedSamples: 0,
            totalSamples: samples.count,
            transferredBytes: 0
        )
        for chunk in chunks {
            let request = CloudIncidentUpload(
                id: incident.id,
                sessionId: incident.sessionID,
                type: incident.kindRaw,
                severity: incident.severityRaw,
                triggeredAt: incident.triggeredAt,
                captureStartedAt: incident.captureStartedAt,
                captureEndedAt: incident.captureEndedAt,
                revision: max(1, incident.revision),
                sampleCount: max(1, incident.sampleCount),
                sampleRateHz: max(0.1, incident.sampleRateHz),
                triggerValue: incident.triggerValue,
                thresholdValue: incident.thresholdValue,
                triggerUnit: incident.triggerUnit,
                triggerRpm: incident.triggerRPM,
                triggerBoostBar: incident.triggerBoostBar,
                triggerAfr: incident.triggerAFR,
                triggerSpeedKph: incident.triggerSpeedKPH,
                latitude: incident.latitude,
                longitude: incident.longitude,
                samples: chunk.map(makeUpload)
            )
            let encodedSize = try JSONEncoder.tougeDashCloud().encode(request).count
            let result: CloudIncidentSyncResult = try await account.send(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/incidents/sync",
                body: request
            )
            incident.remoteID = result.incidentId.uuidString
            completedSamples += chunk.count
            itemTransferredBytes += Int64(encodedSize)
            incidentStatuses[incident.id] = .uploading(
                completedSamples: completedSamples,
                totalSamples: samples.count,
                transferredBytes: itemTransferredBytes
            )
            if var progress {
                progress.completedSamples += chunk.count
                progress.transferredBytes += Int64(encodedSize)
                self.progress = progress
            }
        }
        incident.syncState = .synced
        try context.save()
        incidentStatuses[incident.id] = .synced
        if var progress {
            progress.completedIncidents += 1
            self.progress = progress
        }
    }

    private func makeUpload(_ sample: CapturedTelemetryPoint) -> CloudSampleUpload {
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

    private func upload(annotation: TimelineAnnotation, vehicleID: UUID) async throws {
        let request = CloudTimelineAnnotationUpload(
            id: annotation.id,
            incidentId: annotation.incidentID,
            recordedAt: annotation.timestamp,
            body: annotation.body
        )
        let encodedSize = try JSONEncoder.tougeDashCloud().encode(request).count
        let response: CloudTimelineAnnotationResponse = try await account.send(
            endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/sessions/\(annotation.sessionID.uuidString)/annotations",
            body: request
        )
        annotation.modifiedAt = response.updatedAt
        annotation.syncState = .synced
        try context.save()
        if var progress {
            progress.completedAnnotations += 1
            progress.transferredBytes += Int64(encodedSize)
            self.progress = progress
        }
    }

    private func vehicleLinkKey(_ hardwareIdentifier: UUID) -> String {
        let accountID = account.account?.id.uuidString.lowercased() ?? "signed-out"
        return "\(accountID):\(hardwareIdentifier.uuidString.lowercased())"
    }

    private func updatePendingCount() {
        samplePublicationBuffer = CloudPendingSamplePublicationBuffer()
        let descriptor = FetchDescriptor<DriveSession>(predicate: #Predicate { $0.syncStateRaw != "synced" })
        let sessions = (try? context.fetch(descriptor)) ?? []
        let incidents = (try? context.fetch(FetchDescriptor<DriveIncident>(
            predicate: #Predicate { $0.syncStateRaw != "synced" }
        ))) ?? []
        let annotations = (try? context.fetch(FetchDescriptor<TimelineAnnotation>(
            predicate: #Predicate { $0.syncStateRaw != "synced" }
        ))) ?? []
        pendingSessions = sessions.count
        pendingIncidents = incidents.count
        pendingAnnotations = annotations.count
        let linkedHardwareIDs = Set(currentAccountAssociations().map(\.hardwareIdentifier))
        let uploadableSessions = sessions.filter { linkedHardwareIDs.contains($0.vehicleID) }
        let allSessions = (try? context.fetch(FetchDescriptor<DriveSession>())) ?? []
        let sessionVehicles = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0.vehicleID) })
        let uploadableIncidents = incidents.filter {
            linkedHardwareIDs.contains($0.vehicleID) && sessionVehicles[$0.sessionID] == $0.vehicleID
        }
        let uploadableAnnotations = annotations.filter {
            linkedHardwareIDs.contains($0.vehicleID) && sessionVehicles[$0.sessionID] == $0.vehicleID
        }
        uploadablePendingItems = uploadableSessions.count + uploadableIncidents.count + uploadableAnnotations.count
        pendingSamples = sessions.reduce(0) { $0 + $1.sampleCount } + incidents.reduce(0) { $0 + $1.sampleCount }
        estimatedPendingBytes = Int64(pendingSamples) * Self.estimatedBytesPerSample + Int64(annotations.count * 512)
    }

    private func publishBufferedSampleCount() {
        guard let publishedDelta = samplePublicationBuffer.drain() else { return }
        pendingSamples += publishedDelta
        estimatedPendingBytes += Int64(publishedDelta) * Self.estimatedBytesPerSample
    }

    private func repairPendingChildVehicleAssignments() {
        do {
            let sessions = try context.fetch(FetchDescriptor<DriveSession>())
            let sessionVehicles = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.vehicleID) })
            let incidents = try context.fetch(FetchDescriptor<DriveIncident>(
                predicate: #Predicate { $0.syncStateRaw != "synced" }
            ))
            let annotations = try context.fetch(FetchDescriptor<TimelineAnnotation>(
                predicate: #Predicate { $0.syncStateRaw != "synced" }
            ))
            var changed = false

            for incident in incidents {
                guard let parentVehicleID = sessionVehicles[incident.sessionID],
                      incident.vehicleID != parentVehicleID else { continue }
                incident.vehicleID = parentVehicleID
                incident.remoteID = nil
                incident.syncState = .local
                changed = true
            }
            for annotation in annotations {
                guard let parentVehicleID = sessionVehicles[annotation.sessionID],
                      annotation.vehicleID != parentVehicleID else { continue }
                annotation.vehicleID = parentVehicleID
                annotation.syncState = .local
                changed = true
            }
            if changed { try context.save() }
        } catch {
            // The original local records remain untouched if reconciliation fails.
        }
    }

    private func persistVehicleLinks() {
        if let data = try? JSONEncoder.tougeDashCloud().encode(vehicleLinks) {
            UserDefaults.standard.set(data, forKey: Self.vehicleLinksKey)
        }
    }

    private func currentAccountAssociations() -> [VehicleAssociation] {
        guard let accountID = account.account?.id.uuidString.lowercased() else { return [] }
        let prefix = accountID + ":"
        return vehicleLinks.compactMap { key, vehicle in
            guard key.hasPrefix(prefix),
                  let identifier = UUID(uuidString: String(key.dropFirst(prefix.count))) else { return nil }
            return VehicleAssociation(hardwareIdentifier: identifier, vehicle: vehicle)
        }
        .sorted { $0.vehicle.createdAt < $1.vehicle.createdAt }
    }

    private func pendingSessionEntries(
        for associations: [VehicleAssociation]
    ) throws -> [(session: DriveSession, remoteVehicleID: UUID)] {
        var result: [(DriveSession, UUID)] = []
        for association in associations {
            let hardwareIdentifier = association.hardwareIdentifier
            let descriptor = FetchDescriptor<DriveSession>(
                predicate: #Predicate { session in
                    session.vehicleID == hardwareIdentifier && session.syncStateRaw != "synced"
                }
            )
            result.append(contentsOf: try context.fetch(descriptor).map { ($0, association.vehicle.id) })
        }
        return result.sorted { $0.0.startedAt < $1.0.startedAt }
    }

    private func pendingIncidentEntries(
        for associations: [VehicleAssociation]
    ) throws -> [(incident: DriveIncident, remoteVehicleID: UUID)] {
        var result: [(DriveIncident, UUID)] = []
        let sessionVehicles = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DriveSession>()).map {
            ($0.id, $0.vehicleID)
        })
        for association in associations {
            let hardwareIdentifier = association.hardwareIdentifier
            let descriptor = FetchDescriptor<DriveIncident>(
                predicate: #Predicate { incident in
                    incident.vehicleID == hardwareIdentifier && incident.syncStateRaw != "synced"
                }
            )
            result.append(contentsOf: try context.fetch(descriptor)
                .filter { sessionVehicles[$0.sessionID] == $0.vehicleID }
                .map { ($0, association.vehicle.id) })
        }
        return result.sorted { $0.0.triggeredAt < $1.0.triggeredAt }
    }

    private func pendingAnnotationEntries(
        for associations: [VehicleAssociation]
    ) throws -> [(annotation: TimelineAnnotation, remoteVehicleID: UUID)] {
        var result: [(TimelineAnnotation, UUID)] = []
        let sessionVehicles = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DriveSession>()).map {
            ($0.id, $0.vehicleID)
        })
        for association in associations {
            let hardwareIdentifier = association.hardwareIdentifier
            let descriptor = FetchDescriptor<TimelineAnnotation>(
                predicate: #Predicate { annotation in
                    annotation.vehicleID == hardwareIdentifier && annotation.syncStateRaw != "synced"
                }
            )
            result.append(contentsOf: try context.fetch(descriptor)
                .filter { sessionVehicles[$0.sessionID] == $0.vehicleID }
                .map { ($0, association.vehicle.id) })
        }
        return result.sorted { $0.0.timestamp < $1.0.timestamp }
    }

    @discardableResult
    private func restoreActiveVehicle() -> Bool {
        let associations = currentAccountAssociations()
        guard !associations.isEmpty else {
            activeVehicle = nil
            pendingHardwareIdentifier = nil
            return false
        }
        let remembered = UserDefaults.standard.string(forKey: lastVehicleDefaultsKey())
            .flatMap(UUID.init(uuidString:))
        let selected = associations.first(where: { $0.hardwareIdentifier == remembered }) ?? associations.last!
        pendingHardwareIdentifier = selected.hardwareIdentifier
        activeVehicle = selected.vehicle
        rememberActiveVehicle(selected.hardwareIdentifier)
        return true
    }

    private func rememberActiveVehicle(_ hardwareIdentifier: UUID) {
        UserDefaults.standard.set(hardwareIdentifier.uuidString, forKey: lastVehicleDefaultsKey())
    }

    private func lastVehicleDefaultsKey() -> String {
        let accountID = account.account?.id.uuidString.lowercased() ?? "signed-out"
        return "\(Self.lastVehicleIdentifierKey).\(accountID)"
    }
}
