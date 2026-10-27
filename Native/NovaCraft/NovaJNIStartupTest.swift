import Foundation
import Darwin

/// Non-destructive preflight for the bundled, signed Java 21 runtime.
///
/// Never call JNI_CreateJavaVM from a diagnostic button: a VM created this way
/// cannot be restarted in-process and may terminate NovaCraft before the
/// actual Minecraft launcher is allowed to run.
enum NovaJNIStartupTest {
    static func run() -> String {
        guard let framework = NovaJavaRuntimeRegistry.frameworkURL(major: 21) else {
            return "Brak katalogu Frameworks w aplikacji."
        }
        let javaHome = framework.deletingLastPathComponent()
        let fm = FileManager.default
        // The Java CLI executable is optional for the embedded iOS JLI path.
        let jli = javaHome.appendingPathComponent("lib/libjli.dylib")
        let vm = javaHome.appendingPathComponent("lib/server/libjvm.dylib")
        let release = javaHome.appendingPathComponent("release")

        for (label, path) in [("lib/libjli.dylib", jli),
                              ("lib/server/libjvm.dylib", vm),
                              ("release", release)] {
            guard fm.fileExists(atPath: path.path) else {
                return "Java 21: brak pliku \(label) w pakiecie IPA."
            }
        }

        guard let jliHandle = dlopen(jli.path, RTLD_NOW | RTLD_GLOBAL) else {
            let why = dlerror().map { String(cString: $0) } ?? "nieznany błąd"
            return "Java 21: nie można załadować libjli.dylib. \(why)"
        }
        defer { dlclose(jliHandle) }
        guard dlsym(jliHandle, "JLI_Launch") != nil else {
            return "Java 21: libjli.dylib nie udostępnia JLI_Launch."
        }

        guard let vmHandle = dlopen(vm.path, RTLD_NOW | RTLD_GLOBAL) else {
            let why = dlerror().map { String(cString: $0) } ?? "nieznany błąd"
            return "Java 21: nie można załadować libjvm.dylib. \(why)"
        }
        defer { dlclose(vmHandle) }
        guard dlsym(vmHandle, "JNI_CreateJavaVM") != nil else {
            return "Java 21: libjvm.dylib nie udostępnia JNI_CreateJavaVM."
        }

        return "Java 21: obie biblioteki i symbole JVM są dostępne. " +
            "Nie oznacza to jeszcze, że Minecraft i renderowanie OpenGL uruchomią się na iPhonie."
    }
}
