import Foundation

@main
struct NovaEngineSmoke {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let version = root.appendingPathComponent("versions/1.21.4")
        let library = root.appendingPathComponent("libraries/example/test/1.0/test-1.0.jar")
        let assets = root.appendingPathComponent("assets/indexes/1.21.4.json")
        for directory in [version, library.deletingLastPathComponent(), assets.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("ok".utf8).write(to: version.appendingPathComponent("install-complete"))
        try Data("jar".utf8).write(to: version.appendingPathComponent("client.jar"))
        try Data("jar".utf8).write(to: library)
        try Data("{}".utf8).write(to: assets)

        let metadata = #"""
        {
          "mainClass": "net.minecraft.client.main.Main",
          "javaVersion": { "component": "java-runtime-delta", "majorVersion": 21 },
          "arguments": {
            "game": ["--username", "${auth_player_name}", {"rules": [{"action": "allow"}], "value": "--demo"}],
            "jvm": ["-cp", "${classpath}"]
          },
          "libraries": [
            {"downloads": {"artifact": {"path": "example/test/1.0/test-1.0.jar"}}},
            {"downloads": {"artifact": {"path": "example/missing/1.0/missing.jar"}}}
          ]
        }
        """#
        try Data(metadata.utf8).write(to: version.appendingPathComponent("version.json"))
        let plan = try NovaEngineCore.inspect(versionID: "1.21.4", root: root)
        precondition(plan.requiredJavaMajor == 21)
        precondition(plan.mainClass == "net.minecraft.client.main.Main")
        precondition(plan.argumentsFormat == "modern")
        precondition(plan.classpath.count == 2)
        precondition(plan.missingLibraries.count == 1)
        precondition(plan.hasAssetIndex)

        do {
            _ = try NovaEngineCore.inspect(versionID: "..", root: root)
            fatalError("Unsafe version ID accepted")
        } catch NovaEnginePreflightError.invalidVersionID {
            // Expected.
        }
        print("NovaEngine 0.1 smoke tests passed")
    }
}
