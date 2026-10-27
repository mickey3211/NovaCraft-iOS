import Foundation

/// Invokes Minecraft's Java entrypoint when real signed iOS JVM and LWJGL
/// libraries are embedded. No downloaded executable code is loaded on iOS.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int, experimentalDirectJNI: Bool = false) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        let classpath = iosLWJGLClasspath(fallback: args.classpath)
        // Resolve JVM properties against the classpath that actually includes
        // the iOS LWJGL jars, not the original desktop-only Minecraft manifest.
        var jvmOptions = normalizeJVMOptions(args.jvmArguments)
        // JLI derives java.home from the bundled executable path and JAVA_HOME.
        // Explicit -Djava.home can interfere with locating OpenJDK runtime modules.
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
        // iOS sideload builds commonly lack extended-virtual-addressing rights.
        // Avoid HotSpot reserving a large compressed-class-pointer address range.
        jvmOptions.append("-XX:-UseCompressedClassPointers")
        // The game runs on a dedicated Java thread rather than the UIKit main thread.
        // This does not provide a renderer; it only configures LWJGL's thread checks.
        jvmOptions.append("-Dorg.lwjgl.glfw.checkThread0=false")
        jvmOptions.append("-Dorg.lwjgl.system.allocator=system")
        if experimentalDirectJNI {
            // The direct Invocation API needs these iOS VM flags too; the
            // JLI adapter normally adds them before calling JLI_Launch.
            jvmOptions.append("-XX:+UnlockExperimentalVMOptions")
            jvmOptions.append("-XX:+DisablePrimordialThreadGuardPages")
        }
        // Minecraft must write settings, logs and world saves outside the
        // read-only application bundle. Match the game directory used by
        // official --gameDir arguments in NovaLaunchArgumentBuilder.
        let gameRoot = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
            .appendingPathComponent("NovaCraft", isDirectory: true)
        let gameDirectory = gameRoot.appendingPathComponent("game", isDirectory: true)
        jvmOptions.removeAll { $0.hasPrefix("-Duser.dir=") || $0.hasPrefix("-Duser.home=") }
        jvmOptions.append("-Duser.dir=\(gameDirectory.path)")
        jvmOptions.append("-Duser.home=\(gameRoot.path)")
        // If HotSpot encounters a native fatal error, preserve hs_err_pid
        // in Documents so it can be exported after reopening NovaCraft.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            jvmOptions.append("-XX:ErrorFile=\(documents.appendingPathComponent("NovaCraft-hs_err_pid%p.log").path)")
            // HotSpot writes to this file independently of stdout/stderr.
            // It may survive early JVM initialization crashes on iOS.
            let bootLog = documents.appendingPathComponent("NovaCraft-hotspot-boot.log").path
            jvmOptions.append("-Xlog:os=info:file=\(bootLog):uptime,level,tags:filecount=2,filesize=2M")
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
                                if javaMajor == 21 && !experimentalDirectJNI {
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
