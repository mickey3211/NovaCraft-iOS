import Foundation
import CryptoKit

/// Builds the Minecraft Java command-line from downloaded official metadata.
/// This is an argument resolver, not a JVM or executable game runtime.
struct NovaLaunchArguments {
    let mainClass: String
    let classpath: String
    let gameArguments: [String]
    let jvmArguments: [String]
    let javaMajor: Int?
    let assetsIndexID: String

    var safeSummary: String {
        "Klasa: \(mainClass) • Java \(javaMajor.map(String.init) ?? "?") • JAR: \(classpath.split(separator: ":").count) • argumenty gry: \(gameArguments.count), JVM: \(jvmArguments.count) • zasoby: \(assetsIndexID)"
    }
}

enum NovaLaunchArgumentsError: LocalizedError {
    case invalidMetadata
    case missingIdentity
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidMetadata: return "Nie udało się przygotować argumentów uruchomieniowych."
        case .missingIdentity: return "Wybierz profil offline lub zaloguj się do Microsoft."
        case .unsupportedVersion: return "Ta wersja ma nieobsługiwany format argumentów."
        }
    }
}

enum NovaLaunchArgumentBuilder {
    static func build(version: String, root: URL, nickname: String?, account: MinecraftAccount? = nil) throws -> NovaLaunchArguments {
        let plan = try NovaEngineCore.inspect(versionID: version, root: root)
        let playerName = account?.username ?? nickname
        guard let nickname = playerName, OfflineProfile.isValid(nickname) else {
            throw NovaLaunchArgumentsError.missingIdentity
        }
        let path = root.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("version.json")
        let data = try Data(contentsOf: path)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NovaLaunchArgumentsError.invalidMetadata
        }
        let assetID = (json["assetIndex"] as? [String: Any])?["id"] as? String ?? version
        let assetRoot = root.appendingPathComponent("assets", isDirectory: true)
        let gameDir = root.appendingPathComponent("game", isDirectory: true)
        let uuid: String
        let accessToken: String
        if let account {
            let normalized = account.uuid.replacingOccurrences(of: "-", with: "").lowercased()
            guard normalized.count == 32,
                  normalized.allSatisfy({ "0123456789abcdef".contains($0) }),
                  !account.minecraftAccessToken.isEmpty else {
                throw NovaLaunchArgumentsError.missingIdentity
            }
            uuid = normalized
            accessToken = account.minecraftAccessToken
        } else {
            uuid = offlineUUID(for: nickname).uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            accessToken = "0"
        }
        let values: [String: String] = [
            "auth_player_name": nickname,
            "version_name": version,
            "game_directory": gameDir.path,
            "assets_root": assetRoot.path,
            "assets_index_name": assetID,
            "auth_uuid": uuid,
            "auth_access_token": accessToken,
            "clientid": "",
            "auth_xuid": "",
            "user_type": account == nil ? "legacy" : "msa",
            "version_type": "release",
            "user_properties": "{}",
            "resolution_width": "1280",
            "resolution_height": "720",
            "classpath": plan.classpath.map(\.path).joined(separator: ":"),
            "classpath_separator": ":",
            "library_directory": root.appendingPathComponent("libraries", isDirectory: true).path,
            "natives_directory": root.appendingPathComponent("natives", isDirectory: true).path,
            "launcher_name": "NovaCraft",
            "launcher_version": "1.0"
        ]
        let args: [String]
        if let modern = (json["arguments"] as? [String: Any])?["game"] as? [Any] {
            args = modern.flatMap { entry -> [String] in
                if let literal = entry as? String { return [literal] }
                guard let object = entry as? [String: Any],
                      let rules = object["rules"] as? [[String: Any]],
                      ruleAllows(rules) else { return [] }
                if let value = object["value"] as? String { return [value] }
                return object["value"] as? [String] ?? []
            }
        } else if let legacy = json["minecraftArguments"] as? String {
            args = legacy.split(separator: " ").map(String.init)
        } else {
            throw NovaLaunchArgumentsError.unsupportedVersion
        }
        let expanded = args.map { argument in
            values.reduce(argument) { text, pair in
                text.replacingOccurrences(of: "${\(pair.key)}", with: pair.value)
            }
        }
        // Resolve JVM options independently from game arguments. The official
        // manifest has different JVM options for each Minecraft generation.
        let jvmEntries = ((json["arguments"] as? [String: Any])?["jvm"] as? [Any]) ?? []
        let jvmRaw: [String] = jvmEntries.flatMap { entry -> [String] in
            if let literal = entry as? String { return [literal] }
            guard let object = entry as? [String: Any],
                  let rules = object["rules"] as? [[String: Any]],
                  ruleAllows(rules) else { return [] }
            if let value = object["value"] as? String { return [value] }
            return object["value"] as? [String] ?? []
        }
        let jvmExpanded = jvmRaw.map { argument in
            values.reduce(argument) { text, pair in
                text.replacingOccurrences(of: "${\(pair.key)}", with: pair.value)
            }
        }
        // Older versions do not define JVM arguments in version.json.
        let jvmArguments = jvmExpanded.isEmpty
            ? ["-cp", plan.classpath.map(\.path).joined(separator: ":")]
            : jvmExpanded
        // Fail closed rather than pass unresolved placeholders to a future JVM.
        guard !expanded.contains(where: { $0.contains("${") }),
              !jvmArguments.contains(where: { $0.contains("${") }) else {
            throw NovaLaunchArgumentsError.invalidMetadata
        }
        return NovaLaunchArguments(
            mainClass: plan.mainClass,
            classpath: plan.classpath.map(\.path).joined(separator: ":"),
            gameArguments: expanded,
            jvmArguments: jvmArguments,
            javaMajor: plan.requiredJavaMajor,
            assetsIndexID: assetID
        )
    }

    private static func ruleAllows(_ rules: [[String: Any]]) -> Bool {
        var allowed = false
        for rule in rules {
            if rule["os"] != nil { continue }
            if let features = rule["features"] as? [String: Bool],
               features.values.contains(true) { continue }
            allowed = (rule["action"] as? String) == "allow"
        }
        return allowed
    }

    /// Matches Java UUID.nameUUIDFromBytes("OfflinePlayer:" + name), local identity only.
    private static func offlineUUID(for name: String) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data(("OfflinePlayer:" + name).utf8)))
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}
