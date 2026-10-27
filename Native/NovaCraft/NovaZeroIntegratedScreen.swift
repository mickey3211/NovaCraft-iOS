import SwiftUI
import Foundation

// Original NovaCraft diagnostics screen. This is an on-device check that
// the static OpenJDK Mobile Zero can be called from the real SwiftUI launcher.
struct NovaZeroIntegratedScreen: View {
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
        let thread = Thread {
            let status = nova_zero_run_smoke_test()
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
                Text("Ten eksperymentalny build łączy istniejący interfejs SwiftUI z oficjalnym OpenJDK Mobile Zero. Testuje jedną klasę skompilowaną w formacie Java 21. Nie uruchamia Minecrafta.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(action: runTest) {
                    Label("Uruchom Zero w NovaCraft", systemImage: "play.circle.fill")
                }
                .disabled(running || tested)
                if running { ProgressView("Inicjalizacja Zero JVM…") }
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
                Text("Dopiero po potwierdzeniu NOVA_ZERO_INTEGRATED_OK będzie można podłączać zgodny runtime Minecraft Java 21, bibliotekę LWJGL i obsługę OpenGL. Ten wariant Zero używa nowszego JDK niż Java 21; jego powodzenie nie potwierdza działania Minecrafta.")
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
