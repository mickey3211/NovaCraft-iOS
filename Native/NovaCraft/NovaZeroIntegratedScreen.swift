import SwiftUI
import Foundation

// Original NovaCraft diagnostics screen. This is an on-device check that
// the static OpenJDK Mobile Zero can be called from the real SwiftUI launcher.
struct NovaZeroIntegratedScreen: View {
    @EnvironmentObject private var launcher: LauncherState
    @State private var result = "Naciśnij test, aby uruchomić Javę Zero wewnątrz NovaCraft."
    @State private var running = false
    @State private var tested = false

    private var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft-integrated-zero.log")
    }

    private func runTest() {
        guard !running && !tested else { return }
        running = true
        result = "Tworzenie JVM Zero. Jeżeli aplikacja się wyłączy, raport znajdziesz w Plikach lub analizach iOS."
        let url = logURL
        let selected = launcher.selectedVersion
        let thread = Thread {
            let status = selected.withCString { version in
                nova_zero_run_smoke_test(version)
            }
            let output = (try? String(contentsOf: url, encoding: .utf8))
                ?? "Nie udało się odczytać dziennika Java."
            DispatchQueue.main.async {
                result = output + "\nKod zwrotny: \(status)"
                running = false
                tested = true
            }
        }
        thread.name = "NovaCraft-Zero-Integrated"
        thread.stackSize = 16 * 1024 * 1024
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    var body: some View {
        Form {
            Section("Własny launcher + OpenJDK Zero") {
                Label("Test wewnątrz oryginalnego NovaCraft", systemImage: "cpu")
                    .font(.headline)
                Text("Test sprawdza działający OpenJDK Mobile Zero, moduły Java, ZIP, wątki i (jeśli w tej aplikacji pobrano grę) archiwum client.jar. Nie wykonuje kodu Minecrafta ani LWJGL.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(action: runTest) {
                    Label("Uruchom Zero w NovaCraft", systemImage: "play.circle.fill")
                }
                .disabled(running || tested)
                if running { ProgressView("Sprawdzanie Java Zero i bibliotek…") }
                Text("Wersja Minecraft do sprawdzenia: \(launcher.selectedVersion.isEmpty ? "brak" : launcher.selectedVersion)")
                    .font(.caption).foregroundStyle(.secondary)
                if tested {
                    Text("Drugi start JVM wymaga ponownego otwarcia aplikacji.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Wynik testu") {
                Text(result)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if FileManager.default.fileExists(atPath: logURL.path) {
                    ShareLink(item: logURL) {
                        Label("Wyślij raport Zero", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Dalszy rozwój") {
                Text("Wyniki ZERO_MODULE_*, ZERO_ZIP_API_OK i MINECRAFT_CLIENT_JAR pomogą ustalić, czy brakuje bibliotek Java lub plików gry. Komunikat NOT_DOWNLOADED_IN_THIS_APP oznacza, że klient nie jest pobrany w NovaCraft Z-Dev. Nie jest to dowód uruchomienia Minecrafta ani zgodności OpenGL.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("NovaCraft Zero")
        .onAppear {
            if let previous = try? String(contentsOf: logURL, encoding: .utf8) {
                result = previous
                tested = previous.contains("NOVA_ZERO_INTEGRATED_OK")
            }
        }
    }
}
