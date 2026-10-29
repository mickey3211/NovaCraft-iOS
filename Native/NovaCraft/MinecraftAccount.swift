import Foundation

struct MinecraftAccount {
    let username: String
    let uuid: String
    /// Token is held in memory only. Production app should use Keychain for persistent sessions.
    let minecraftAccessToken: String
}

