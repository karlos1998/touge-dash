import AVFoundation
import CryptoKit
import Foundation

enum SeventyMaiCameraChannel: String, CaseIterable, Identifiable, Sendable {
    case front
    case rear
    case interior

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .front: localized("Przód")
        case .rear: localized("Tył")
        case .interior: localized("Wnętrze")
        }
    }

    var systemImage: String {
        switch self {
        case .front: "car.front.waves.up"
        case .rear: "car.rear.waves.up"
        case .interior: "person.crop.rectangle"
        }
    }
}

enum SeventyMaiCameraModel: String, CaseIterable, Identifiable, Sendable {
    case m300
    case m500
    case a200
    case a400
    case a500s
    case a510
    case a800s
    case a810
    case s500

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m300: "70mai M300"
        case .m500: "70mai M500"
        case .a200: "70mai A200"
        case .a400: "70mai A400"
        case .a500s: "70mai A500S / Pro Plus+"
        case .a510: "70mai A510"
        case .a800s: "70mai A800S"
        case .a810: "70mai A810"
        case .s500: "70mai S500"
        }
    }

    var ssidPlaceholder: String {
        switch self {
        case .m300: "70mai_M300_XXXX"
        case .m500: "70mai_M500_XXXX"
        case .a200: "70mai_A200_XXXX"
        case .a400: "70mai_A400_XXXX"
        case .a500s: "70mai_A500S_XXXX"
        case .a510: "70mai_A510_XXXX"
        case .a800s: "70mai_A800S_XXXX"
        case .a810: "70mai_A810_XXXX"
        case .s500: "70mai_S500_XXXX"
        }
    }

    var channels: [SeventyMaiCameraChannel] {
        switch self {
        case .m300, .m500:
            [.front]
        case .a200, .a400, .a500s, .a510, .a800s, .a810, .s500:
            [.front, .rear]
        }
    }

    func recordingType(for channel: SeventyMaiCameraChannel) -> String? {
        guard channels.contains(channel) else { return nil }
        switch (self, channel) {
        case (.m300, .front), (.m500, .front): return "0"
        case (_, .front): return "4"
        case (_, .rear): return "8"
        case (_, .interior): return "18"
        }
    }
}

struct SeventyMaiM300Clip: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let sizeBytes: Int64
    let cameraStartedAt: Date
    let correctedStartedAt: Date
    let duration: TimeInterval
    let width: Int
    let height: Int
    let framesPerSecond: Double
    let videoCodec: String?

    var id: String { "\(path)/\(name)" }
    var endedAt: Date { correctedStartedAt.addingTimeInterval(duration) }

    func overlaps(startedAt: Date, endedAt: Date) -> Bool {
        correctedStartedAt < endedAt && self.endedAt > startedAt
    }

    func replacingDuration(_ duration: TimeInterval) -> Self {
        Self(
            path: path,
            name: name,
            sizeBytes: sizeBytes,
            cameraStartedAt: cameraStartedAt,
            correctedStartedAt: correctedStartedAt,
            duration: duration,
            width: width,
            height: height,
            framesPerSecond: framesPerSecond,
            videoCodec: videoCodec
        )
    }
}

struct SeventyMaiM300ScanResult: Sendable {
    let cameraModel: SeventyMaiCameraModel
    let channel: SeventyMaiCameraChannel
    let host: String
    let connectKey: String
    let clockOffsetSeconds: TimeInterval?
    let clips: [SeventyMaiM300Clip]
}

struct PreparedSeventyMaiImport: Sendable {
    let fileName: String
    let displayName: String
    let startedAt: Date
    let fileSizeBytes: Int64
    let metadata: DriveVideoAssetMetadata
    let telemetryTrimStartSeconds: Double
    let exportDurationSeconds: Double
}

enum SeventyMaiM300Progress: Sendable {
    case probing(String)
    case requestingAuthorization
    case waitingForButton
    case readingClock
    case readingRecordings(page: Int)
    case enteringAlbum
    case downloading(
        current: Int,
        total: Int,
        name: String,
        receivedBytes: Int64,
        expectedBytes: Int64
    )
    case joining
    case inspecting
}

enum SeventyMaiM300Error: LocalizedError, Equatable {
    case cameraUnavailable
    case invalidResponse(String)
    case cameraRejected(String)
    case authorizationTimedOut
    case noMatchingRecordings
    case invalidRecordingMetadata(String)
    case discontinuousRecordings(Double)
    case exportUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            localized("Nie znaleziono kamery 70mai pod adresem 192.168.0.1. Sprawdź, czy Wi‑Fi kamery jest włączone i iPhone jest z nim połączony.")
        case .invalidResponse(let endpoint):
            String(format: localized("Kamera zwróciła nieprawidłową odpowiedź dla %@."), endpoint)
        case .cameraRejected(let code):
            String(format: localized("Kamera odrzuciła żądanie (kod %@)."), code)
        case .authorizationTimedOut:
            localized("Kamera nie potwierdziła połączenia. Uruchom skan ponownie i naciśnij raz przycisk zasilania, gdy kamera poprosi o autoryzację.")
        case .noMatchingRecordings:
            localized("Na karcie pamięci nie znaleziono zwykłych nagrań pokrywających się z tym przejazdem.")
        case .invalidRecordingMetadata(let name):
            String(format: localized("Nagranie %@ nie ma prawidłowego czasu lub długości."), name)
        case .discontinuousRecordings(let gap):
            String(format: localized("Między nagraniami jest przerwa %.1f s. Import został zatrzymany, żeby nie rozsunąć filmu i telemetrii."), gap)
        case .exportUnavailable:
            localized("Nie udało się połączyć klipów pobranych z kamery.")
        }
    }
}

enum SeventyMaiM300Protocol {
    static let defaultHost = "192.168.0.1"
    static let bindSecret = "73VpsAfdety8FDd0"
    // The official 70mai client requests type 0 for normal front-camera
    // recordings on single-channel models such as the M300. Type 4 is used by
    // selected multi-channel Hisi models and returns no array on M300 firmware.
    static let normalRecordingType = "0"

    static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func bindURL(host: String, userID: String) -> URL? {
        unsignedURL(
            host: host,
            endpoint: "BindByBanya.cgi",
            parameters: [("usr", userID), ("signkey", md5(userID + bindSecret))]
        )
    }

    static func confirmationURL(host: String, timestamp: String) -> URL? {
        unsignedURL(
            host: host,
            endpoint: "UserconfirmByBanya.cgi",
            parameters: [("timestamp", timestamp), ("signkey", md5(timestamp + bindSecret))]
        )
    }

    static func signedURL(
        host: String,
        endpoint: String,
        parameters: [(String, String)] = [],
        timestamp: Int64,
        connectKey: String
    ) -> URL? {
        let completeParameters = parameters + [("timestamp", String(timestamp))]
        let unsignedQuery = query(completeParameters)
        let signature = md5(endpoint + "?" + unsignedQuery + connectKey)
        return unsignedURL(
            host: host,
            endpoint: endpoint,
            parameters: completeParameters + [("signkey", signature)]
        )
    }

    static func directFileURL(host: String, path: String, name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        let joined = ([path, name]
            .flatMap { $0.split(separator: "/").map(String.init) })
            .joined(separator: "/")
        components.percentEncodedPath = "/" + joined
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return components.url
    }

    static func parseCameraDate(_ value: String, calendar: Calendar = .current) -> Date? {
        let candidates = [
            "yyyyMMdd-HHmmss",
            "yyyyMMddHHmmss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in candidates {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func dateFromFileName(_ name: String, calendar: Calendar = .current) -> Date? {
        let expression = try? NSRegularExpression(pattern: #"(20\d{6}-\d{6})"#)
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = expression?.firstMatch(in: name, range: range),
              let matchRange = Range(match.range(at: 1), in: name) else { return nil }
        return parseCameraDate(String(name[matchRange]), calendar: calendar)
    }

    static func correctedClip(
        dictionary: [String: Any],
        clockOffsetSeconds: TimeInterval?,
        calendar: Calendar = .current
    ) -> SeventyMaiM300Clip? {
        guard let name = string(dictionary["name"]),
              name.lowercased().hasSuffix(".mp4") else { return nil }
        let path = string(dictionary["path"]) ?? ""
        let rawDate = string(dictionary["time"])
            .flatMap { parseCameraDate($0, calendar: calendar) }
            ?? dateFromFileName(name, calendar: calendar)
        guard let cameraStartedAt = rawDate else { return nil }
        let rawDuration = double(dictionary["duration"]) ?? 0
        let duration = rawDuration > 0 ? rawDuration / 100 : 60
        let offset = clockOffsetSeconds ?? 0
        return SeventyMaiM300Clip(
            path: path,
            name: name,
            sizeBytes: Int64(double(dictionary["size"]) ?? 0),
            cameraStartedAt: cameraStartedAt,
            correctedStartedAt: cameraStartedAt.addingTimeInterval(-offset),
            duration: duration,
            width: Int(double(dictionary["width"]) ?? 0),
            height: Int(double(dictionary["height"]) ?? 0),
            framesPerSecond: double(dictionary["fps"]) ?? 0,
            videoCodec: string(dictionary["videoencode"])
        )
    }

    static func matchingClips(
        _ clips: [SeventyMaiM300Clip],
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) -> [SeventyMaiM300Clip] {
        normalizedClipDurations(clips)
            .filter { $0.overlaps(startedAt: sessionStartedAt, endedAt: sessionEndedAt) }
            .sorted { $0.correctedStartedAt < $1.correctedStartedAt }
    }

    static func normalizedClipDurations(_ clips: [SeventyMaiM300Clip]) -> [SeventyMaiM300Clip] {
        let sorted = clips.sorted { $0.correctedStartedAt < $1.correctedStartedAt }
        return sorted.enumerated().map { index, clip in
            guard sorted.indices.contains(index + 1) else { return clip }
            let intervalToNext = sorted[index + 1].correctedStartedAt.timeIntervalSince(clip.correctedStartedAt)
            // Some M300 firmware reports 60 seconds for a full three-minute
            // recording. The next filename timestamp is a better upper bound;
            // the MP4 duration becomes authoritative after download.
            guard intervalToNext > clip.duration,
                  intervalToNext <= 5 * 60 else { return clip }
            return clip.replacingDuration(intervalToNext)
        }
    }

    private static func unsignedURL(
        host: String,
        endpoint: String,
        parameters: [(String, String)]
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/cgi-bin/\(endpoint)"
        // The firmware accepts the unusual leading "&-" form used by the
        // official client. Building the percent-encoded query ourselves keeps
        // that exact wire format.
        components.percentEncodedQuery = query(parameters)
        return components.url
    }

    private static func query(_ parameters: [(String, String)]) -> String {
        parameters.map { key, value in
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .seventyMaiQueryValue) ?? value
            return "&-\(key)=\(escaped)"
        }.joined()
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }
}

private extension CharacterSet {
    static let seventyMaiQueryValue: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return allowed
    }()
}

actor SeventyMaiM300Client {
    typealias ProgressHandler = @MainActor @Sendable (SeventyMaiM300Progress) -> Void

    private static let userIDDefaultsKey = "TougeDash.dashcam.m300.userID"
    private let session: URLSession
    private let userID: String

    init(session: URLSession? = nil, userID: String? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // M300 transfers can be only a few MB/s. A single clip may take
            // several minutes, so only an idle connection should time out
            // quickly; the complete resource gets a much larger window.
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60 * 60
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.userID = userID ?? Self.persistentUserID()
    }

    private static func persistentUserID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: userIDDefaultsKey), !existing.isEmpty {
            return existing
        }
        let created = String(Int64.random(in: 100_000_000...9_999_999_999))
        defaults.set(created, forKey: userIDDefaultsKey)
        return created
    }

    func scan(
        cameraModel: SeventyMaiCameraModel,
        channel: SeventyMaiCameraChannel,
        sessionStartedAt: Date,
        sessionEndedAt: Date,
        progress: ProgressHandler? = nil
    ) async throws -> SeventyMaiM300ScanResult {
        let host = SeventyMaiM300Protocol.defaultHost
        guard let recordingType = cameraModel.recordingType(for: channel) else {
            throw SeventyMaiM300Error.noMatchingRecordings
        }
        await progress?(.probing(host))
        let connectKey = try await authorize(host: host, progress: progress)

        let clockOffset = try? await readClockOffset(host: host, connectKey: connectKey, progress: progress)
        try await setAlbumMode(true, host: host, connectKey: connectKey)
        defer {
            Task { try? await self.setAlbumMode(false, host: host, connectKey: connectKey) }
        }

        var allClips: [SeventyMaiM300Clip] = []
        for page in 0..<20 {
            await progress?(.readingRecordings(page: page + 1))
            let start = page * 100 + 1
            let dictionaries = try await filePage(
                host: host,
                connectKey: connectKey,
                start: start,
                end: start + 99,
                recordingType: recordingType
            )
            let pageClips = dictionaries.compactMap {
                SeventyMaiM300Protocol.correctedClip(
                    dictionary: $0,
                    clockOffsetSeconds: clockOffset
                )
            }
            allClips.append(contentsOf: pageClips)
            if dictionaries.count < 100 { break }
            if pageClips.count > 1,
               pageClips.first!.correctedStartedAt >= pageClips.last!.correctedStartedAt,
               pageClips.last!.endedAt < sessionStartedAt.addingTimeInterval(-60) {
                break
            }
        }

        let matching = SeventyMaiM300Protocol.matchingClips(
            allClips,
            sessionStartedAt: sessionStartedAt,
            sessionEndedAt: sessionEndedAt
        )
        guard !matching.isEmpty else { throw SeventyMaiM300Error.noMatchingRecordings }
        return SeventyMaiM300ScanResult(
            cameraModel: cameraModel,
            channel: channel,
            host: host,
            connectKey: connectKey,
            clockOffsetSeconds: clockOffset,
            clips: matching
        )
    }

    func importClips(
        _ scan: SeventyMaiM300ScanResult,
        sessionStartedAt: Date,
        sessionEndedAt: Date,
        progress: ProgressHandler? = nil
    ) async throws -> PreparedSeventyMaiImport {
        await progress?(.enteringAlbum)
        try await setAlbumMode(true, host: scan.host, connectKey: scan.connectKey)
        await SeventyMaiBackgroundDownloadCoordinator.shared.cancelOrphanedTasks()
        defer {
            Task { try? await self.setAlbumMode(false, host: scan.host, connectKey: scan.connectKey) }
        }

        let temporaryDirectory = try stagingDirectory(
            for: scan.clips,
            sessionStartedAt: sessionStartedAt,
            sessionEndedAt: sessionEndedAt
        )
        var finishedImport = false
        defer {
            if finishedImport {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
        }

        var downloaded: [(clip: SeventyMaiM300Clip, url: URL)] = []
        var transfers: [(clip: SeventyMaiM300Clip, remoteURL: URL, localURL: URL, index: Int)] = []
        for (index, clip) in scan.clips.enumerated() {
            try Task.checkCancellation()
            guard let remoteURL = SeventyMaiM300Protocol.directFileURL(
                host: scan.host,
                path: clip.path,
                name: clip.name
            ) else {
                throw SeventyMaiM300Error.invalidRecordingMetadata(clip.name)
            }
            let localURL = temporaryDirectory.appending(path: clip.name, directoryHint: .notDirectory)
            if isCompleteStagedFile(localURL, expectedBytes: clip.sizeBytes) {
                await progress?(.downloading(
                    current: index + 1,
                    total: scan.clips.count,
                    name: clip.name,
                    receivedBytes: max(0, clip.sizeBytes),
                    expectedBytes: max(0, clip.sizeBytes)
                ))
            } else {
                try? FileManager.default.removeItem(at: localURL)
                transfers.append((clip, remoteURL, localURL, index + 1))
            }
            downloaded.append((clip, localURL))
        }

        for transfer in transfers {
            try Task.checkCancellation()
            await progress?(.downloading(
                current: transfer.index,
                total: scan.clips.count,
                name: transfer.clip.name,
                receivedBytes: 0,
                expectedBytes: max(0, transfer.clip.sizeBytes)
            ))
            try await SeventyMaiBackgroundDownloadCoordinator.shared.download(
                from: transfer.remoteURL,
                to: transfer.localURL,
                current: transfer.index,
                total: scan.clips.count,
                name: transfer.clip.name,
                expectedBytes: max(0, transfer.clip.sizeBytes),
                progress: progress
            )
        }

        await progress?(.joining)
        let outputURL = try DriveVideoFileStore.newRecordingURL(fileExtension: "mp4")
        do {
            let startedAt = try await join(
                downloaded,
                sessionStartedAt: sessionStartedAt,
                sessionEndedAt: sessionEndedAt,
                outputURL: outputURL
            )
            await progress?(.inspecting)
            let metadata = try await DriveVideoAssetInspector.metadata(for: outputURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let telemetryStart = max(0, startedAt.timeIntervalSince(sessionStartedAt))
            finishedImport = true
            return PreparedSeventyMaiImport(
                fileName: outputURL.lastPathComponent,
                displayName: scan.cameraModel.displayName
                    + (scan.cameraModel.channels.count > 1 ? " · \(scan.channel.displayName)" : "")
                    + " · \(scan.clips.count) klipów",
                startedAt: startedAt,
                fileSizeBytes: size,
                metadata: metadata,
                telemetryTrimStartSeconds: telemetryStart,
                exportDurationSeconds: min(metadata.duration, max(0, sessionEndedAt.timeIntervalSince(startedAt)))
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func stagingDirectory(
        for clips: [SeventyMaiM300Clip],
        sessionStartedAt: Date,
        sessionEndedAt: Date
    ) throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "TougeDashM300Imports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cleanupStaleStagingDirectories(in: root)

        let identity = clips.map(\.id).joined(separator: "|")
            + "|\(sessionStartedAt.timeIntervalSince1970)|\(sessionEndedAt.timeIntervalSince1970)"
        let jobDirectory = root.appending(
            path: SeventyMaiM300Protocol.md5(identity),
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: jobDirectory.path)
        return jobDirectory
    }

    private func cleanupStaleStagingDirectories(in root: URL) {
        let expiration = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        for directory in directories {
            guard let values = try? directory.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  (values.contentModificationDate ?? .distantPast) < expiration else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func isCompleteStagedFile(_ url: URL, expectedBytes: Int64) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let storedBytes = (attributes[.size] as? NSNumber)?.int64Value,
              storedBytes > 0 else { return false }
        return expectedBytes <= 0 || storedBytes == expectedBytes
    }

    private func authorize(host: String, progress: ProgressHandler?) async throws -> String {
        await progress?(.requestingAuthorization)
        guard let bindURL = SeventyMaiM300Protocol.bindURL(host: host, userID: userID) else {
            throw SeventyMaiM300Error.cameraUnavailable
        }
        let result = try await requestResult(bindURL, endpoint: "BindByBanya.cgi")
        guard let dictionary = result as? [String: Any],
              let connectKey = (dictionary["Token"] as? String) ?? (dictionary["token"] as? String),
              let timestamp = valueString(dictionary["timestamp"]),
              !connectKey.isEmpty else {
            throw SeventyMaiM300Error.invalidResponse("BindByBanya.cgi")
        }

        await progress?(.waitingForButton)
        let deadline = ContinuousClock.now.advanced(by: .seconds(35))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard let confirmationURL = SeventyMaiM300Protocol.confirmationURL(
                host: host,
                timestamp: timestamp
            ) else { throw SeventyMaiM300Error.cameraUnavailable }
            do {
                _ = try await requestResult(confirmationURL, endpoint: "UserconfirmByBanya.cgi")
                return connectKey
            } catch SeventyMaiM300Error.cameraRejected(let code) where code == "-6675" || code == "-6677" {
                try await Task.sleep(for: .milliseconds(400))
            } catch SeventyMaiM300Error.cameraRejected {
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw SeventyMaiM300Error.authorizationTimedOut
    }

    private func readClockOffset(
        host: String,
        connectKey: String,
        progress: ProgressHandler?
    ) async throws -> TimeInterval? {
        await progress?(.readingClock)
        let sentAt = Date()
        let result = try await signedResult(
            host: host,
            endpoint: "getAllMenu.cgi",
            connectKey: connectKey
        )
        let receivedAt = Date()
        guard let dictionary = result as? [String: Any],
              let rawTime = valueString(dictionary["systime"]),
              let cameraTime = SeventyMaiM300Protocol.parseCameraDate(rawTime) else { return nil }
        let midpoint = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
        return cameraTime.timeIntervalSince(midpoint)
    }

    private func setAlbumMode(_ enabled: Bool, host: String, connectKey: String) async throws {
        _ = try await signedResult(
            host: host,
            endpoint: "setaccessalbum.cgi",
            parameters: [("enable", enabled ? "1" : "0")],
            connectKey: connectKey
        )
    }

    private func filePage(
        host: String,
        connectKey: String,
        start: Int,
        end: Int,
        recordingType: String
    ) async throws -> [[String: Any]] {
        let result = try await signedResult(
            host: host,
            endpoint: "getfilelist.cgi",
            parameters: [
                ("start", String(start)),
                ("end", String(end)),
                ("type", recordingType)
            ],
            connectKey: connectKey
        )
        if result is NSNull { return [] }
        if let dictionaries = result as? [[String: Any]] { return dictionaries }
        if let container = result as? [String: Any] {
            for key in ["files", "filelist", "list"] {
                if let dictionaries = container[key] as? [[String: Any]] {
                    return dictionaries
                }
            }
        }
        throw SeventyMaiM300Error.invalidResponse("getfilelist.cgi")
    }

    private func signedResult(
        host: String,
        endpoint: String,
        parameters: [(String, String)] = [],
        connectKey: String
    ) async throws -> Any {
        let timestamp = Int64(Date().timeIntervalSince1970)
        guard let url = SeventyMaiM300Protocol.signedURL(
            host: host,
            endpoint: endpoint,
            parameters: parameters,
            timestamp: timestamp,
            connectKey: connectKey
        ) else { throw SeventyMaiM300Error.cameraUnavailable }
        return try await requestResult(url, endpoint: endpoint)
    }

    private func requestResult(_ url: URL, endpoint: String) async throws -> Any {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SeventyMaiM300Error.cameraUnavailable
        }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SeventyMaiM300Error.invalidResponse(endpoint)
        }
        let resultCode = valueString(object["ResultCode"]) ?? ""
        guard resultCode == "0" else {
            throw SeventyMaiM300Error.cameraRejected(resultCode.isEmpty ? "?" : resultCode)
        }
        guard let rawResult = object["Result"] else { return NSNull() }
        if let string = rawResult as? String,
           let nestedData = string.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: nestedData) {
            return nested
        }
        return rawResult
    }

    func join(
        _ inputs: [(clip: SeventyMaiM300Clip, url: URL)],
        sessionStartedAt: Date,
        sessionEndedAt: Date,
        outputURL: URL
    ) async throws -> Date {
        guard let first = inputs.first else { throw SeventyMaiM300Error.noMatchingRecordings }
        let outputStartedAt = max(sessionStartedAt, first.clip.correctedStartedAt)
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw SeventyMaiM300Error.exportUnavailable }
        let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform?
        for input in inputs {
            let asset = AVURLAsset(url: input.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw SeventyMaiM300Error.invalidRecordingMetadata(input.clip.name)
            }
            let assetDuration = try await asset.load(.duration).seconds
            let actualClipEnd = input.clip.correctedStartedAt.addingTimeInterval(assetDuration)
            let clipStart = max(sessionStartedAt, input.clip.correctedStartedAt)
            let clipEnd = min(sessionEndedAt, actualClipEnd)
            guard clipEnd > clipStart else { continue }

            let expectedCursorSeconds = clipStart.timeIntervalSince(outputStartedAt)
            let overlapTrim = max(0, cursor.seconds - expectedCursorSeconds)
            let sourceStartSeconds = max(0, clipStart.timeIntervalSince(input.clip.correctedStartedAt) + overlapTrim)
            let desiredDuration = max(0, clipEnd.timeIntervalSince(clipStart) - overlapTrim)
            let safeDuration = min(desiredDuration, max(0, assetDuration - sourceStartSeconds))
            guard safeDuration > 0 else { continue }

            let gap = expectedCursorSeconds - cursor.seconds
            if gap > 0.05 {
                let emptyRange = CMTimeRange(
                    start: cursor,
                    duration: CMTime(seconds: gap, preferredTimescale: 600)
                )
                compositionVideo.insertEmptyTimeRange(emptyRange)
                compositionAudio?.insertEmptyTimeRange(emptyRange)
                cursor = cursor + emptyRange.duration
            }
            let range = CMTimeRange(
                start: CMTime(seconds: sourceStartSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: safeDuration, preferredTimescale: 600)
            )
            try compositionVideo.insertTimeRange(range, of: sourceVideo, at: cursor)
            if firstTransform == nil { firstTransform = try await sourceVideo.load(.preferredTransform) }
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? compositionAudio?.insertTimeRange(range, of: sourceAudio, at: cursor)
            }
            cursor = cursor + range.duration
        }
        guard cursor.seconds > 0 else { throw SeventyMaiM300Error.exportUnavailable }
        compositionVideo.preferredTransform = firstTransform ?? .identity

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw SeventyMaiM300Error.exportUnavailable
        }
        exporter.timeRange = CMTimeRange(start: .zero, duration: cursor)
        try await exporter.export(to: outputURL, as: .mp4)
        return outputStartedAt
    }

    private func valueString(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}

private struct SeventyMaiBackgroundTransferDescriptor: Codable, Sendable {
    var destinationPath: String
    var current: Int
    var total: Int
    var name: String
    var expectedBytes: Int64
    var retryCount: Int

    var encodedTaskDescription: String? {
        try? JSONEncoder().encode(self).base64EncodedString()
    }

    static func decode(_ value: String?) -> Self? {
        guard let value,
              let data = Data(base64Encoded: value) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

final class SeventyMaiBackgroundDownloadCoordinator: NSObject, URLSessionDownloadDelegate, URLSessionDelegate, @unchecked Sendable {
    typealias ProgressHandler = SeventyMaiM300Client.ProgressHandler

    static let shared = SeventyMaiBackgroundDownloadCoordinator()
    static let sessionIdentifier = "it.letscode.touge-dash.70mai-downloads"

    private struct PendingTransfer {
        var descriptor: SeventyMaiBackgroundTransferDescriptor
        let continuation: CheckedContinuation<Void, Error>
        let progress: ProgressHandler?
        let taskReference: SeventyMaiDownloadTaskReference
    }

    private let lock = NSLock()
    private var pending: [Int: PendingTransfer] = [:]
    private var completedResults: [Int: Result<Void, Error>] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override private init() {
        super.init()
        _ = session
    }

    func storeBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        lock.withLock {
            backgroundCompletionHandler = completionHandler
        }
    }

    func cancelOrphanedTasks() async {
        let tasks = await session.allTasks
        let activeTaskIDs = lock.withLock { Set(pending.keys) }
        for task in tasks where !activeTaskIDs.contains(task.taskIdentifier) {
            task.cancel()
        }
    }

    func download(
        from remoteURL: URL,
        to localURL: URL,
        current: Int,
        total: Int,
        name: String,
        expectedBytes: Int64,
        progress: ProgressHandler?
    ) async throws {
        let taskReference = SeventyMaiDownloadTaskReference()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var request = URLRequest(url: remoteURL)
                request.timeoutInterval = 30
                let descriptor = SeventyMaiBackgroundTransferDescriptor(
                    destinationPath: localURL.path,
                    current: current,
                    total: total,
                    name: name,
                    expectedBytes: expectedBytes,
                    retryCount: 0
                )
                let task = session.downloadTask(with: request)
                task.taskDescription = descriptor.encodedTaskDescription
                if expectedBytes > 0 {
                    task.countOfBytesClientExpectsToReceive = expectedBytes
                }
                lock.withLock {
                    pending[task.taskIdentifier] = PendingTransfer(
                        descriptor: descriptor,
                        continuation: continuation,
                        progress: progress,
                        taskReference: taskReference
                    )
                }
                taskReference.store(task)
                task.resume()
            }
        } onCancel: {
            taskReference.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let transfer = lock.withLock { pending[downloadTask.taskIdentifier] }
        let descriptor = transfer?.descriptor
            ?? SeventyMaiBackgroundTransferDescriptor.decode(downloadTask.taskDescription)
        guard let descriptor else { return }
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : descriptor.expectedBytes
        reportProgress(
            descriptor,
            receivedBytes: max(0, totalBytesWritten),
            expectedBytes: max(0, expected),
            to: transfer?.progress
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        let transfer = lock.withLock { pending[downloadTask.taskIdentifier] }
        let descriptor = transfer?.descriptor
            ?? SeventyMaiBackgroundTransferDescriptor.decode(downloadTask.taskDescription)
        guard let descriptor else { return }
        reportProgress(
            descriptor,
            receivedBytes: max(0, fileOffset),
            expectedBytes: max(expectedTotalBytes, descriptor.expectedBytes),
            to: transfer?.progress
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let descriptor = lock.withLock({ pending[downloadTask.taskIdentifier]?.descriptor })
                ?? SeventyMaiBackgroundTransferDescriptor.decode(downloadTask.taskDescription) else {
            lock.withLock {
                completedResults[downloadTask.taskIdentifier] = .failure(SeventyMaiM300Error.cameraUnavailable)
            }
            return
        }

        let result: Result<Void, Error>
        if let response = downloadTask.response as? HTTPURLResponse,
           (200..<300).contains(response.statusCode) {
            do {
                let destination = URL(fileURLWithPath: descriptor.destinationPath)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                result = .success(())
            } catch {
                result = .failure(error)
            }
        } else {
            result = .failure(SeventyMaiM300Error.cameraUnavailable)
        }
        lock.withLock {
            completedResults[downloadTask.taskIdentifier] = result
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskID = task.taskIdentifier
        let transfer = lock.withLock { pending.removeValue(forKey: taskID) }

        if let error,
           let transfer,
           transfer.descriptor.retryCount < 3,
           let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            var descriptor = transfer.descriptor
            descriptor.retryCount += 1
            let resumedTask = self.session.downloadTask(withResumeData: resumeData)
            resumedTask.taskDescription = descriptor.encodedTaskDescription
            if descriptor.expectedBytes > 0 {
                resumedTask.countOfBytesClientExpectsToReceive = descriptor.expectedBytes
            }
            transfer.taskReference.store(resumedTask)
            lock.withLock {
                completedResults.removeValue(forKey: taskID)
                pending[resumedTask.taskIdentifier] = PendingTransfer(
                    descriptor: descriptor,
                    continuation: transfer.continuation,
                    progress: transfer.progress,
                    taskReference: transfer.taskReference
                )
            }
            resumedTask.resume()
            return
        }

        let storedResult = lock.withLock { completedResults.removeValue(forKey: taskID) }
        guard let transfer else { return }
        if let error {
            transfer.continuation.resume(throwing: error)
        } else {
            switch storedResult ?? .failure(SeventyMaiM300Error.cameraUnavailable) {
            case .success:
                transfer.continuation.resume()
            case .failure(let storedError):
                transfer.continuation.resume(throwing: storedError)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completionHandler = lock.withLock { () -> (() -> Void)? in
            defer { backgroundCompletionHandler = nil }
            return backgroundCompletionHandler
        }
        guard let completionHandler else { return }
        DispatchQueue.main.async {
            completionHandler()
        }
    }

    private func reportProgress(
        _ descriptor: SeventyMaiBackgroundTransferDescriptor,
        receivedBytes: Int64,
        expectedBytes: Int64,
        to progress: ProgressHandler?
    ) {
        guard let progress else { return }
        Task { @MainActor in
            progress(.downloading(
                current: descriptor.current,
                total: descriptor.total,
                name: descriptor.name,
                receivedBytes: receivedBytes,
                expectedBytes: expectedBytes
            ))
        }
    }
}

private final class SeventyMaiDownloadTaskReference: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?

    func store(_ task: URLSessionDownloadTask) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }
}
