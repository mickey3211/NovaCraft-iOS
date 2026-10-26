import Foundation
import Darwin

/// Runtime registry for official Minecraft releases and snapshots.
/// Frameworks must be built for iOS arm64 and signed inside the application.
enum NovaJavaRuntimeRegistry {
    static let supportedMajors = [8, 16, 17, 21, 25]

    static func inferredMajor(for version: String) -> Int? {
        // Old manifests often omit javaVersion. This is a fallback only.
        let parts = version.split(separator: ".")
        guard parts.count >= 2, parts[0] == "1",
              let minor = Int(parts[1]) else { return nil }
        if minor <= 16 { return 8 }
        if minor == 17 { return 16 }
        if minor <= 20 { return 17 }
        return 21
    }

    static func requiredMajor(for plan: NovaEngineLaunchPlan) -> Int? {
        plan.requiredJavaMajor ?? inferredMajor(for: plan.versionID)
    }

    static func frameworkURL(major: Int) -> URL? {
        Bundle.main.privateFrameworksURL?
            .appendingPathComponent("NovaJava\(major).framework", isDirectory: true)
            .appendingPathComponent("NovaJava\(major)")
    }

    static func availability(for plan: NovaEngineLaunchPlan) -> String {
        guard let major = requiredMajor(for: plan) else {
            return "Nie można ustalić wymaganej wersji Java dla \(plan.versionID)."
        }
        guard supportedMajors.contains(major) else {
            return "Minecraft \(plan.versionID) wymaga Java \(major); NovaCraft nie ma jeszcze obsługi tego środowiska."
        }
        guard let library = frameworkURL(major: major),
              FileManager.default.fileExists(atPath: library.path) else {
            return "Minecraft \(plan.versionID) wymaga Java \(major). Brak podpisanego środowiska NovaJava\(major).framework w IPA."
        }
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            return "Java \(major) jest dołączona, ale iOS nie może załadować biblioteki lub jej zależności."
        }
        defer { dlclose(handle) }
        guard dlsym(handle, "JNI_CreateJavaVM") != nil else {
            return "Java \(major) nie udostępnia JNI_CreateJavaVM."
        }
        return "Java \(major): biblioteka JNI dostępna. Uruchomienie gry wymaga jeszcze integracji JVM, bibliotek natywnych i renderowania LWJGL."
    }
}
