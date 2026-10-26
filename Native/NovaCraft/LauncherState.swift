import Foundation
import SwiftUI

@MainActor
final class LauncherState: ObservableObject {
    @Published var versions: [MinecraftVersion] = []
    @Published var selectedVersion = ""
    @Published var installed: Set<String> = []
    @Published var downloadProgress: Double = 0
    @Published var busy = false
    @Published var refreshing = false
    @Published var message = "Gotowy"
    @Published var account: MinecraftAccount?
    @Published var offlineProfiles: [OfflineProfile] = [] {
        didSet { if let data = try? JSONEncoder().encode(offlineProfiles) { UserDefaults.standard.set(data, forKey: "offline-profiles") } }
    }
    @Published var selectedOfflineID: UUID? {
        didSet { UserDefaults.standard.set(selectedOfflineID?.uuidString, forKey: "offline-selected") }
    }
    @Published var serverProbeStatus = "Nie sprawdzono serwera"
    @Published var servers: [SavedServer] = [] {
        didSet { if let data = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(data, forKey: "servers") } }
    }

    let installer = MinecraftInstaller()
    let authentication = MicrosoftMinecraftAuth()
    let runtime = NovaEngineRuntime()

    init() {
        selectedVersion = UserDefaults.standard.string(forKey: "version") ?? ""
        if let data = UserDefaults.standard.data(forKey: "servers"),
           let stored = try? JSONDecoder().decode([SavedServer].self, from: data) { servers = stored }
        if let data = UserDefaults.standard.data(forKey: "offline-profiles"),
           let saved = try? JSONDecoder().decode([OfflineProfile].self, from: data) { offlineProfiles = saved }
        if let id = UserDefaults.standard.string(forKey: "offline-selected") { selectedOfflineID = UUID(uuidString: id) }
        Task { await refresh() }
    }

    var selectedInstalled: Bool { installed.contains(selectedVersion) }

    var activeOfflineProfile: OfflineProfile? { offlineProfiles.first { $0.id == selectedOfflineID } }

    func addOfflineProfile(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OfflineProfile.isValid(clean),
              !offlineProfiles.contains(where: { $0.nickname.lowercased() == clean.lowercased() }) else {
            message = "Nick offline: 3–16 znaków (litery A–Z, cyfry i _), bez duplikatów."
            return
        }
        let profile = OfflineProfile(nickname: clean)
        offlineProfiles.append(profile)
        selectedOfflineID = profile.id
        message = "Wybrano profil offline: \(clean). Nie daje dostępu do serwerów premium."
    }

    func removeOfflineProfiles(at offsets: IndexSet) {
        offlineProfiles.remove(atOffsets: offsets)
        if activeOfflineProfile == nil { selectedOfflineID = nil }
    }

    func probeServer(_ address: String) async {
        serverProbeStatus = "Odczytywanie statusu Minecraft Java…"
        serverProbeStatus = await NovaMinecraftServerStatus.query(address: address)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            versions = try await installer.fetchVersions()
            installed = Set(versions.filter { installer.isInstalled($0.id) }.map(\.id))
            if !versions.contains(where: { $0.id == selectedVersion }) {
                select(versions.first(where: { $0.type == "release" })?.id ?? "")
            }
            message = "Lista wersji zaktualizowana"
        } catch {
            message = "Nie udało się pobrać manifestu: \(error.localizedDescription)"
        }
    }

    func select(_ id: String) {
        selectedVersion = id
        UserDefaults.standard.set(id, forKey: "version")
    }

    func installSelected() async {
        guard !busy, let version = versions.first(where: { $0.id == selectedVersion }) else { return }
        busy = true
        downloadProgress = 0
        message = "Pobieranie wersji \(version.id)…"
        defer { busy = false }
        do {
            try await installer.install(version: version) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            installed.insert(version.id)
            message = "Pobrano klienta, biblioteki Java i zasoby wersji \(version.id). Do uruchomienia gry nadal brakuje JVM i grafiki LWJGL na iOS."
        } catch { message = "Błąd instalacji: \(error.localizedDescription)" }
    }

    func removeSelected() {
        guard !busy, selectedInstalled else { return }
        do {
            try installer.remove(versionID: selectedVersion)
            installed.remove(selectedVersion)
            message = "Usunięto pobrane pliki wersji \(selectedVersion)"
        } catch {
            message = "Nie udało się usunąć plików: \(error.localizedDescription)"
        }
    }

    func signIn() async {
        do {
            account = try await authentication.signIn()
            message = "Zalogowano: \(account?.username ?? "")"
        } catch { message = "Logowanie nieudane: \(error.localizedDescription)" }
    }

    func testJVMStartup() async {
        message = "Uruchamianie testu JNI…"
        let result = await Task.detached(priority: .userInitiated) {
            NovaJNIStartupTest.run()
        }.value
        message = result
    }

    func inspectEngine() {
        do {
            let plan = try runtime.inspect(version: selectedVersion)
            message = "NovaEngine 0.1 — " + plan.summary
        } catch {
            message = "NovaEngine: " + error.localizedDescription
        }
    }

    func prepareOfflineLaunch() {
        guard let profile = activeOfflineProfile else {
            message = "Wybierz profil offline w zakładce Konto."
            return
        }
        do {
            let arguments = try runtime.prepareOfflineArguments(version: selectedVersion, nickname: profile.nickname)
            message = "NovaEngine 0.4 — " + arguments.safeSummary + ". Argumenty przygotowane; JVM i renderer nadal niedostępne."
        } catch {
            message = "Przygotowanie startu: " + error.localizedDescription
        }
    }

    func launch() async {
        do {
            try await runtime.launch(version: selectedVersion, account: account, offlineNickname: activeOfflineProfile?.nickname)
        } catch { message = error.localizedDescription }
    }

    @discardableResult
    func addServer(name: String, address: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty, cleanName.count <= 64,
              !cleanAddress.isEmpty, cleanAddress.count <= 253,
              !cleanAddress.contains(where: { $0.isWhitespace }),
              !cleanAddress.contains("/"),
              !servers.contains(where: { $0.address.lowercased() == cleanAddress }) else {
            message = "Sprawdź nazwę i adres serwera (lub usuń duplikat)."
            return false
        }
        servers.append(SavedServer(name: cleanName, address: cleanAddress))
        message = "Zapisano serwer \(cleanName)"
        return true
    }
}

struct SavedServer: Identifiable, Codable {
    var id = UUID()
    let name: String
    let address: String
}
