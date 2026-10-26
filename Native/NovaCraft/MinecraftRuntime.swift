import Foundation

protocol MinecraftRuntime {
    func launch(version: String, account: MinecraftAccount?, offlineNickname: String?) async throws
}

struct NovaEngineRuntime: MinecraftRuntime {
    private let root: URL

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft", isDirectory: true)
    }

    /// Preflight checks local version metadata and installed dependencies.
    /// It intentionally refuses to start until a real iOS JVM + graphics bridge exists.
    func inspect(version: String) throws -> NovaEngineLaunchPlan {
        try NovaEngineCore.inspect(versionID: version, root: root)
    }

    func prepareOfflineArguments(version: String, nickname: String) throws -> NovaLaunchArguments {
        try NovaLaunchArgumentBuilder.build(version: version, root: root, nickname: nickname)
    }

    func launch(version: String, account: MinecraftAccount?, offlineNickname: String?) async throws {
        let plan = try inspect(version: version)
        if !plan.missingLibraries.isEmpty || !plan.hasAssetIndex {
            throw NovaEngineLaunchError.incompleteInstallation(plan.summary)
        }
        guard let nickname = offlineNickname else {
            throw NovaEngineLaunchError.missingJavaAndRenderer("Wybierz profil offline. Start przez konto Microsoft wymaga jeszcze przekazania tokenu gry do JVM.")
        }
        guard let major = NovaJavaRuntimeRegistry.requiredMajor(for: plan),
              let java = NovaJavaRuntimeRegistry.frameworkURL(major: major),
              FileManager.default.fileExists(atPath: java.path) else {
            throw NovaEngineLaunchError.missingJavaAndRenderer(NovaJavaRuntimeRegistry.availability(for: plan))
        }
        guard let frameworks = Bundle.main.privateFrameworksURL,
              FileManager.default.fileExists(atPath: frameworks
                  .appendingPathComponent("liblwjgl.dylib").path),
              FileManager.default.fileExists(atPath: Bundle.main.bundleURL
                  .appendingPathComponent("LWJGL-iOS", isDirectory: true).path) else {
            throw NovaEngineLaunchError.missingJavaAndRenderer(
                "Java \(major) jest dostępna, ale brak bibliotek LWJGL dla iOS. Nie można bezpiecznie uruchomić klienta Minecraft."
            )
        }
        // The iOS app bundle is read-only. Minecraft needs a writable game
        // directory before its settings, resource cache and logs are created.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("game", isDirectory: true),
            withIntermediateDirectories: true
        )
        let args = try prepareOfflineArguments(version: version, nickname: nickname)
        // A Java VM can live for hours and may initialize deep native stack
        // frames. Never occupy a Swift cooperative-concurrency worker thread.
        // Use one dedicated POSIX-backed NSThread with a predictable stack.
        let startTime = ProcessInfo.processInfo.systemUptime
        let code = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let javaThread = Thread {
                let result = NovaGameRunner.run(args, javaMajor: major)
                continuation.resume(returning: result)
            }
            javaThread.name = "NovaCraft-Java-\(major)"
            javaThread.stackSize = 16 * 1024 * 1024
            javaThread.qualityOfService = .userInitiated
            javaThread.start()
        }
        guard code == 0 else { throw NovaEngineLaunchError.jvmFailure(code) }
        let runtimeSeconds = ProcessInfo.processInfo.systemUptime - startTime
        if runtimeSeconds < 10 {
            throw NovaEngineLaunchError.gameExitedImmediately(runtimeSeconds)
        }
    }
}

enum NovaEngineLaunchError: LocalizedError {
    case incompleteInstallation(String)
    case missingJavaAndRenderer(String)
    case jvmFailure(Int32)
    case gameExitedImmediately(Double)

    var errorDescription: String? {
        switch self {
        case .gameExitedImmediately(let duration):
            return "Java zakończyła działanie po \(String(format: "%.1f", duration)) s (kod 0), ale nie pojawiło się okno Minecrafta. Zobacz dziennik Java poniżej."
        case .jvmFailure(let code):
            return "Nie udało się uruchomić Minecraft przez JVM (JNI/JLI) (kod: \(code))."
        case .incompleteInstallation(let report):
            return "NovaEngine: instalacja niekompletna. \(report)"
        case .missingJavaAndRenderer(let report):
            return "NovaEngine: \(report) Gra nie została uruchomiona. Nadal brakuje kompletnego uruchamiania Java i LWJGL/Metal."
        }
    }
}
