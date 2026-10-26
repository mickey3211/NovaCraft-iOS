import Foundation

/// Invokes Minecraft's Java entrypoint when real signed iOS JVM and LWJGL
/// libraries are embedded. No downloaded executable code is loaded on iOS.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        let classpath = iosLWJGLClasspath(fallback: args.classpath)
        // Resolve JVM properties against the classpath that actually includes
        // the iOS LWJGL jars, not the original desktop-only Minecraft manifest.
        var jvmOptions = normalizeJVMOptions(args.jvmArguments)
        if javaMajor == 21 {
            let home = library.deletingLastPathComponent().path
            jvmOptions.append("-Djava.home=\(home)")
        }
        // Keep JVM heap under iOS jetsam limits. The native JNI bridge
        // respects an explicit -Xmx option instead of adding a duplicate.
        let physicalGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let heapMB = physicalGB >= 6 ? 1536 : (physicalGB >= 4 ? 1024 : 768)
        // iOS code-signing often disallows JIT executable pages. During
        // bootstrap testing force HotSpot's interpreter and a modest heap.
        jvmOptions.removeAll { $0.hasPrefix("-Xmx") || $0 == "-Xint" }
        jvmOptions.append("-Xmx\(min(heapMB, 768))m")
        jvmOptions.append("-Xint")
        jvmOptions.append("-XX:+UseSerialGC")
        jvmOptions.append("-XX:-UsePerfData")
        // If HotSpot encounters a native fatal error, preserve hs_err_pid
        // in Documents so it can be exported after reopening NovaCraft.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            jvmOptions.append("-XX:ErrorFile=\(documents.appendingPathComponent("NovaCraft-hs_err_pid%p.log").path)")
        }

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
                                // OpenJDK Mobile iOS launchers use JLI_Launch instead of
                                // calling JNI_CreateJavaVM directly. Prefer that
                                // proven initialization route for our bundled Java 21.
                                if javaMajor == 21 {
                                    return nova_jli_launch_main(runtimePath, mainClass, classpath,
                                                                nativeDir, vmBuffer.baseAddress,
                                                                Int32(vmStrings.count),
                                                                gameBuffer.baseAddress,
                                                                Int32(gameStrings.count))
                                }
                                return nova_jni_invoke_main(runtimePath, mainClass, classpath,
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
            return filename != "lwjgl.jar" && !filename.hasPrefix("lwjgl-")
                && !filename.hasPrefix("lwjgl3-") && !filename.hasPrefix("lwjglx-")
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
