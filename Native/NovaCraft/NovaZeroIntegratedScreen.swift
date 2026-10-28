import SwiftUI
import Foundation

/// One read-only report surface. Diagnostics run from Play, not from Settings.
struct NovaZeroIntegratedScreen: View {
    @State private var report = "Brak raportu. Pobierz wybraną wersję Minecraft i naciśnij Graj na ekranie Start."
    @State private var hasReport = false
    private var logURL: URL { NovaZeroLaunchDiagnostics.logURL }

    var body: some View {
        Form {
            Section("Ostatnia próba uruchomienia") {
                Text("Sprawdzenia wykonują się automatycznie po naciśnięciu Graj. Ten ekran nie uruchamia dodatkowych testów.")
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
            if let saved = try? String(contentsOf: logURL, encoding: .utf8) {
                report = saved
                hasReport = true
            }
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
