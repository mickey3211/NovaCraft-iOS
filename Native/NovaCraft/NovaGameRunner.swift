import Foundation

/// Invokes Minecraft's Java entrypoint when real signed iOS JVM and LWJGL
/// libraries are embedded. No downloaded executable code is loaded on iOS.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        // For JNI_CreateJavaVM the actual libjvm inside JAVA_HOME is more
        // reliable than the framework's extra entrypoint copy. The JLI path
        // continues to use the conventional framework entrypoint for discovery.
        let runtimePath = javaMajor == 21
            ? library.deletingLastPathComponent()
                .appendingPathComponent("lib/server/libjvm.dylib").path
            : library.path
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        // A tiny first-party Java 8-compatible trampoline records the first
        // executed Java bytecode before loading Minecraft. It lets us tell
        // JVM initialization failure from Minecraft classpath/graphics errors.
        let bootstrap = Bundle.main.bundleURL
            .appendingPathComponent("NovaBootstrap/novacraft-bootstrap.jar")
        guard javaMajor != 21 || FileManager.default.fileExists(atPath: bootstrap.path)
            else { return -56 }
        let probeOnly = javaMajor == 21 &&
            UserDefaults.standard.bool(forKey: "novacraft-jvm-probe-only")
        // Do not load Minecraft's argument list/classpath during a JVM probe.
        // The first step is testing that Java can execute one tiny class.
        let classpath = probeOnly
            ? bootstrap.path
            : (javaMajor == 21
                ? bootstrap.path + ":" + iosLWJGLClasspath(fallback: args.classpath)
                : iosLWJGLClasspath(fallback: args.classpath))
        let entrypoint = javaMajor == 21 ? "dev.novacraft.GameEntrypoint" : args.mainClass
        let gameArguments = probeOnly ? [] :
            (javaMajor == 21 ? [args.mainClass] + args.gameArguments : args.gameArguments)
        // Resolve JVM properties against the classpath that actually includes
        // the iOS LWJGL jars, not the original desktop-only Minecraft manifest.
        var jvmOptions = probeOnly ? [] : normalizeJVMOptions(args.jvmArguments)
        // JLI derives java.home from its bundled launcher path; do not
        // override it there. The direct Invocation API, however, does not
        // perform JLI path discovery and needs the explicit Java home.
        if javaMajor == 21 {
            let home = library.deletingLastPathComponent().path
            jvmOptions.append("-Djava.home=\(home)")
        }
        // User-controlled memory budget (384…1024 MB on 4 GB devices).
        // Clamp by physical RAM to reduce iOS jetsam termination risk.
        // This does not enable JIT or change Java/LWJGL compatibility.
        // Compatibility is on by default for sideloaded iOS applications.
        // User can turn it off to compare logs without changing the JRE.
        let compatibilityKey = "novacraft-ios-jvm-compatibility"
        let compatibility = UserDefaults.standard.object(forKey: compatibilityKey) == nil
            || UserDefaults.standard.bool(forKey: compatibilityKey)
        let physicalMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        let maximum = physicalMB < 6144 ? 768 : NovaPerformance.availableHeapMB()
        let heapMB = probeOnly ? 256 : (compatibility ? min(NovaPerformance.heapMB, maximum) : NovaPerformance.heapMB)
        jvmOptions.removeAll {
            $0.hasPrefix("-Xmx") || $0.hasPrefix("-Xms") ||
            $0 == "-Xint" || $0.hasPrefix("-XX:ReservedCodeCacheSize=") ||
            $0 == "-XX:+UseCompressedOops" || $0 == "-XX:-UseCompressedOops"
        }
        if probeOnly {
            // No Minecraft client, LWJGL or multi-gigabyte Java classpath.
            jvmOptions.append("-Xms32m")
            jvmOptions.append("-XX:ReservedCodeCacheSize=32m")
        } else if compatibility {
            jvmOptions.append("-Xms64m")
        }
        jvmOptions.append("-Xmx\(heapMB)m")
        jvmOptions.append("-Xint")
        jvmOptions.append("-XX:+UseSerialGC")
        jvmOptions.append("-XX:-UsePerfData")
        // The user's JVM log shows repeated EINVAL (errno 22) when HotSpot
        // tries to reserve the 1 GiB heap at preferred compressed-oop
        // addresses. Its fallback later succeeds, so this flag is an A/B
        // memory-layout diagnostic, NOT a confirmed fix for the crash.
        // Uncompressed oops use more RAM but avoid those address constraints.
        if compatibility || probeOnly {
            jvmOptions.append("-XX:-UseCompressedOops")
        }
        jvmOptions.append("-XX:-UseCompressedClassPointers")
        // The game runs on a dedicated Java thread rather than the UIKit main thread.
        // This does not provide a renderer; it only configures LWJGL's thread checks.
        jvmOptions.append("-Dorg.lwjgl.glfw.checkThread0=false")
        jvmOptions.append("-Dorg.lwjgl.system.allocator=system")
        if probeOnly {
            jvmOptions.append("-Dnovacraft.jvmProbeOnly=true")
        }
        if javaMajor == 21 {
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
            // Persist thread, memory-mapping and GC initialization events
            // before a native fatal signal or iOS termination.
            jvmOptions.append("-Xlog:os*=debug,arguments=info,gc+init=info:file=\(bootLog):uptime,level,tags:filecount=2,filesize=4M")
        }

        let gamePointers = gameArguments.map { strdup($0) }
        let jvmPointers = jvmOptions.map { strdup($0) }
        defer {
            gamePointers.forEach { free($0) }
            jvmPointers.forEach { free($0) }
        }
        let gameStrings: [UnsafePointer<CChar>?] = gamePointers.map { $0.map { UnsafePointer($0) } }
        let vmStrings: [UnsafePointer<CChar>?] = jvmPointers.map { $0.map { UnsafePointer($0) } }
        return gameStrings.withUnsafeBufferPointer { gameBuffer in
            vmStrings.withUnsafeBufferPointer { vmBuffer in
                runtimePath.withCString { runtimePath in
                    entrypoint.withCString { mainClass in
                        classpath.withCString { classpath in
                            nativePath.withCString { nativeDir in
                                // Direct JNI avoids restarting SwiftUI's app entrypoint.
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
