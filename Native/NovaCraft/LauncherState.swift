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
    @Published var lastCrashStage: String?
    @Published var lastHotSpotReport: String?
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
        if UserDefaults.standard.bool(forKey: "novacraft-jvm-launch-in-progress") {
            let log = Self.lastJVMCheckpoint()
            lastCrashStage = log
            lastHotSpotReport = Self.lastHotSpotCrashReport()
            message = "Poprzednie uruchomienie zakończyło się nieoczekiwanie. Etap: \(log ?? "nieznany")."
        }
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
            if lastCrashStage == nil { message = "Lista wersji zaktualizowana" }
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
                Task { @MainActor in
                    guard let self else { return }
                    // Avoid redrawing the entire launcher for every asset byte.
                    if progress >= 1 || progress - self.downloadProgress >= 0.01 {
                        self.downloadProgress = progress
                    }
                }
            }
            installed.insert(version.id)
            message = "Pobrano i zweryfikowano pliki Minecraft \(version.id). Możesz nacisnąć Graj."
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
        message = "Sprawdzanie bibliotek Java 21 i ich podpisów…"
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

    private static func lastJVMCheckpoint() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("NovaCraft-jvm-last-stage.txt")
        return try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lastHotSpotCrashReport() -> String? {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              let recent = urls.filter({
                  $0.lastPathComponent.hasPrefix("NovaCraft-hs_err_pid") &&
                  $0.pathExtension == "log"
              }).max(by: {
                  let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  return first < second
              }),
              let handle = try? FileHandle(forReadingFrom: recent) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 16 * 1024), !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    func launch() async {
        guard !busy, selectedInstalled else {
            if !selectedInstalled { message = "Najpierw pobierz pliki wybranej wersji Minecraft." }
            return
        }
        busy = true
        lastCrashStage = nil
        lastHotSpotReport = nil
        // Eliminate stale crash markers before each attempted launch.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("NovaCraft-jvm-last-stage.txt"))
        message = "Uruchamianie Minecraft \(selectedVersion)…"
        UserDefaults.standard.set(true, forKey: "novacraft-jvm-launch-in-progress")
        UserDefaults.standard.synchronize()
        defer {
            UserDefaults.standard.set(false, forKey: "novacraft-jvm-launch-in-progress")
            busy = false
        }
        do {
            try await runtime.launch(version: selectedVersion, account: account, offlineNickname: activeOfflineProfile?.nickname)
            message = "Proces Minecraft zakończył działanie."
        } catch {
            message = error.localizedDescription
            if let checkpoint = Self.lastJVMCheckpoint() {
                lastCrashStage = checkpoint
                message += " Etap JVM: \(checkpoint)."
            }
            lastHotSpotReport = Self.lastHotSpotCrashReport()
        }
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
