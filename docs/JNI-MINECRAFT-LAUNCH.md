# Native Minecraft Java entrypoint (NovaEngine)

This change implements a real JNI Invocation API path: `JNI_CreateJavaVM`, `FindClass`, `GetStaticMethodID`, Java `String[]` construction and `main(String[])` invocation. The bridge is implemented in `NovaJNIInvoker.c`, connected to Swift by `NovaGameRunner.swift`.

**This is not a playable Minecraft build.** It is deliberately gated on both signed, iOS-device-native libraries existing in the app:

- `Frameworks/NovaJava<major>.framework/NovaJava<major>` — iOS ARM64 JVM, with Java version selected from the official Minecraft manifest.
- `Frameworks/NovaLWJGLBridge.framework/NovaLWJGLBridge` — a real iOS-native implementation of the LWJGL/OpenGL/Metal compatibility surface required by the chosen Minecraft client.

Neither of these runtimes is currently supplied by NovaCraft. The bridge's existence is only a prerequisite; merely embedding an empty or placeholder framework **will not** make Minecraft work. Java natives, JAR linkage, version-specific JVM options, rendering, audio, input and device testing are still required. The current launcher uses offline nicknames for this path; Microsoft game token integration is not wired to JNI yet.

JVM creation can occur only once per process. Java errors are logged by `ExceptionDescribe` and the JVM stays resident. Do not treat a successful return from JNI as proof of playable graphics or network functionality.
