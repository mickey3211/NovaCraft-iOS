import Foundation

/// Builds the Minecraft Java command-line from downloaded official metadata.
/// This is an argument resolver, not a JVM or executable game runtime.
struct NovaLaunchArguments {
    let mainClass: String
    let classpath: String
    let gameArguments: [String]
    let javaMajor: Int?
    let assetsIndexID: String

    var safeSummary: String {
        "Klasa: \(mainClass) • Java \(javaMajor.map(String.init) ?? "?") • JAR: \(classpath.split(separator: ":").count) • argumenty: \(gameArguments.count) • zasoby: \(assetsIndexID)"
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
    static func build(version: String, root: URL, nickname: String?) throws -> NovaLaunchArguments {
        let plan = try NovaEngineCore.inspect(versionID: version, root: root)
        guard let nickname, OfflineProfile.isValid(nickname) else {
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
        let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let uuid = offlineUUID(for: nickname, namespace: identity)
        let values: [String: String] = [
            "auth_player_name": nickname,
            "version_name": version,
            "game_directory": gameDir.path,
            "assets_root": assetRoot.path,
            "assets_index_name": assetID,
            "auth_uuid": uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "auth_access_token": "0",
            "clientid": "",
            "auth_xuid": "",
            "user_type": "legacy",
            "version_type": "release",
            "user_properties": "{}",
            "resolution_width": "1280",
            "resolution_height": "720"
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
        // Fail closed rather than pass unresolved placeholders to a future JVM.
        guard !expanded.contains(where: { $0.contains("${") }) else {
            throw NovaLaunchArgumentsError.invalidMetadata
        }
        return NovaLaunchArguments(
            mainClass: plan.mainClass,
            classpath: plan.classpath.map(\.path).joined(separator: ":"),
            gameArguments: expanded,
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

    /// Stable offline UUID based on username, without pretending to be a Microsoft identity.
    private static func offlineUUID(for name: String, namespace: UUID) -> UUID {
        // This deterministic UUID is local-only. It is not a verified player UUID.
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in ("OfflinePlayer:" + name).utf8.enumerated() {
            let slot = index % 16
            bytes[slot] = (bytes[slot] &* 31) &+ byte
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}
