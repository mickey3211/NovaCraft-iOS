import Foundation

enum NovaZeroClient {
    static func launch(_ args: NovaLaunchArguments, root: URL) async throws {
        let bundle = Bundle.main.bundleURL
        let native = bundle.appendingPathComponent("Frameworks")
        let jarRoot = bundle.appendingPathComponent("LWJGL-iOS")
        let required = ["libopenal.dylib", "libglfw.dylib", "libmobileglues.dylib", "liblwjgl.dylib", "liblwjgl_opengl.dylib", "liblwjgl_stb.dylib", "libEGL.framework/libEGL", "libGLESv2.framework/libGLESv2"]
        for file in required where !FileManager.default.fileExists(atPath: native.appendingPathComponent(file).path) {
            throw MinecraftClientError.message("Brak biblioteki w IPA: \(file).")
        }
        let jars = try FileManager.default.contentsOfDirectory(at: jarRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jar" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard jars.contains(where: { $0.lastPathComponent == "lwjgl.jar" }) else {
            throw MinecraftClientError.message("Brak bibliotek Java LWJGL w IPA.")
        }
        let original = args.classpath.split(separator: ":").map(String.init).filter {
            let name = URL(fileURLWithPath: $0).lastPathComponent
            return name != "lwjgl.jar" && !name.hasPrefix("lwjgl-") && !name.hasPrefix("lwjgl3-") && !name.hasPrefix("lwjglx-")
        }
        let classpath = ([bundle.appendingPathComponent("NovaZeroSmoke.jar").path] + jars.map(\.path) + original).joined(separator: ":")
        let game = root.appendingPathComponent("game")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        var options = NovaGameRunner.normalizeJVMOptions(args.jvmArguments).filter {
            !$0.hasPrefix("-Xmx") && !$0.hasPrefix("-Xms") && !$0.hasPrefix("-Djava.home=")
        }
        options += ["-Xms64m", "-Xmx\(min(NovaPerformance.heapMB, 768))m", "-XX:+UseSerialGC",
                    "-Djava.class.path=\(classpath)", "-Djava.library.path=\(native.path)",
                    "-Dorg.lwjgl.librarypath=\(native.path)",
                    "-Dorg.lwjgl.glfw.libname=\(native.appendingPathComponent("libglfw.dylib").path)",
                    "-Dorg.lwjgl.opengl.libname=\(native.appendingPathComponent("libmobileglues.dylib").path)",
                    "-Dorg.lwjgl.openal.libname=\(native.appendingPathComponent("libopenal.dylib").path)",
                    "-Dorg.lwjgl.glfw.checkThread0=false", "-Dorg.lwjgl.system.allocator=system",
                    "-Duser.dir=\(game.path)", "-Duser.home=\(root.path)",
                    "--enable-native-access=ALL-UNNAMED", "-Dorg.lwjgl.util.DebugLoader=true"]
        let payload: [String: Any] = ["mainClass": "dev.novacraft.client.NovaClientEntrypoint", "options": options, "arguments": [args.mainClass] + args.gameArguments, "gameDirectory": game.path]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else { throw MinecraftClientError.message("Nie można przygotować startu gry.") }
        try await NovaClientSurface.shared.prepare()
        let code: Int32 = await withCheckedContinuation { continuation in
            let thread = Thread {
                let result = json.withCString { nova_zero_run_client($0) }
                continuation.resume(returning: result)
            }
            thread.name = "NovaCraft-Minecraft-Zero"
            thread.stackSize = 16 * 1024 * 1024
            thread.start()
        }
        await NovaClientSurface.shared.finish()
        guard code == 0 else {
            if code == -90 { throw MinecraftClientError.message("Java była już uruchomiona. Zamknij i ponownie otwórz NovaCraft.") }
            throw MinecraftClientError.message("Uruchamianie klienta zakończyło się błędem \(code). Szczegóły są w dzienniku Java.")
        }
    }
}
enum MinecraftClientError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
