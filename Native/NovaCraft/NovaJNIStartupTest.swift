import Foundation
import Darwin

// Minimal JNI Invocation API ABI, compatible with JNI_VERSION_1_8.
private struct NovaJNIInitArgs {
    var version: Int32
    var optionCount: Int32
    var options: UnsafeMutableRawPointer?
    var ignoreUnrecognized: UInt8
}

private typealias NovaJNICreate = @convention(c) (
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    UnsafeMutableRawPointer?
) -> Int32

/// Explicit smoke test; NEVER run automatically at app startup.
enum NovaJNIStartupTest {
    private static var didStart = false
    private static var retainedHandle: UnsafeMutableRawPointer?

    static func run() -> String {
        if didStart { return "JVM już uruchomiona w tym procesie." }
        guard let directory = Bundle.main.privateFrameworksURL else {
            return "Brak katalogu Frameworks."
        }
        let library = directory
            .appendingPathComponent("NovaJavaRuntime.framework", isDirectory: true)
            .appendingPathComponent("NovaJavaRuntime")
        guard FileManager.default.fileExists(atPath: library.path) else {
            return "Brak Java 21 dla iOS arm64 w aplikacji. Test JVM nie został uruchomiony."
        }
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            return "Nie można załadować frameworku JVM. Sprawdź podpis i zależności."
        }
        guard let symbol = dlsym(handle, "JNI_CreateJavaVM") else {
            dlclose(handle)
            return "Brak JNI_CreateJavaVM w dostarczonym frameworku."
        }
        let create = unsafeBitCast(symbol, to: NovaJNICreate.self)
        var vm: UnsafeMutableRawPointer?
        var env: UnsafeMutableRawPointer?
        var args = NovaJNIInitArgs(version: 0x00010008, optionCount: 0, options: nil, ignoreUnrecognized: 0)
        let code = withUnsafeMutablePointer(to: &args) { pointer in
            create(&vm, &env, UnsafeMutableRawPointer(pointer))
        }
        if code == 0, vm != nil, env != nil {
            didStart = true
            retainedHandle = handle
            return "JVM uruchomiona przez JNI_CreateJavaVM (JNI_OK). Uruchamianie Minecraft i grafika LWJGL nadal nie są gotowe."
        }
        dlclose(handle)
        return "JNI_CreateJavaVM zwróciło błąd: \(code)."
    }
}
