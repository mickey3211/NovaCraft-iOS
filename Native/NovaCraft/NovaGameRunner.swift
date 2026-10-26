import Foundation

/// Invokes Minecraft's Java entrypoint when real signed iOS JVM and LWJGL
/// libraries are embedded. No downloaded executable code is loaded on iOS.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        let jvmOptions = normalizeJVMOptions(args.jvmArguments)

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
                        args.classpath.withCString { classpath in
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

    /// JNI invocation accepts VM options, not the command-line java launcher
    /// syntax. -cp/--class-path is handled by -Djava.class.path in C.
    private static func normalizeJVMOptions(_ input: [String]) -> [String] {
        var output: [String] = []
        var index = 0
        while index < input.count {
            let value = input[index]
            if value == "-cp" || value == "-classpath" || value == "--class-path" {
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
                value.hasPrefix("--add-exports=") || value.hasPrefix("--add-modules=") {
                output.append(value)
            }
            index += 1
        }
        return output
    }
}
