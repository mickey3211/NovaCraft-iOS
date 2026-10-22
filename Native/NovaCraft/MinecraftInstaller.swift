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
    let url: URL
    let sha1: String
    let size: Int64?
}
private struct VersionDetail: Decodable {
    let downloads: [String: DownloadInfo]
    let assetIndex: DownloadInfo?
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
        case .invalidFile: return "Brak pliku klienta w manifeście"
        }
    }
}

/// Downloads a verified client JAR and version JSON from Mojang.
/// Does NOT yet install libraries, natives, asset objects or a Java runtime.
final class MinecraftInstaller {
    private let session: URLSession = .shared
    private let base: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("NovaCraft", isDirectory: true)
    }

    func isInstalled(_ id: String) -> Bool {
        let safe = safeID(id)
        return FileManager.default.fileExists(atPath: base.appendingPathComponent("versions/\(safe)/client.jar").path)
    }

    func fetchVersions() async throws -> [MinecraftVersion] {
        let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        let data = try await fetchData(url)
        return try JSONDecoder().decode(VersionManifest.self, from: data).versions
    }

    func install(version: MinecraftVersion, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard version.url.scheme == "https", version.url.host == "piston-meta.mojang.com" else {
            throw InstallError.invalidManifest
        }
        let json = try await fetchData(version.url)
        let detail = try JSONDecoder().decode(VersionDetail.self, from: json)
        guard let client = detail.downloads["client"] else { throw InstallError.invalidFile }
        guard client.url.scheme == "https", ["piston-data.mojang.com", "launcher.mojang.com"].contains(client.url.host ?? "") else {
            throw InstallError.invalidManifest
        }
        let folder = base.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(safeID(version.id), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        progress(0.1)
        let (temporary, response) = try await session.download(from: client.url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        progress(0.75)
        let bytes = try Data(contentsOf: temporary)
        if let size = client.size, Int64(bytes.count) != size { throw InstallError.invalidFile }
        let actual = Insecure.SHA1.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(client.sha1) == .orderedSame else {
            throw InstallError.checksumMismatch
        }
        let destination = folder.appendingPathComponent("client.jar")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try json.write(to: folder.appendingPathComponent("version.json"), options: .atomic)
        progress(1)
    }

    private func fetchData(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw InstallError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func safeID(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
