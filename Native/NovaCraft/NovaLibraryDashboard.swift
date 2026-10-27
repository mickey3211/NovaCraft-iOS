import SwiftUI
import UniformTypeIdentifiers
import Foundation

// Copyright (c) 2026 mickey3211. Original NovaCraft file management UI.
// The library manages files in this app's sandbox, never Amethyst's files.

struct NovaStorageCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let bytes: Int64
    let fileCount: Int
}

struct NovaStorageSnapshot {
    let categories: [NovaStorageCategory]
    let freeBytes: Int64?
    var totalBytes: Int64 { categories.reduce(0) { $0 + $1.bytes } }
    static let empty = NovaStorageSnapshot(categories: [], freeBytes: nil)
}

enum NovaLibraryError: LocalizedError {
    case invalidFile
    case tooLarge
    case emptyPack

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Wybierz prawidłowy plik .zip. Nie można importować plików wykonywalnych."
        case .tooLarge: return "Archiwum przekracza limit 256 MB."
        case .emptyPack: return "Archiwum jest puste lub uszkodzone."
        }
    }
}

enum NovaLibraryManager {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft", isDirectory: true)
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var packDirectory: URL {
        root.appendingPathComponent("game/resourcepacks", isDirectory: true)
    }

    static func logURLs() -> [URL] {
        let prefix = "NovaCraft-"
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return contents.filter {
            $0.lastPathComponent.hasPrefix(prefix) &&
            ($0.pathExtension.lowercased() == "log" ||
             $0.pathExtension.lowercased() == "txt")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Enumerates only inside NovaCraft's sandbox. Deliberately does not follow
    /// symlinks, read file contents, or delete world saves/mods.
    static func inspect() -> NovaStorageSnapshot {
        let fm = FileManager.default
        let locations: [(String, String, String, URL)] = [
            ("versions", "Wersje Minecraft", "square.stack.3d.up", root.appendingPathComponent("versions")),
            ("libraries", "Biblioteki Java", "shippingbox", root.appendingPathComponent("libraries")),
            ("assets", "Tekstury i dźwięki", "photo.stack", root.appendingPathComponent("assets")),
            ("worlds", "Światy i zapisy", "globe.europe.africa", root.appendingPathComponent("game/saves")),
            ("packs", "Paczki zasobów", "square.on.square", packDirectory),
            ("game", "Pozostałe pliki gry", "folder", root.appendingPathComponent("game")),
            ("logs", "Dzienniki diagnostyczne", "doc.text", documents)
        ]
        var categories: [NovaStorageCategory] = []
        for (id, title, icon, directory) in locations {
            // Other game files are counted separately to avoid double counting
            // worlds/resourcepacks in the total.
            let skipGameDirs = id == "game" ? Set(["saves", "resourcepacks"]) : Set<String>()
            let files = id == "logs" ? logURLs() : allFiles(at: directory, skipping: skipGameDirs)
            let bytes = files.reduce(Int64(0)) { sum, file in
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + Int64(size)
            }
            categories.append(NovaStorageCategory(id: id, title: title, icon: icon,
                                                  bytes: bytes, fileCount: files.count))
        }
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values?.volumeAvailableCapacityForImportantUsage
        return NovaStorageSnapshot(categories: categories, freeBytes: available)
    }

    static func importedPacks() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: packDirectory, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return entries.filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func importResourcePack(_ source: URL) throws -> String {
        guard source.pathExtension.lowercased() == "zip",
              !source.lastPathComponent.isEmpty else { throw NovaLibraryError.invalidFile }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let meta = try fm.attributesOfItem(atPath: source.path)
        let size = (meta[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw NovaLibraryError.emptyPack }
        guard size <= 256 * 1024 * 1024 else { throw NovaLibraryError.tooLarge }

        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        guard header.count == 4, header[0] == 0x50, header[1] == 0x4b,
              ((header[2] == 3 && header[3] == 4) ||
               (header[2] == 5 && header[3] == 6)) else {
            throw NovaLibraryError.invalidFile
        }

        try fm.createDirectory(at: packDirectory, withIntermediateDirectories: true)
        // The archive remains a data file. It is not extracted or executed,
        // and it is only copied into resourcepacks (never mods/natives).
        let safeName = source.deletingPathExtension().lastPathComponent
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) ||
                                     $0 == "_" || $0 == "-" || $0 == " " }
            .map(String.init).joined()
        let shortName = String(safeName.prefix(60))
        let name = shortName.isEmpty ? "Paczka" : shortName
        var destination = packDirectory.appendingPathComponent(name + ".zip")
        for index in 1...999 where fm.fileExists(atPath: destination.path) {
            destination = packDirectory.appendingPathComponent("\(name)-\(index).zip")
        }
        guard !fm.fileExists(atPath: destination.path) else { throw NovaLibraryError.invalidFile }
        try fm.copyItem(at: source, to: destination)
        return destination.lastPathComponent
    }

    static func removeResourcePack(_ url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL == packDirectory.standardizedFileURL,
              url.pathExtension.lowercased() == "zip" else { throw NovaLibraryError.invalidFile }
        try FileManager.default.removeItem(at: url)
    }

    static func removeDiagnosticLogs() throws {
        for file in logURLs() { try FileManager.default.removeItem(at: file) }
    }

    private static func allFiles(at root: URL, skipping directChildren: Set<String> = []) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: { _, _ in true }) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.deletingLastPathComponent() == root &&
                directChildren.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  attrs.isSymbolicLink != true, attrs.isRegularFile == true else { continue }
            files.append(url)
        }
        return files
    }
}

struct NovaLibraryDashboard: View {
    @State private var snapshot = NovaStorageSnapshot.empty
    @State private var packs: [URL] = []
    @State private var logs: [URL] = []
    @State private var loading = true
    @State private var importing = false
    @State private var alert: String?
    @State private var confirmClearLogs = false

    private func refresh() {
        loading = true
        Task {
            let latest = await Task.detached(priority: .utility) {
                NovaLibraryManager.inspect()
            }.value
            snapshot = latest
            packs = NovaLibraryManager.importedPacks()
            logs = NovaLibraryManager.logURLs()
            loading = false
        }
    }

    var body: some View {
        List {
            Section("Pamięć NovaCraft") {
                if loading { ProgressView("Skanowanie plików…") }
                HStack {
                    Label("Łącznie zajęte", systemImage: "internaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: snapshot.totalBytes, countStyle: .file))
                        .monospacedDigit()
                }
                if let free = snapshot.freeBytes {
                    LabeledContent("Wolne na iPhonie",
                        value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                }
                ForEach(snapshot.categories) { category in
                    HStack {
                        Label(category.title, systemImage: category.icon)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(ByteCountFormatter.string(fromByteCount: category.bytes, countStyle: .file))
                            Text("\(category.fileCount) plików")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Paczki zasobów Minecraft") {
                Button {
                    importing = true
                } label: {
                    Label("Importuj resource pack (.zip)", systemImage: "square.and.arrow.down")
                }
                ForEach(packs, id: \.path) { pack in
                    HStack {
                        Text(pack.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            do {
                                try NovaLibraryManager.removeResourcePack(pack)
                                refresh()
                            } catch { alert = error.localizedDescription }
                        } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                        .accessibilityLabel("Usuń \(pack.lastPathComponent)")
                    }
                }
                Text("Paczki trafiają do katalogu Minecraft/resourcepacks. Instalowanie modów i uruchamianie paczek nadal wymaga działającej gry.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Dzienniki JVM") {
                if logs.isEmpty {
                    Text("Brak zapisanych raportów.")
                        .foregroundStyle(.secondary)
                }
                ForEach(logs, id: \.path) { log in
                    ShareLink(item: log) {
                        Label("Udostępnij \(log.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                }
                if !logs.isEmpty {
                    Button("Usuń wyłącznie dzienniki", role: .destructive) {
                        confirmClearLogs = true
                    }
                }
                Text("Logi mogą zawierać nicki, ścieżki i adresy serwerów — przejrzyj je przed udostępnieniem.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Bezpieczeństwo") {
                Text("Ta sekcja nie usuwa światów ani plików Minecraft automatycznie. Import .zip nie uruchamia kodu i nie modyfikuje JVM.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Biblioteka i pliki")
        .toolbar {
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
        }
        .onAppear { refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let first = urls.first else { return }
                do {
                    let name = try NovaLibraryManager.importResourcePack(first)
                    refresh()
                    alert = "Zaimportowano \(name)"
                } catch { alert = error.localizedDescription }
            case .failure(let error):
                alert = error.localizedDescription
            }
        }
        .confirmationDialog("Usunąć zapisane raporty JVM?", isPresented: $confirmClearLogs) {
            Button("Usuń logi", role: .destructive) {
                do {
                    try NovaLibraryManager.removeDiagnosticLogs()
                    refresh()
                } catch { alert = error.localizedDescription }
            }
        } message: {
            Text("Usunie logi, ale nie zapisane światy ani pliki gry.")
        }
        .alert("NovaCraft", isPresented: Binding(
            get: { alert != nil },
            set: { if !$0 { alert = nil } })) {
                Button("OK") { alert = nil }
            } message: {
                Text(alert ?? "")
            }
    }
}
