import Foundation
import Network
import SwiftData

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
        do {
            try await synchronizeDashboardTemplates()
            let associations = currentAccountAssociations()
            guard !associations.isEmpty else {
                lastSynchronizedAt = .now
                state = pendingHardwareIdentifier == nil ? .ready : .waitingForVehicleName
                return
            }
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
                try await upload(session: entry.session, vehicleID: entry.remoteVehicleID)
            }
            for entry in queuedIncidents {
                try await upload(incident: entry.incident, vehicleID: entry.remoteVehicleID)
            }
            for entry in queuedAnnotations {
                try await upload(annotation: entry.annotation, vehicleID: entry.remoteVehicleID)
            }
            try context.save()

            // Alert configuration is synchronized after telemetry so a rules-only
            // failure can never prevent a recorded drive from reaching the server.
            for association in associations {
                try await synchronizeAlertRules(for: association)
            }

            lastTransferBytes = progress?.transferredBytes ?? 0
            lastSynchronizedAt = .now
            state = .ready
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

    func noteLocalSampleRecorded(sessionBecamePending: Bool) {
        pendingSamples += 1
        estimatedPendingBytes = Int64(pendingSamples) * Self.estimatedBytesPerSample
        if sessionBecamePending {
            pendingSessions += 1
        }
    }

    func noteLocalIncidentRecorded(sampleCount: Int) {
        pendingIncidents += 1
        pendingSamples += sampleCount
        estimatedPendingBytes += Int64(sampleCount) * Self.estimatedBytesPerSample
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
        var offset = 0
        var sentEmptySession = false
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
                samples: chunk.map(makeUpload)
            )
            let encodedSize = try JSONEncoder.tougeDashCloud().encode(request).count
            let result: CloudSyncResult = try await account.send(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/sessions/sync",
                body: request
            )
            session.remoteID = result.sessionId.uuidString
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
            if var progress {
                progress.completedSamples += chunk.count
                progress.transferredBytes += Int64(encodedSize)
                self.progress = progress
            }
        }
        incident.syncState = .synced
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
        let associations = currentAccountAssociations()
        let sessions: [DriveSession]
        if associations.isEmpty {
            let descriptor = FetchDescriptor<DriveSession>(predicate: #Predicate { $0.syncStateRaw != "synced" })
            sessions = (try? context.fetch(descriptor)) ?? []
        } else {
            sessions = (try? pendingSessionEntries(for: associations).map(\.session)) ?? []
        }
        let incidents: [DriveIncident]
        let annotations: [TimelineAnnotation]
        if associations.isEmpty {
            incidents = (try? context.fetch(FetchDescriptor<DriveIncident>(predicate: #Predicate { $0.syncStateRaw != "synced" }))) ?? []
            annotations = (try? context.fetch(FetchDescriptor<TimelineAnnotation>(predicate: #Predicate { $0.syncStateRaw != "synced" }))) ?? []
        } else {
            incidents = (try? pendingIncidentEntries(for: associations).map(\.incident)) ?? []
            annotations = (try? pendingAnnotationEntries(for: associations).map(\.annotation)) ?? []
        }
        pendingSessions = sessions.count
        pendingIncidents = incidents.count
        pendingAnnotations = annotations.count
        pendingSamples = sessions.reduce(0) { $0 + $1.sampleCount } + incidents.reduce(0) { $0 + $1.sampleCount }
        estimatedPendingBytes = Int64(pendingSamples) * Self.estimatedBytesPerSample + Int64(annotations.count * 512)
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
        for association in associations {
            let hardwareIdentifier = association.hardwareIdentifier
            let descriptor = FetchDescriptor<DriveIncident>(
                predicate: #Predicate { incident in
                    incident.vehicleID == hardwareIdentifier && incident.syncStateRaw != "synced"
                }
            )
            result.append(contentsOf: try context.fetch(descriptor).map { ($0, association.vehicle.id) })
        }
        return result.sorted { $0.0.triggeredAt < $1.0.triggeredAt }
    }

    private func pendingAnnotationEntries(
        for associations: [VehicleAssociation]
    ) throws -> [(annotation: TimelineAnnotation, remoteVehicleID: UUID)] {
        var result: [(TimelineAnnotation, UUID)] = []
        for association in associations {
            let hardwareIdentifier = association.hardwareIdentifier
            let descriptor = FetchDescriptor<TimelineAnnotation>(
                predicate: #Predicate { annotation in
                    annotation.vehicleID == hardwareIdentifier && annotation.syncStateRaw != "synced"
                }
            )
            result.append(contentsOf: try context.fetch(descriptor).map { ($0, association.vehicle.id) })
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
