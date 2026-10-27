import Foundation
import SwiftUI
import UIKit

// Copyright (c) 2026 mickey3211. Original NovaCraft crash report exporter.
// Never uploads data automatically; the user must inspect and share manually.
enum NovaJVMDiagnostics {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func reportInputPaths() -> [URL] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let prefixes = ["NovaCraft-java-output.log",
                        "NovaCraft-hotspot-boot.log",
                        "NovaCraft-jvm-last-stage.txt"]
        let selected = files.filter {
            prefixes.contains($0.lastPathComponent) ||
                ($0.lastPathComponent.hasPrefix("NovaCraft-hs_err_pid") &&
                 $0.pathExtension.lowercased() == "log")
        }
        return selected.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func summary() -> String {
        let files = reportInputPaths()
        let hsError = files.filter { $0.lastPathComponent.hasPrefix("NovaCraft-hs_err_pid") }
        return "Raportów HotSpot: \(hsError.count), plików diagnostycznych: \(files.count)."
    }

    // Bound each read to at most 2 MiB; never append giant core dumps or raw
    // app data. This includes complete hs_err reports unless >2 MiB.
    static func createForSharing() throws -> URL {
        var contents = """
        NOVACRAFT — RAPORT STARTU JVM
        Uwaga: to NIE jest dowód uruchomienia Minecrafta.
        Raport utworzony: \(Date())
        iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Urządzenie: \(UIDevice.current.model)
        Pamięć fizyczna: \(ProcessInfo.processInfo.physicalMemory / 1048576) MiB
        Tryb testu JVM: \(UserDefaults.standard.bool(forKey: "novacraft-jvm-probe-only") ? "tak" : "nie")
        JVM: dołączone OpenJDK 21.0.8 iOS ARM64 (sprawdź metadane IPA)

        WAŻNE: raport może zawierać nazwę konta, ścieżki i adresy serwerów.
        Przejrzyj i usuń dane prywatne przed wysłaniem komukolwiek.

        """
        let input = reportInputPaths()
        if input.isEmpty {
            contents += "\nBrak zapisanych logów. Uruchom Test JVM i ponownie otwórz NovaCraft.\n"
        }
        for file in input {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 2 * 1024 * 1024) ?? Data()
            contents += "\n========== \(file.lastPathComponent) ==========\n"
            contents += String(decoding: data, as: UTF8.self)
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > data.count {
                contents += "\n[PRZYCIĘTO: pełny plik dostępny w Dokumentach aplikacji.]\n"
            }
            contents += "\n"
        }
        let output = directory.appendingPathComponent("NovaCraft-JVM-diagnostics.txt")
        try contents.write(to: output, atomically: true, encoding: .utf8)
        return output
    }
}

struct NovaJVMDiagnosticsScreen: View {
    @State private var report: URL?
    @State private var error: String?
    @State private var summary = "Sprawdzanie raportów…"

    private func collect() {
        do {
            report = try NovaJVMDiagnostics.createForSharing()
            summary = NovaJVMDiagnostics.summary()
            error = nil
        } catch {
            report = nil
            self.error = error.localizedDescription
        }
    }

    var body: some View {
        Form {
            Section("Ostatnia awaria Java 21") {
                Label("JVM zatrzymuje się podczas JNI_CreateJavaVM", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Najnowszy zrzut pokazał załadowaną bibliotekę libjava.dylib, ale bez potwierdzenia uruchomienia klasy Java. To może być problem kodu JVM, podpisu bibliotek lub ograniczeń systemu iOS.")
                    .font(.footnote)
                Text(summary)
                    .font(.caption)
            }
            Section("Pełny raport") {
                Button {
                    collect()
                } label: {
                    Label("Zbierz najnowsze logi", systemImage: "arrow.clockwise")
                }
                if let report {
                    ShareLink(item: report) {
                        Label("Udostępnij pełny raport JVM", systemImage: "square.and.arrow.up")
                    }
                    Text(report.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("Ważne przed udostępnieniem") {
                Text("Usuń z raportu nicki, identyfikatory konta, adresy serwerów, tokeny i prywatne ścieżki. NovaCraft nie wysyła raportów automatycznie.")
                    .font(.footnote)
                Text("Jeśli JVM zamyka aplikację bez pliku hs_err, spróbuj znaleźć raport NovaCraft w iOS: Ustawienia → Prywatność i ochrona → Analizy i ulepszenia → Dane analiz.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Diagnostyka JVM")
        .onAppear { collect() }
    }
}
