import Foundation

@main
struct NovaLaunchIdentityTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("versions/1.21.5")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("install-complete"))
        try Data().write(to: folder.appendingPathComponent("client.jar"))
        let metadata = #"""
        {"mainClass":"net.minecraft.client.main.Main","javaVersion":{"majorVersion":21},
         "libraries":[],"arguments":{"game":["--username","${auth_player_name}",
          "--uuid","${auth_uuid}","--accessToken","${auth_access_token}","--userType","${user_type}"],
          "jvm":["-cp","${classpath}"]}}
        """#
        try Data(metadata.utf8).write(to: folder.appendingPathComponent("version.json"))
        let account = MinecraftAccount(username: "OnlinePlayer", uuid: "00112233-4455-6677-8899-AABBCCDDEEFF", minecraftAccessToken: "synthetic-token-not-real")
        let online = try NovaLaunchArgumentBuilder.build(version: "1.21.5", root: root, nickname: "LocalPlayer", account: account)
        precondition(online.gameArguments == ["--username", "OnlinePlayer", "--uuid", "00112233445566778899aabbccddeeff", "--accessToken", "synthetic-token-not-real", "--userType", "msa"])
        precondition(!online.safeSummary.contains(account.minecraftAccessToken))
        let offline = try NovaLaunchArgumentBuilder.build(version: "1.21.5", root: root, nickname: "LocalPlayer")
        precondition(offline.gameArguments[1] == "LocalPlayer")
        precondition(offline.gameArguments[5] == "0")
        precondition(offline.gameArguments[7] == "legacy")
        precondition(offline.gameArguments[3].count == 32)
        for invalid in [
            MinecraftAccount(username: "OnlinePlayer", uuid: "bad", minecraftAccessToken: "token"),
            MinecraftAccount(username: "OnlinePlayer", uuid: account.uuid, minecraftAccessToken: "")
        ] {
            do {
                _ = try NovaLaunchArgumentBuilder.build(version: "1.21.5", root: root, nickname: "LocalPlayer", account: invalid)
                fatalError("Invalid account silently accepted or downgraded to offline")
            } catch NovaLaunchArgumentsError.missingIdentity { }
        }
        print("NovaCraft launch identity checks passed")
    }
}
