# NovaEngine JVM integration milestone

NovaCraft is **not yet able to execute Minecraft Java**. The app can now check whether a code-signed `NovaJavaRuntime.framework` is embedded in the iOS app and exports both JNI invocation functions. This is a diagnostic probe only.

## Requirements for an actual JVM

1. Obtain or build a legally redistributable **Java 21 runtime targeting iOS arm64**. A macOS, Linux or Windows JDK will not load on iOS.
2. Package all executable code and native dependencies as signed iOS frameworks **at app build/signing time**. A JAR downloaded by the launcher is data; dynamically loading unsigned native code from app storage is not supported by normal iOS signing.
3. Integrate the framework and its dependencies in `project.yml` and the GitHub Actions build. **No Java binary is currently bundled or fetched.**
4. Verify `JNI_CreateJavaVM` startup and class loading on a physical device. Avoid promising unrestricted JIT; iOS code-signing and execution restrictions may require an interpreter/AOT implementation.
5. Implement Java launch options, JNI lifecycle, LWJGL API compatibility, rendering, input and audio, then test an actual Minecraft frame.
6. Multiplayer requires a working client, Minecraft networking, and authenticated Microsoft accounts on online-mode servers. Offline profiles do not bypass server authentication.

## What the current probe checks

- Looks for `Frameworks/NovaJavaRuntime.framework/NovaJavaRuntime`.
- Attempts to load the framework using the system dynamic loader.
- Verifies `JNI_CreateJavaVM` and `JNI_GetCreatedJavaVMs` exports.
- Reports missing or unloadable libraries without claiming successful Java startup.

The name `NovaJavaRuntime.framework` is a packaging contract for a future iOS-compatible runtime, **not an existing implementation**.
