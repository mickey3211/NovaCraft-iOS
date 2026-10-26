import Foundation

/// NovaEngine 0.1: inspects the official, locally installed Minecraft metadata.
/// This is a launch *preflight*, not a Java virtual machine or graphics renderer.
struct NovaEngineLaunchPlan {
    let versionID: String
    let mainClass: String
    let requiredJavaMajor: Int?
    let classpath: [URL]
    let missingLibraries: [String]
    let argumentsFormat: String
    let hasAssetIndex: Bool

    var summary: String {
        let java = requiredJavaMajor.map { "Java \($0)" } ?? "Java: nieokreślona w manifeście"
        let files = missingLibraries.isEmpty
            ? "biblioteki dostępne"
            : "brakuje \(missingLibraries.count) bibliotek"
        let assets = hasAssetIndex ? "indeks zasobów dostępny" : "brak indeksu zasobów"
        return "\(versionID): \(java), \(files), \(assets), argumenty: \(argumentsFormat)"
    }
}

enum NovaEnginePreflightError: LocalizedError {
    case invalidVersionID
    case notInstalled
    case invalidMetadata
    case missingMainClass
    case unsupportedArguments

    var errorDescription: String? {
        switch self {
        case .invalidVersionID: return "Nieprawidłowy identyfikator wersji."
        case .notInstalled: return "Najpierw pobierz pliki tej wersji Minecraft."
        case .invalidMetadata: return "Nie można odczytać metadanych zainstalowanej wersji."
        case .missingMainClass: return "Manifest Minecraft nie zawiera klasy startowej."
        case .unsupportedArguments: return "Manifest nie zawiera obsługiwanego formatu argumentów startowych."
        }
    }
}

private struct NovaVersionMetadata: Decodable {
    let mainClass: String?
    let javaVersion: JavaVersion?
    let arguments: Arguments?
    let minecraftArguments: String?
    let libraries: [Library]?

    struct JavaVersion: Decodable {
        let majorVersion: Int
    }
    struct Arguments: Decodable {
        let game: [Argument]?
        let jvm: [Argument]?
    }
    // Modern manifests mix plain strings and rule-controlled objects.
    enum Argument: Decodable {
        case literal(String)
        case conditional

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .literal(value)
            } else if (try? container.decode([String: JSONValue].self)) != nil {
                self = .conditional
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Minecraft argument")
            }
        }
    }
    struct JSONValue: Decodable {
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { return }
            if (try? container.decode(String.self)) != nil { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode([JSONValue].self)) != nil { return }
            if (try? container.decode([String: JSONValue].self)) != nil { return }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSON")
        }
    }
    struct Library: Decodable {
        let downloads: Downloads?
        let rules: [Rule]?
    }
    struct Downloads: Decodable {
        let artifact: Artifact?
    }
    struct Artifact: Decodable {
        let path: String
    }
    struct Rule: Decodable {
        let action: String
        let os: OS?
    }
    struct OS: Decodable {
        let name: String?
    }
}

enum NovaEngineCore {
    static func inspect(versionID: String, root: URL) throws -> NovaEngineLaunchPlan {
        guard isSafeID(versionID) else { throw NovaEnginePreflightError.invalidVersionID }
        let folder = root.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(versionID, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("install-complete").path),
              fm.fileExists(atPath: folder.appendingPathComponent("client.jar").path) else {
            throw NovaEnginePreflightError.notInstalled
        }
        let metadata: NovaVersionMetadata
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent("version.json"))
            metadata = try JSONDecoder().decode(NovaVersionMetadata.self, from: data)
        } catch {
            throw NovaEnginePreflightError.invalidMetadata
        }
        guard let mainClass = metadata.mainClass, !mainClass.isEmpty else {
            throw NovaEnginePreflightError.missingMainClass
        }
        let argumentsFormat: String
        if metadata.arguments?.game != nil {
            argumentsFormat = "modern"
        } else if metadata.minecraftArguments != nil {
            argumentsFormat = "legacy"
        } else {
            throw NovaEnginePreflightError.unsupportedArguments
        }

        var classpath: [URL] = []
        var missing: [String] = []
        for library in metadata.libraries ?? [] where isAllowed(library) {
            guard let artifact = library.downloads?.artifact else { continue }
            guard let parts = safePath(artifact.path) else {
                throw NovaEnginePreflightError.invalidMetadata
            }
            let url = parts.reduce(root.appendingPathComponent("libraries", isDirectory: true)) {
                $0.appendingPathComponent($1)
            }
            if fm.fileExists(atPath: url.path) {
                classpath.append(url)
            } else {
                missing.append(artifact.path)
            }
        }
        classpath.append(folder.appendingPathComponent("client.jar"))
        let assets = root.appendingPathComponent("assets/indexes", isDirectory: true)
            .appendingPathComponent(versionID + ".json")
        return NovaEngineLaunchPlan(
            versionID: versionID,
            mainClass: mainClass,
            requiredJavaMajor: metadata.javaVersion?.majorVersion,
            classpath: classpath,
            missingLibraries: missing,
            argumentsFormat: argumentsFormat,
            hasAssetIndex: fm.fileExists(atPath: assets.path)
        )
    }

    private static func isAllowed(_ library: NovaVersionMetadata.Library) -> Bool {
        guard let rules = library.rules else { return true }
        var allowed = false
        for rule in rules {
            if rule.os?.name != nil { continue }
            allowed = rule.action == "allow"
        }
        return allowed
    }

    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".." && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0)
        }
    }

    private static func safePath(_ path: String) -> [String]? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":")
        }) else { return nil }
        return parts
    }
}
