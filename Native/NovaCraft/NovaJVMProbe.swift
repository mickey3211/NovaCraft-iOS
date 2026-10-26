import Foundation
import Darwin

/// Validates a *bundled and code-signed* iOS JVM. No Java runtime is downloaded
/// or executable code loaded from the Documents/Application Support directory.
enum NovaJVMProbe {
    static func report() -> String {
        guard let framework = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("NovaJavaRuntime.framework", isDirectory: true) else {
            return "JVM: nie można znaleźć katalogu Frameworks."
        }
        let library = framework.appendingPathComponent("NovaJavaRuntime")
        guard FileManager.default.fileExists(atPath: library.path) else {
            return "Java 21: brak podpisanego NovaJavaRuntime.framework w aplikacji."
        }
        // iOS requires executable code to be signed as part of the app bundle.
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            return "JVM: biblioteka istnieje, ale iOS nie pozwolił jej załadować (podpis, architektura lub zależności)."
        }
        defer { dlclose(handle) }
        guard dlsym(handle, "JNI_CreateJavaVM") != nil else {
            return "JVM: framework nie udostępnia JNI_CreateJavaVM."
        }
        guard dlsym(handle, "JNI_GetCreatedJavaVMs") != nil else {
            return "JVM: framework nie udostępnia JNI_GetCreatedJavaVMs."
        }
        return "JVM: znaleziono symbole JNI w podpisanym frameworku. Uruchomienie Java 21 i Minecraft nie zostało jeszcze zweryfikowane."
    }
}
