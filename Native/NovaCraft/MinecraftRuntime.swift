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

    func launch(version: String, account: MinecraftAccount?) async throws {
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
                  .appendingPathComponent("NovaLWJGLBridge.framework/NovaLWJGLBridge").path) else {
            throw NovaEngineLaunchError.missingJavaAndRenderer(
                "Java \\(major) jest dostępna, ale brak natywnego mostu LWJGL/Metal. Nie można bezpiecznie uruchomić klienta Minecraft."
            )
        }
        let args = try prepareOfflineArguments(version: version, nickname: nickname)
        let code = await Task.detached(priority: .userInitiated) {
            NovaGameRunner.run(args, javaMajor: major)
        }.value
        guard code == 0 else { throw NovaEngineLaunchError.jvmFailure(code) }
    }
}

enum NovaEngineLaunchError: LocalizedError {
    case incompleteInstallation(String)
    case missingJavaAndRenderer(String)
    case jvmFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .jvmFailure(let code):
            return "Nie udało się uruchomić klasy głównej Minecraft przez JNI (kod: \\(code))."
        case .incompleteInstallation(let report):
            return "NovaEngine: instalacja niekompletna. \(report)"
        case .missingJavaAndRenderer(let report):
            return "NovaEngine: \(report) Gra nie została uruchomiona. Nadal brakuje kompletnego uruchamiania Java i LWJGL/Metal."
        }
    }
}
