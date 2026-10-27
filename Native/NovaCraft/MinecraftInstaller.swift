import Foundation
import CryptoKit

struct MinecraftVersion: Decodable, Identifiable {
    let id: String
    let type: String
    let url: URL
}

private struct VersionManifest: Decodable {
    let versions: [MinecraftVersion]
}

private struct DownloadInfo: Decodable {
    let id: String?
    let url: URL
    let sha1: String
    let size: Int64?
}

private struct Library: Decodable {
    let downloads: LibraryDownloads?
    let rules: [LibraryRule]?
}

private struct LibraryDownloads: Decodable {
    let artifact: LibraryArtifact?
}

private struct LibraryArtifact: Decodable {
    let path: String
    let url: URL
    let sha1: String
    let size: Int64?
}

private struct LibraryRule: Decodable {
    let action: String
    let os: LibraryOS?
}

private struct LibraryOS: Decodable {
    let name: String?
}

private struct VersionDetail: Decodable {
    let downloads: [String: DownloadInfo]
    let assetIndex: DownloadInfo?
    let libraries: [Library]?
}

private struct AssetIndex: Decodable {
    let objects: [String: AssetObject]
}

private struct AssetObject: Decodable {
    let hash: String
    let size: Int64
}

enum InstallError: LocalizedError {
    case invalidManifest
    case badHTTP(Int)
    case checksumMismatch
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "Nieprawidłowy manifest Minecraft"
        case .badHTTP(let status): return "Błąd pobierania HTTP \(status)"
        case .checksumMismatch: return "Nieprawidłowa suma kontrolna pobranego pliku"
        case .invalidFile: return "Nieprawidłowy plik lub ścieżka pobierania"
        }
    }
}

/// Pobiera pliki klienta, biblioteki Java i zasoby Minecraft.
/// Nie instaluje JVM ani bibliotek natywnych LWJGL dla iOS i nie uruchamia gry.
final class MinecraftInstaller {
    private let session: URLSession = .shared
    private let base: URL
    private let fm = FileManager.default

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("NovaCraft", isDirectory: true)
    }

    func isInstalled(_ id: String) -> Bool {
        let folder = versionFolder(id)
        return fm.fileExists(atPath: folder.appendingPathComponent("install-complete").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("client.jar").path)
    }

    func remove(versionID: String) throws {
        let folder = versionFolder(versionID)
        if fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
        // Wspólne biblioteki i assety są współdzielone między wersjami.
    }

    func fetchVersions() async throws -> [MinecraftVersion] {
        let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        let data = try await fetchData(url)
        return try JSONDecoder().decode(VersionManifest.self, from: data).versions
    }

    func install(version: MinecraftVersion, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard isTrusted(version.url, hosts: ["piston-meta.mojang.com"]) else {
            throw InstallError.invalidManifest
        }

        let json = try await fetchData(version.url)
        let detail = try JSONDecoder().decode(VersionDetail.self, from: json)
        guard let client = detail.downloads["client"],
              let assetIndex = detail.assetIndex,
              isTrusted(client.url, hosts: ["piston-data.mojang.com", "launcher.mojang.com"]),
              isTrusted(assetIndex.url, hosts: ["piston-meta.mojang.com", "launchermeta.mojang.com"]) else {
            throw InstallError.invalidManifest
        }

        let folder = versionFolder(version.id)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let complete = folder.appendingPathComponent("install-complete")
        if fm.fileExists(atPath: complete.path) { try fm.removeItem(at: complete) }
        progress(0.02)

        try await downloadVerified(url: client.url, sha1: client.sha1, size: client.size,
                                   destination: folder.appendingPathComponent("client.jar"))
        progress(0.12)

        // Pomijamy biblioteki przypisane do Windows, Linux i macOS.
        // Biblioteki natywne tych systemów nie działają na iOS.
        let libraries = (detail.libraries ?? []).filter(libraryAllowed).compactMap { $0.downloads?.artifact }
        for (index, artifact) in libraries.enumerated() {
            try Task.checkCancellation()
            guard isTrusted(artifact.url, hosts: ["libraries.minecraft.net"]),
                  let components = safeComponents(artifact.path) else {
                throw InstallError.invalidManifest
            }
            let destination = components.reduce(base.appendingPathComponent("libraries", isDirectory: true)) {
                $0.appendingPathComponent($1)
            }
            try await downloadVerified(url: artifact.url, sha1: artifact.sha1,
                                       size: artifact.size, destination: destination)
            progress(0.12 + 0.38 * Double(index + 1) / Double(max(libraries.count, 1)))
        }
        progress(0.50)

        let indexFolder = base.appendingPathComponent("assets/indexes", isDirectory: true)
        // Multiple Minecraft versions can share an asset index whose ID differs
        // from the version ID (for example older releases).
        let indexID = assetIndex.id ?? version.id
        let indexPath = indexFolder.appendingPathComponent(safeID(indexID) + ".json")
        try await downloadVerified(url: assetIndex.url, sha1: assetIndex.sha1,
                                   size: assetIndex.size, destination: indexPath)
        let indexData = try Data(contentsOf: indexPath)
        let index = try JSONDecoder().decode(AssetIndex.self, from: indexData)
        let objects = Array(Set(index.objects.values.map { $0.hash })).sorted()
        let assetInfo = Dictionary(index.objects.values.map { ($0.hash, $0.size) }, uniquingKeysWith: { first, _ in first })

        // Keep network throughput high without creating hundreds of in-flight
        // connections. Asset downloads are independent and verified by SHA-1.
        // Progress is updated on the coordinating task, never by worker tasks.
        let maxConcurrentAssets = 4
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            var completed = 0

            func enqueue(_ hash: String) {
                group.addTask {
                    try Task.checkCancellation()
                    guard self.isSHA1(hash), let size = assetInfo[hash] else {
                        throw InstallError.invalidManifest
                    }
                    let prefix = String(hash.prefix(2))
                    let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)")!
                    let destination = self.base.appendingPathComponent("assets/objects", isDirectory: true)
                        .appendingPathComponent(prefix, isDirectory: true)
                        .appendingPathComponent(hash)
                    try await self.downloadVerified(url: url, sha1: hash, size: size, destination: destination)
                }
            }

            while next < min(maxConcurrentAssets, objects.count) {
                enqueue(objects[next])
                next += 1
            }
            while let _ = try await group.next() {
                completed += 1
                if completed == objects.count || completed % 12 == 0 {
                    progress(0.50 + 0.49 * Double(completed) / Double(max(objects.count, 1)))
                }
                if next < objects.count {
                    enqueue(objects[next])
                    next += 1
                }
            }
        }
        progress(0.99)

        try json.write(to: folder.appendingPathComponent("version.json"), options: .atomic)
        try Data("ok".utf8).write(to: complete, options: .atomic)
        progress(1)
    }

    /// Prepare the manifest and asset index while the app is in the foreground.
    /// Once queued, each large client/library/asset object is downloaded by the
    /// system-owned background URLSession and survives app suspension.
    /// Assets are NEVER extracted or executed; each is verified by SHA-1.
    func prepareBackgroundInstall(version: MinecraftVersion) async throws -> NovaBackgroundPlan {
        guard isTrusted(version.url, hosts: ["piston-meta.mojang.com"]) else {
            throw InstallError.invalidManifest
        }
        let versionData = try await fetchData(version.url)
        let detail = try JSONDecoder().decode(VersionDetail.self, from: versionData)
        guard let client = detail.downloads["client"],
              let assetIndex = detail.assetIndex,
              isTrusted(client.url, hosts: ["piston-data.mojang.com", "launcher.mojang.com"]),
              isTrusted(assetIndex.url, hosts: ["piston-meta.mojang.com", "launchermeta.mojang.com"]),
              isSHA1(client.sha1), isSHA1(assetIndex.sha1) else {
            throw InstallError.invalidManifest
        }

        // The index is relatively small; it is required to enumerate all the
        // actual files and must be retrieved before background queueing begins.
        let indexBytes = try await fetchData(assetIndex.url)
        guard (assetIndex.size == nil || assetIndex.size == Int64(indexBytes.count)),
              Self.sha1(indexBytes).caseInsensitiveCompare(assetIndex.sha1) == .orderedSame
        else { throw InstallError.checksumMismatch }
        let index = try JSONDecoder().decode(AssetIndex.self, from: indexBytes)

        let folder = versionFolder(version.id)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let complete = folder.appendingPathComponent("install-complete")
        // Do not call the install finished until *all* background files have
        // passed checksums and moved to their permanent locations.
        try? fm.removeItem(at: complete)
        try versionData.write(to: folder.appendingPathComponent("version.json"), options: .atomic)

        let indexID = assetIndex.id ?? version.id
        let indexDir = base.appendingPathComponent("assets/indexes", isDirectory: true)
        try fm.createDirectory(at: indexDir, withIntermediateDirectories: true)
        try indexBytes.write(to: indexDir.appendingPathComponent(safeID(indexID) + ".json"),
                             options: .atomic)

        func entry(url: URL, sha1: String, size: Int64?, relativePath: String) -> NovaBackgroundEntry {
            NovaBackgroundEntry(id: UUID().uuidString, source: url, target: relativePath,
                                checksum: sha1, expectedBytes: size, state: .queued, retries: 0)
        }
        var entries: [NovaBackgroundEntry] = []
        entries.append(entry(url: client.url, sha1: client.sha1, size: client.size,
                             relativePath: "versions/\(safeID(version.id))/client.jar"))

        for library in (detail.libraries ?? []).filter(libraryAllowed) {
            guard let artifact = library.downloads?.artifact else { continue }
            guard isTrusted(artifact.url, hosts: ["libraries.minecraft.net"]),
                  isSHA1(artifact.sha1),
                  let path = safeComponents(artifact.path) else { throw InstallError.invalidManifest }
            entries.append(entry(url: artifact.url, sha1: artifact.sha1,
                                 size: artifact.size,
                                 relativePath: "libraries/" + path.joined(separator: "/")))
        }

        // Deduplicate resources by SHA-1; distinct logical paths often point
        // at the same file. Validate all resource URLs before queueing them.
        var unique: [String: Int64] = [:]
        for asset in index.objects.values {
            guard isSHA1(asset.hash), asset.size >= 0 else { throw InstallError.invalidManifest }
            unique[asset.hash.lowercased()] = asset.size
        }
        for (hash, size) in unique.sorted(by: { $0.key < $1.key }) {
            let prefix = String(hash.prefix(2))
            guard let url = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)")
                else { throw InstallError.invalidManifest }
            entries.append(entry(url: url, sha1: hash, size: size,
                                 relativePath: "assets/objects/\(prefix)/\(hash)"))
        }

        return NovaBackgroundPlan(versionID: version.id, entries: entries,
                                  isPaused: false, finished: false, errorMessage: nil)
    }

    private static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Pobieranie na dysk, sprawdzanie SHA-1 i ponowne wykorzystanie poprawnych plików.
    private func downloadVerified(url: URL, sha1: String, size: Int64?,
                                  destination: URL) async throws {
        guard url.scheme == "https", isSHA1(sha1) else { throw InstallError.invalidManifest }
        if fm.fileExists(atPath: destination.path),
           (try? verify(file: destination, sha1: sha1, size: size)) == true {
            return
        }

        try Task.checkCancellation()
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (temporary, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard try verify(file: temporary, sha1: sha1, size: size) else {
            throw InstallError.checksumMismatch
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temporary, to: destination)
    }

    private func verify(file: URL, sha1: String, size: Int64?) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        var length: Int64 = 0
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            length += Int64(chunk.count)
            hasher.update(data: chunk)
        }
        if let size = size, length != size { return false }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return actual.caseInsensitiveCompare(sha1) == .orderedSame
    }

    private func libraryAllowed(_ library: Library) -> Bool {
        guard let rules = library.rules else { return true }
        var allowed = false
        for rule in rules {
            // Reguły dla desktopowych OS nie dotyczą iOS.
            if rule.os?.name != nil { continue }
            allowed = rule.action == "allow"
        }
        return allowed
    }

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func versionFolder(_ id: String) -> URL {
        base.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(safeID(id), isDirectory: true)
    }

    private func isTrusted(_ url: URL, hosts: Set<String>) -> Bool {
        url.scheme == "https" && hosts.contains(url.host ?? "")
    }

    private func isSHA1(_ hash: String) -> Bool {
        hash.count == 40 && hash.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }

    private func safeComponents(_ path: String) -> [String]? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && !part.contains("\\")
                && !part.contains(":") && !part.contains("\0")
        }) else { return nil }
        return parts
    }

    private func safeID(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
