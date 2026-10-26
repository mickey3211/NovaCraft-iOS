import Foundation

/// The actual Java main() invocation path. It is only reachable when a signed
/// iOS JVM and an iOS-native LWJGL bridge have both been bundled in the IPA.
enum NovaGameRunner {
    static func run(_ args: NovaLaunchArguments, javaMajor: Int) -> Int32 {
        guard let library = NovaJavaRuntimeRegistry.frameworkURL(major: javaMajor) else { return -30 }
        let nativePath = Bundle.main.privateFrameworksURL?.path ?? ""
        // JNI accepts UTF-8 C strings and copies them into Java String objects.
        let pointers = args.gameArguments.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        let strings: [UnsafePointer<CChar>?] = pointers.map { pointer in
            pointer.map { UnsafePointer($0) }
        }
        return strings.withUnsafeBufferPointer { buffer in
            library.path.withCString { runtimePath in
                args.mainClass.withCString { mainClass in
                    args.classpath.withCString { classpath in
                        nativePath.withCString { nativeDir in
                            nova_jni_invoke_main(runtimePath, mainClass, classpath,
                                                 nativeDir, buffer.baseAddress,
                                                 Int32(strings.count))
                        }
                    }
                }
            }
        }
    }
}
