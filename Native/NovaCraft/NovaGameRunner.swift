import Foundation

/// Invokes Minecraft's Java entrypoint when real signed iOS JVM and LWJGL
/// libraries are embedded. No downloaded executable code is loaded on iOS.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        let jvmOptions = normalizeJVMOptions(args.jvmArguments)
        let classpath = iosLWJGLClasspath(fallback: args.classpath)

        let gamePointers = args.gameArguments.map { strdup($0) }
        let jvmPointers = jvmOptions.map { strdup($0) }
        defer {
            gamePointers.forEach { free($0) }
            jvmPointers.forEach { free($0) }
        }
        let gameStrings: [UnsafePointer<CChar>?] = gamePointers.map { $0.map { UnsafePointer($0) } }
        let vmStrings: [UnsafePointer<CChar>?] = jvmPointers.map { $0.map { UnsafePointer($0) } }
        return gameStrings.withUnsafeBufferPointer { gameBuffer in
            vmStrings.withUnsafeBufferPointer { vmBuffer in
                library.path.withCString { runtimePath in
                    args.mainClass.withCString { mainClass in
                        classpath.withCString { classpath in
                            nativePath.withCString { nativeDir in
                                nova_jni_invoke_main(runtimePath, mainClass, classpath,
                                                     nativeDir, vmBuffer.baseAddress,
                                                     Int32(vmStrings.count),
                                                     gameBuffer.baseAddress,
                                                     Int32(gameStrings.count))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Prefer upstream iOS LWJGL jars to Mojang's desktop variants, but preserve
    /// the rest of the Minecraft classpath. Jars are code data, not executable iOS binaries.
    private static func iosLWJGLClasspath(fallback: String) -> String {
        let dir = Bundle.main.bundleURL.appendingPathComponent("LWJGL-iOS", isDirectory: true)
        guard let jars = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              !jars.isEmpty else { return fallback }
        let libraryJars = jars.filter { $0.pathExtension.lowercased() == "jar" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if libraryJars.isEmpty { return fallback }
        let original = fallback.split(separator: ":").map(String.init).filter { entry in
            let filename = URL(fileURLWithPath: entry).lastPathComponent
            return !filename.hasPrefix("lwjgl-") && !filename.hasPrefix("lwjgl3-")
                && !filename.hasPrefix("lwjglx-")
        }
        return (libraryJars.map(\.path) + original).joined(separator: ":")
    }

    /// The Java launcher accepts argument pairs like "--add-opens", "module/pkg=..."
    /// but JNI_CreateJavaVM expects each VM option as one string.
    /// Keep launch-only options out of the Invocation API.
    static func normalizeJVMOptions(_ input: [String]) -> [String] {
        var output: [String] = []
        let equalsOptions: Set<String> = [
            "--add-opens", "--add-exports", "--add-modules",
            "--enable-native-access", "--add-reads", "--patch-module",
            "--limit-modules"
        ]
        var index = 0
        while index < input.count {
            let value = input[index]
            if value == "-cp" || value == "-classpath" || value == "--class-path" ||
                value == "-p" || value == "--module-path" {
                index += min(2, input.count - index)
                continue
            }
            if equalsOptions.contains(value) {
                guard index + 1 < input.count else { break }
                output.append(value + "=" + input[index + 1])
                index += 2
                continue
            }
            if value == "-XstartOnFirstThread" ||
                value.hasPrefix("-Djava.library.path=") ||
                value.hasPrefix("-Djava.class.path=") {
                index += 1
                continue
            }
            if value.hasPrefix("-D") || value.hasPrefix("-X") ||
                value.hasPrefix("-XX:") || value.hasPrefix("--add-opens=") ||
                value.hasPrefix("--add-exports=") || value.hasPrefix("--add-modules=") ||
                value.hasPrefix("--enable-native-access=") ||
                value.hasPrefix("--add-reads=") ||
                value.hasPrefix("--patch-module=") ||
                value.hasPrefix("--limit-modules=") {
                output.append(value)
            }
            index += 1
        }
        return output
    }
}
