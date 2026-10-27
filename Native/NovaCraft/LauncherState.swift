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
    @Published var lastJavaOutput: String?
    @Published var lastHotspotBootLog: String?
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
            lastJavaOutput = Self.lastJavaOutputLog()
            lastHotspotBootLog = Self.lastHotspotBootLog()
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
        message = "Przygotowywanie pobierania w tle dla Minecraft \(version.id)… Pozostaw aplikację otwartą do rozpoczęcia transferów."
        defer { busy = false }
        do {
            // Mojang's small metadata and asset index are fetched first. Every
            // large client/library/asset download is then handled by Apple's
            // persistent background URLSession and its saved on-disk plan.
            let plan = try await installer.prepareBackgroundInstall(version: version)
            installed.remove(version.id)
            try await NovaBackgroundDownloads.shared.begin(plan)
            message = "Minecraft \(version.id): transfery działają w tle. Możesz przełączyć się do innej aplikacji."
        } catch {
            message = "Błąd przygotowania pobierania w tle: \(error.localizedDescription)"
        }
    }

    func reflectBackgroundInstall(_ id: String) {
        installed = Set(versions.filter { installer.isInstalled($0.id) }.map(\.id))
        if installed.contains(id) {
            message = "Minecraft \(id): pliki pobrane i zweryfikowane. Możesz nacisnąć Graj."
        }
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

    private static func lastJavaOutputLog() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("NovaCraft-java-output.log")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 24 * 1024
        try? handle.seek(toOffset: length > maxBytes ? length - maxBytes : 0)
        guard let data = try? handle.read(upToCount: Int(maxBytes)), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Java 21 HotSpot writes this log separately from stdout/stderr.
    // Read the last 24 KiB only to avoid keeping large JVM logs in memory.
    private static func lastHotspotBootLog() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("NovaCraft-hotspot-boot.log")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 24 * 1024
        try? handle.seek(toOffset: length > maxBytes ? length - maxBytes : 0)
        guard let data = try? handle.read(upToCount: Int(maxBytes)), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func launch() async {
        guard !busy, selectedInstalled else {
            if !selectedInstalled { message = "Najpierw pobierz pliki wybranej wersji Minecraft." }
            return
        }
        busy = true
        lastCrashStage = nil
        lastHotSpotReport = nil
        lastJavaOutput = nil
        lastHotspotBootLog = nil
        // Eliminate stale crash markers before each attempted launch.
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("NovaCraft-jvm-last-stage.txt"))
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("NovaCraft-java-output.log"))
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("NovaCraft-hotspot-boot.log"))
        message = "Uruchamianie Minecraft \(selectedVersion)…"
        UserDefaults.standard.set(true, forKey: "novacraft-jvm-launch-in-progress")
        UserDefaults.standard.synchronize()
        defer {
            UserDefaults.standard.set(false, forKey: "novacraft-jvm-launch-in-progress")
            busy = false
        }
        do {
            try await runtime.launch(version: selectedVersion, account: account, offlineNickname: activeOfflineProfile?.nickname)
            if UserDefaults.standard.bool(forKey: "novacraft-jvm-probe-only") {
                message = "Test JVM zakończony. Sprawdź w dzienniku Java wpis JVM_PROBE_OK. Wyłącz tryb testowy i uruchom NovaCraft ponownie przed kolejnym startem gry."
            } else {
                message = "Java zakończyła działanie; sprawdź dziennik Java i etap uruchomienia gry."
            }
            lastCrashStage = Self.lastJVMCheckpoint()
            lastJavaOutput = Self.lastJavaOutputLog()
            lastHotspotBootLog = Self.lastHotspotBootLog()
        } catch {
            message = error.localizedDescription
            if let checkpoint = Self.lastJVMCheckpoint() {
                lastCrashStage = checkpoint
                message += " Etap JVM: \(checkpoint)."
            }
            lastHotSpotReport = Self.lastHotSpotCrashReport()
            lastJavaOutput = Self.lastJavaOutputLog()
            lastHotspotBootLog = Self.lastHotspotBootLog()
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
