import SwiftUI
import Foundation

/// One read-only report surface. Diagnostics run from Play, not from Settings.
struct NovaZeroIntegratedScreen: View {
    @State private var report = "Brak raportu. Pobierz wybraną wersję Minecraft i naciśnij Graj na ekranie Start."
    @State private var hasReport = false
    private var logURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft-launch-report.txt")
    }

    var body: some View {
        Form {
            Section("Ostatnia próba uruchomienia") {
                Text("Dziennik ostatniego uruchomienia gry. Przed udostępnieniem sprawdź, czy nie zawiera danych prywatnych.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if hasReport {
                Section {
                    ShareLink(item: logURL) {
                        Label("Udostępnij raport", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Raport diagnostyczny")
        .onAppear {
            let documents = logURL.deletingLastPathComponent()
            let gameLog = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NovaCraft/game/logs/latest.log")
            let sources = [NovaZeroLaunchDiagnostics.logURL,
                           documents.appendingPathComponent("NovaCraft-java-output.log"), gameLog]
            var sections: [String] = []
            for source in sources {
                guard let file = try? FileHandle(forReadingFrom: source) else { continue }
                defer { try? file.close() }
                do {
                    let size = try file.seekToEnd()
                    let start = size > 1_048_576 ? size - 1_048_576 : 0
                    try file.seek(toOffset: start)
                    let bytes = try file.readToEnd() ?? Data()
                    guard !bytes.isEmpty else { continue }
                    let truncation = start > 0 ? "(ostatni 1 MiB)\n" : ""
                    sections.append("--- \(source.lastPathComponent) ---\n" + truncation + String(decoding: bytes, as: UTF8.self))
                } catch { continue }
            }
            guard !sections.isEmpty else { return }
            report = sections.joined(separator: "\n\n")
            do {
                try report.write(to: logURL, atomically: true, encoding: .utf8)
                hasReport = true
            } catch { hasReport = false }
        }
    }
}

/// A single process-wide attempt: reopening a view must never create another VM.
@MainActor
enum NovaZeroLaunchDiagnostics {
    struct Result {
        let version: String
        let status: Int32
    }
    static let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NovaCraft-integrated-zero.log")
    private static var attempt: Task<Result, Never>?

    static func run(version: String) async -> Result {
        if let attempt { return await attempt.value }
        let task = Task<Result, Never> {
            let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                let thread = Thread {
                    let status = version.withCString { nova_zero_run_smoke_test($0) }
                    continuation.resume(returning: status)
                }
                thread.name = "NovaCraft-Zero-Launch"
                thread.stackSize = 16 * 1024 * 1024
                thread.qualityOfService = .userInitiated
                thread.start()
            }
            return Result(version: version, status: status)
        }
        attempt = task
        return await task.value
    }
}
