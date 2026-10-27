import SwiftUI
import Foundation

// NovaCraft / NovaEngine preferences. These options affect only supported
// subsystems and deliberately do not claim to enable JIT or render Minecraft.

enum NovaPerformance {
    static let heapKey = "nova-heap-megabytes"
    static let fpsKey = "nova-metal-fps"
    static let worldSideKey = "nova-world-side"
    static let worldSeedKey = "nova-world-seed"
    static let paletteKey = "nova-world-palette"

    static func availableHeapMB() -> Int {
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return memoryGB >= 6 ? 1536 : 1024
    }

    static var heapMB: Int {
        let stored = UserDefaults.standard.integer(forKey: heapKey)
        let requested = stored > 0 ? stored : 768
        return max(384, min(availableHeapMB(), requested))
    }

    static var fps: Int {
        let saved = UserDefaults.standard.integer(forKey: fpsKey)
        return max(20, min(60, saved == 0 ? 60 : saved))
    }

    static var side: Int {
        let saved = UserDefaults.standard.integer(forKey: worldSideKey)
        return [24, 32, 40, 48].contains(saved) ? saved : 24
    }

    static var seed: Int {
        UserDefaults.standard.object(forKey: worldSeedKey) == nil
            ? 2026 : UserDefaults.standard.integer(forKey: worldSeedKey)
    }

    static var palette: String {
        let saved = UserDefaults.standard.string(forKey: paletteKey) ?? "aurora"
        return ["aurora", "forest", "lava"].contains(saved) ? saved : "aurora"
    }
}

struct NovaPerformanceSettingsView: View {
    @AppStorage("nova-heap-megabytes") private var heapMB = 768
    @AppStorage("nova-metal-fps") private var fps = 60
    @AppStorage("nova-world-side") private var worldSide = 24
    @AppStorage("nova-world-palette") private var palette = "aurora"

    var body: some View {
        Form {
            Section("Pamięć Java — Minecraft") {
                LabeledContent("Maksymalny heap JVM", value: "\(heapMB) MB")
                Slider(
                    value: Binding(
                        get: { Double(heapMB) },
                        set: { heapMB = Int(($0 / 128).rounded()) * 128 }
                    ),
                    in: 384...Double(NovaPerformance.availableHeapMB()), step: 128
                )
                Text("Domyślnie 768 MB. Większe wartości mogą przyspieszyć grę, ale również spowodować zamknięcie aplikacji przez iOS przy braku RAM. Ustawienie jest przekazywane do JVM jako -Xmx. Nie usuwa ograniczeń JIT.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Przywróć bezpieczne 768 MB") { heapMB = 768 }
            }
            Section("Grafika własnego NovaEngine Metal") {
                Picker("Limit FPS", selection: $fps) {
                    Text("20 FPS").tag(20)
                    Text("30 FPS").tag(30)
                    Text("45 FPS").tag(45)
                    Text("60 FPS").tag(60)
                }
                Picker("Wielkość świata", selection: $worldSide) {
                    Text("24 × 24 (lekka)").tag(24)
                    Text("32 × 32").tag(32)
                    Text("40 × 40").tag(40)
                    Text("48 × 48 (więcej detali)").tag(48)
                }
                Picker("Wygląd terenu", selection: $palette) {
                    Text("Neonowa zorza").tag("aurora")
                    Text("Zielone wzgórza").tag("forest")
                    Text("Wulkaniczny").tag("lava")
                }
                Text("FPS i jakość dotyczą własnego świata NovaEngine, nie Minecraft Java. Zmiany zastosują się po ponownym otwarciu podglądu świata.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink {
                    NovaVoxelEngineScreen()
                } label: {
                    Label("Otwórz świat NovaEngine", systemImage: "cube.fill")
                }
            }
            Section("Informacje o silniku") {
                LabeledContent("Projekt", value: "NovaCraft / mickey3211")
                LabeledContent("Grafika", value: "Metal — kod NovaEngine")
                LabeledContent("Java", value: "OpenJDK 21 (zewnętrzny)")
                LabeledContent("LWJGL", value: "Biblioteki zewnętrzne")
                Text("Ustawienia nie dodają implementacji GLFW/OpenGL. Minecraft Java wymaga odrębnej integracji renderera oraz zgodności JVM z iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Wydajność")
    }
}
