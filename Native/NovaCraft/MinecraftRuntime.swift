import Foundation

protocol MinecraftRuntime {
    func launch(version: String, account: MinecraftAccount?) async throws
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
        throw NovaEngineLaunchError.missingJavaAndRenderer(NovaJavaRuntimeRegistry.availability(for: plan))
    }
}

enum NovaEngineLaunchError: LocalizedError {
    case incompleteInstallation(String)
    case missingJavaAndRenderer(String)

    var errorDescription: String? {
        switch self {
        case .incompleteInstallation(let report):
            return "NovaEngine: instalacja niekompletna. \(report)"
        case .missingJavaAndRenderer(let report):
            return "NovaEngine: \(report) Gra nie została uruchomiona. Nadal brakuje kompletnego uruchamiania Java i LWJGL/Metal."
        }
    }
}
