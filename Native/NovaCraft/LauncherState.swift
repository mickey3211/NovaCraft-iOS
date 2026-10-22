import Foundation
import SwiftUI

@MainActor
final class LauncherState: ObservableObject {
    @Published var versions: [MinecraftVersion] = []
    @Published var selectedVersion = ""
    @Published var installed: Set<String> = []
    @Published var downloadProgress: Double = 0
    @Published var busy = false
    @Published var message = "Gotowy"
    @Published var account: MinecraftAccount?
    @Published var servers: [SavedServer] = [] {
        didSet { if let data = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(data, forKey: "servers") } }
    }

    let installer = MinecraftInstaller()
    let authentication = MicrosoftMinecraftAuth()
    let runtime: any MinecraftRuntime = UnavailableMinecraftRuntime()

    init() {
        selectedVersion = UserDefaults.standard.string(forKey: "version") ?? ""
        if let data = UserDefaults.standard.data(forKey: "servers"),
           let stored = try? JSONDecoder().decode([SavedServer].self, from: data) { servers = stored }
        Task { await refresh() }
    }

    func refresh() async {
        do {
            versions = try await installer.fetchVersions()
            installed = Set(versions.filter { installer.isInstalled($0.id) }.map(\.id))
            if selectedVersion.isEmpty { selectedVersion = versions.first(where: { $0.type == "release" })?.id ?? "" }
            message = "Pobrano listę wersji"
        } catch { message = "Nie udało się pobrać manifestu: \(error.localizedDescription)" }
    }

    func select(_ id: String) {
        selectedVersion = id
        UserDefaults.standard.set(id, forKey: "version")
    }

    func installSelected() async {
        guard let version = versions.first(where: { $0.id == selectedVersion }) else { return }
        busy = true
        downloadProgress = 0
        defer { busy = false }
        do {
            try await installer.install(version: version) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            installed.insert(version.id)
            message = "Pobrano pliki klienta \(version.id) — nie oznacza to, że gra jest uruchamialna"
        } catch { message = "Błąd instalacji: \(error.localizedDescription)" }
    }

    func signIn() async {
        do {
            account = try await authentication.signIn()
            message = "Zalogowano: \(account?.username ?? "")"
        } catch { message = "Logowanie nieudane: \(error.localizedDescription)" }
    }

    func launch() async {
        do {
            try await runtime.launch(version: selectedVersion, account: account)
        } catch { message = error.localizedDescription }
    }

    func addServer(name: String, address: String) {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !clean.isEmpty, clean.count <= 253 else { return }
        servers.append(SavedServer(name: name, address: clean))
    }
}

struct SavedServer: Identifiable, Codable {
    var id = UUID()
    let name: String
    let address: String
}
