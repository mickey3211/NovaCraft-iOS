import Foundation

protocol MinecraftRuntime {
    func launch(version: String, account: MinecraftAccount?) async throws
}

struct RuntimeUnavailable: LocalizedError {
    var errorDescription: String? {
        "Brak JVM i mostu LWJGL dla iOS. NovaCraft nie może jeszcze uruchomić Minecraft Java ani połączyć się z serwerami."
    }
}

/// An explicit fail-closed runtime boundary, not a simulated game launcher.
struct UnavailableMinecraftRuntime: MinecraftRuntime {
    func launch(version: String, account: MinecraftAccount?) async throws {
        throw RuntimeUnavailable()
    }
}
