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
        #if NOVA_ZERO_INTEGRATION
        let diagnostic = await NovaZeroLaunchDiagnostics.run(version: version)
        if diagnostic.version != version {
            throw NovaEngineLaunchError.missingJavaAndRenderer(
                "Raport dotyczy wersji \(diagnostic.version). Zamknij i ponownie otwórz aplikację, aby sprawdzić inną wersję."
            )
        }
        guard diagnostic.status == 0 else {
            throw NovaEngineLaunchError.missingJavaAndRenderer(
                "Nie udało się przygotować środowiska Java (kod \(diagnostic.status)). Szczegóły: Ustawienia → Raport diagnostyczny."
            )
        }
        throw NovaEngineLaunchError.missingJavaAndRenderer(
            "Zapisano raport uruchomienia. Ten build zawiera ograniczone środowisko Java Zero; pełne moduły Java i obsługa grafiki Minecraft są nadal niedostępne. Szczegóły: Ustawienia → Raport diagnostyczny."
        )
        #else
        // The pure VM test must be possible without downloading Minecraft,
        // signing in to Microsoft, loading LWJGL or having an offline profile.
        if UserDefaults.standard.bool(forKey: "novacraft-jvm-probe-only") {
            guard let java = NovaJavaRuntimeRegistry.frameworkURL(major: 21),
                  FileManager.default.fileExists(atPath: java.path),
                  FileManager.default.fileExists(atPath:
                    Bundle.main.bundleURL.appendingPathComponent("NovaBootstrap/novacraft-bootstrap.jar").path)
            else {
                throw NovaEngineLaunchError.missingJavaAndRenderer("Brak kompletnej Java 21 albo klasy diagnostycznej w IPA.")
            }
            let minimal = NovaLaunchArguments(
                mainClass: "dev.novacraft.GameEntrypoint",
                classpath: "",
                gameArguments: [],
                jvmArguments: [],
                javaMajor: 21,
                assetsIndexID: "probe")
            let result = await invokeJava(minimal, major: 21)
            guard result == 0 else { throw NovaEngineLaunchError.jvmFailure(result) }
            return
        }
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
        // JNI_CreateJavaVM avoids the Apple JLI main() re-entry which killed
        // the SwiftUI AppGraph before Java had run its entrypoint.
        let code = await invokeJava(args, major: major)
        guard code == 0 else { throw NovaEngineLaunchError.jvmFailure(code) }
        // Probe mode runs only the bundled Java bootstrap. The JVM cannot be
        // restarted in the same process; users must relaunch NovaCraft before
        // trying Minecraft again.
        if UserDefaults.standard.bool(forKey: "novacraft-jvm-probe-only") { return }
        let runtimeSeconds = ProcessInfo.processInfo.systemUptime - startTime
        if runtimeSeconds < 10 {
            throw NovaEngineLaunchError.gameExitedImmediately(runtimeSeconds)
        }
        #endif
    }

    private func invokeJava(_ arguments: NovaLaunchArguments, major: Int) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let javaThread = Thread {
                let result = NovaGameRunner.run(arguments, javaMajor: major)
                continuation.resume(returning: result)
            }
            javaThread.name = "NovaCraft-Java-\(major)"
            javaThread.stackSize = 16 * 1024 * 1024
            javaThread.qualityOfService = .userInitiated
            javaThread.start()
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
