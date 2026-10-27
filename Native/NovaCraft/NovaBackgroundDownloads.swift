import Foundation
import Combine
import CryptoKit
import UIKit

// Copyright (c) 2026 mickey3211. Independent NovaCraft download engine.
// This uses Apple's documented background URLSession; it does not execute,
// unpack, load or sideload any downloaded Minecraft code.

enum NovaBackgroundPhase: String, Codable {
    case queued, running, done
}

struct NovaBackgroundEntry: Codable {
    var id: String
    var source: URL
    // Relative to Application Support/NovaCraft. Never an absolute path.
    var target: String
    var checksum: String
    var expectedBytes: Int64?
    var state: NovaBackgroundPhase
    var retries: Int
}

struct NovaBackgroundPlan: Codable {
    var versionID: String
    var entries: [NovaBackgroundEntry]
    var isPaused: Bool
    var finished: Bool
    var errorMessage: String?
}

struct NovaDownloadSnapshot {
    var versionID: String?
    var completed = 0
    var total = 0
    var isPaused = false
    var finished = false
    var error: String?
    var progress: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var isRunning: Bool { versionID != nil && !isPaused && !finished }
}

enum NovaBackgroundDownloadError: LocalizedError {
    case anotherVersion(String)
    case untrustedFile
    case invalidPlan
    var errorDescription: String? {
        switch self {
        case .anotherVersion(let id):
            return "Najpierw ukończ pobieranie Minecraft \(id), zanim zaczniesz inną wersję."
        case .untrustedFile: return "Nieprawidłowa lokalizacja lub kontrola bezpieczeństwa pliku."
        case .invalidPlan: return "Nie udało się zapisać planu pobierania Minecraft."
        }
    }
}

extension Notification.Name {
    static let novaBackgroundDownloadFinished = Notification.Name("pl.novacraft.minecraft.download.finished")
}

/// One persistent background session for all Minecraft client, library and
/// asset downloads. Apple transfers these jobs in a separate OS process.
/// A saved manifest survives NovaCraft suspension and an ordinary app restart.
final class NovaBackgroundDownloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let identifier = "pl.novacraft.zero.integrated.minecraft.background.v1"
    static let shared = NovaBackgroundDownloads()

    @Published private(set) var snapshot = NovaDownloadSnapshot()

    private let worker = DispatchQueue(label: "pl.novacraft.backgrounddownloads.disk", qos: .utility)
    private let fm = FileManager.default
    // Keep a modest pool of OS-managed tasks queued before iOS suspends us.
    // The actual concurrent HTTPS connections remain limited separately.
    private let maximumActiveTasks = 128
    private var plan: NovaBackgroundPlan?
    private var liveIDs = Set<String>()
    private var isReconciled = false

    // Called by UIApplicationDelegate on the main thread when iOS relaunches
    // the process to deliver background transfer events.
    private var backgroundEventCompletion: (() -> Void)?

    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft", isDirectory: true)
    }

    private var stateFile: URL {
        root.appendingPathComponent("background-downloads/install-plan.json")
    }

    private var stagingFolder: URL {
        root.appendingPathComponent("background-downloads/staging")
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        worker.async { [self] in
            plan = try? readPlan()
            publish()
            reconnect()
        }
    }

    /// UIKit callback always executes on the main thread.
    func acceptBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.identifier else {
            completionHandler()
            return
        }
        backgroundEventCompletion = completionHandler
        // Accessing session creates the same persistent session identifier.
        _ = session
    }

    private func readPlan() throws -> NovaBackgroundPlan {
        try JSONDecoder().decode(NovaBackgroundPlan.self, from: Data(contentsOf: stateFile))
    }

    private func savePlan() throws {
        try fm.createDirectory(at: stateFile.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        guard let plan else { throw NovaBackgroundDownloadError.invalidPlan }
        let bytes = try JSONEncoder().encode(plan)
        try bytes.write(to: stateFile, options: .atomic)
    }

    private func publish() {
        let value: NovaDownloadSnapshot
        if let plan {
            value = NovaDownloadSnapshot(
                versionID: plan.versionID,
                completed: plan.entries.reduce(0) { $0 + ($1.state == .done ? 1 : 0) },
                total: plan.entries.count,
                isPaused: plan.isPaused,
                finished: plan.finished,
                error: plan.errorMessage
            )
        } else {
            value = NovaDownloadSnapshot()
        }
        DispatchQueue.main.async { [weak self] in self?.snapshot = value }
    }

    /// Reconnect OS-managed tasks before scheduling any new downloads. Avoids
    /// duplicate jobs after iOS restores a suspended/terminated application.
    private func reconnect() {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            self.worker.async {
                let recognized = Set(self.plan?.entries.map(\.id) ?? [])
                for task in tasks where !recognized.contains(task.taskDescription ?? "") {
                    task.cancel()
                }
                self.liveIDs = Set(tasks.compactMap { task in
                    let id = task.taskDescription ?? ""
                    return recognized.contains(id) ? id : nil
                })
                if var current = self.plan {
                    for index in current.entries.indices {
                        if current.entries[index].state == .running &&
                           !self.liveIDs.contains(current.entries[index].id) {
                            current.entries[index].state = .queued
                        }
                    }
                    self.plan = current
                    try? self.savePlan()
                }
                self.isReconciled = true
                self.schedule()
            }
        }
    }

    /// An installation may only be queued after the version and asset index
    /// were downloaded and checksum-verified while the app was open.
    func begin(_ prepared: NovaBackgroundPlan) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async {
                if let current = self.plan, !current.finished &&
                   current.versionID != prepared.versionID {
                    continuation.resume(throwing: NovaBackgroundDownloadError.anotherVersion(current.versionID))
                    return
                }
                if let current = self.plan, !current.finished &&
                   current.versionID == prepared.versionID {
                    self.plan?.isPaused = false
                    self.plan?.errorMessage = nil
                } else {
                    self.plan = prepared
                }
                do {
                    try self.savePlan()
                    self.publish()
                    if self.isReconciled { self.schedule() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func retryFailed() {
        worker.async {
            guard self.plan != nil else { return }
            self.plan?.isPaused = false
            self.plan?.errorMessage = nil
            for i in self.plan!.entries.indices where self.plan!.entries[i].state != .done {
                self.plan!.entries[i].retries = 0
            }
            try? self.savePlan()
            self.publish()
            self.schedule()
        }
    }

    // Called only on the serial worker queue.
    private func schedule() {
        guard isReconciled, var plan, !plan.isPaused, !plan.finished else { return }
        var updated = false

        // Finish staged transfers that may have been interrupted after iOS
        // moved their files but before the app committed their checksums.
        for index in plan.entries.indices where plan.entries[index].state != .done {
            let entry = plan.entries[index]
            if fm.fileExists(atPath: stagingURL(for: entry.id).path) {
                self.plan = plan
                finishStaged(entry.id)
                plan = self.plan ?? plan
                updated = true
            }
        }

        // A staged checksum failure may have paused the job in finishStaged.
        // Never enqueue additional tasks after a fatal validation error.
        if plan.isPaused {
            self.plan = plan
            try? savePlan()
            publish()
            return
        }

        for i in plan.entries.indices {
            guard liveIDs.count < maximumActiveTasks else { break }
            guard plan.entries[i].state == .queued else { continue }
            let entry = plan.entries[i]
            guard allowedSource(entry.source), let destination = destinationURL(for: entry.target),
                  validSHA1(entry.checksum) else {
                plan.isPaused = true
                plan.errorMessage = "Nieprawidłowy adres pliku gry. Pobieranie wstrzymano."
                break
            }
            if fm.fileExists(atPath: destination.path),
               (try? Self.verify(destination, sha1: entry.checksum,
                                 size: entry.expectedBytes)) == true {
                plan.entries[i].state = .done
                updated = true
                continue
            }

            let task = session.downloadTask(with: entry.source)
            task.taskDescription = entry.id
            task.countOfBytesClientExpectsToReceive = entry.expectedBytes ?? NSURLSessionTransferSizeUnknown
            plan.entries[i].state = .running
            liveIDs.insert(entry.id)
            task.resume()
            updated = true
        }

        self.plan = plan
        if plan.entries.allSatisfy({ $0.state == .done }) && !plan.finished {
            finishInstall()
            return
        }
        if updated {
            try? savePlan()
            publish()
        }
    }

    private func finishInstall() {
        guard var plan else { return }
        let folder = root.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(safeVersion(plan.versionID), isDirectory: true)
        do {
            // This marker is the single source of truth used by LauncherState
            // to decide whether Minecraft files are fully installed.
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("ok".utf8).write(to: folder.appendingPathComponent("install-complete"),
                                         options: .atomic)
            plan.finished = true
            plan.errorMessage = nil
            self.plan = plan
            try savePlan()
            publish()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .novaBackgroundDownloadFinished, object: plan.versionID)
            }
        } catch {
            plan.isPaused = true
            plan.errorMessage = "Nie można zakończyć instalacji na dysku: \(error.localizedDescription)"
            self.plan = plan
            try? savePlan()
            publish()
        }
    }

    private func finishStaged(_ id: String) {
        guard let index = plan?.entries.firstIndex(where: { $0.id == id }),
              let entry = plan?.entries[index],
              let destination = destinationURL(for: entry.target) else { return }
        let staged = stagingURL(for: id)
        do {
            guard try Self.verify(staged, sha1: entry.checksum, size: entry.expectedBytes)
                else { throw InstallError.checksumMismatch }
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staged, to: destination)
            plan?.entries[index].state = .done
            plan?.entries[index].retries = 0
            liveIDs.remove(id)
        } catch {
            try? fm.removeItem(at: staged)
            fail(id, reason: "Błąd sumy kontrolnej lub zapisu pliku")
        }
    }

    private func fail(_ id: String, reason: String) {
        guard let index = plan?.entries.firstIndex(where: { $0.id == id }),
              plan?.entries[index].state != .done else { return }
        liveIDs.remove(id)
        plan?.entries[index].state = .queued
        plan?.entries[index].retries += 1
        if let attempts = plan?.entries[index].retries, attempts >= 3 {
            plan?.isPaused = true
            plan?.errorMessage = "\(reason). Połącz się z internetem i naciśnij Wznów."
        }
        try? savePlan()
        publish()
    }

    private func stagingURL(for id: String) -> URL {
        // Task IDs are UUIDs generated locally, never user-provided paths.
        stagingFolder.appendingPathComponent(id + ".download", isDirectory: false)
    }

    private func destinationURL(for relative: String) -> URL? {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.first.map(String.init).map({ ["versions", "libraries", "assets"].contains($0) }) == true,
              parts.allSatisfy({ part in
                !part.isEmpty && part != "." && part != ".." &&
                !part.contains(":") && !part.contains("\\") && !part.contains("\0")
              }) else { return nil }
        return parts.reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    private func safeVersion(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func allowedSource(_ url: URL) -> Bool {
        let permitted: Set<String> = [
            "piston-data.mojang.com", "launcher.mojang.com",
            "libraries.minecraft.net", "resources.download.minecraft.net"
        ]
        return url.scheme == "https" && permitted.contains(url.host ?? "")
    }

    private func validSHA1(_ value: String) -> Bool {
        value.count == 40 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }

    private static func verify(_ path: URL, sha1: String, size: Int64?) throws -> Bool {
        let file = try FileHandle(forReadingFrom: path)
        defer { try? file.close() }
        var hash = Insecure.SHA1()
        var count: Int64 = 0
        while true {
            let chunk = try file.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            count += Int64(chunk.count)
            hash.update(data: chunk)
        }
        if let size, count != size { return false }
        let result = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return result.caseInsensitiveCompare(sha1) == .orderedSame
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo temporary: URL) {
        guard let id = downloadTask.taskDescription, UUID(uuidString: id) != nil else { return }
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode),
              response.url?.scheme == "https" else {
            worker.async {
                self.fail(id, reason: "Serwer Minecraft zwrócił błędną odpowiedź HTTP")
                self.schedule()
            }
            return
        }

        // Apple removes the temporary URL as soon as this delegate method
        // returns. Move it immediately; hash off the delegate queue later.
        let staged = stagingURL(for: id)
        do {
            try fm.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
            try? fm.removeItem(at: staged)
            try fm.moveItem(at: temporary, to: staged)
            worker.async {
                self.finishStaged(id)
                self.schedule()
            }
        } catch {
            worker.async {
                self.fail(id, reason: "Nie można zapisać pobieranego pliku")
                self.schedule()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        worker.async {
            // If the OS delivered didFinishDownloadingTo, we may already have
            // a staged or fully verified file. Don't count it as failure.
            guard self.plan?.entries.contains(where: { $0.id == id && $0.state != .done }) == true,
                  !self.fm.fileExists(atPath: self.stagingURL(for: id).path) else { return }
            self.fail(id, reason: "Błąd sieci: \(error.localizedDescription)")
            self.schedule()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Each finished, SHA-1-verified file updates visible progress.
        // Deliberately don't publish thousands of per-byte updates to SwiftUI.
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        worker.async {
            // Flush the SHA-1 and status updates before letting iOS suspend us.
            DispatchQueue.main.async {
                let completion = self.backgroundEventCompletion
                self.backgroundEventCompletion = nil
                completion?()
            }
        }
    }
}
