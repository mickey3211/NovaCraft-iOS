# Using only the upstream iOS runtime and LWJGL components

NovaCraft retains its own SwiftUI launcher, Minecraft installer, Java launch parameter builder and account handling. The external project is **not** installed as the launcher.

Native components sourced from:
- `PojavLauncherTeam/lwjgl3` (fork with an iOS-specific `ci_build_ios.bash`; LWJGL BSD-3 license) — Java JAR files and iOS `.dylib` files only.
- OpenJDK iOS runtime sources / an appropriately signed, legally redistributable Java runtime (OpenJDK GPLv2 + Classpath Exception, subject to the actual distribution license).

To build the LWJGL dependencies, run the **Build iOS LWJGL components** manual GitHub workflow with a reviewed upstream commit SHA. Its result is **not** an IPA. After reviewing licenses, binary dependencies (including libffi/shaderc), platform flags, code signatures and security implications, place the outputs in:
```
Vendor/LWJGL-iOS/jars/*.jar
Vendor/LWJGL-iOS/native/*.dylib
```
The IPA workflow copies these into `NovaCraft.app/LWJGL-iOS` and `NovaCraft.app/Frameworks`. The Java runtime classpath prefers these JARs over desktop LWJGL. Every executable `.dylib` and JVM must be properly signed, with correct `@rpath` dependencies.

**Not yet solved:** actual signed JVM framework for Java 21, dependency relocation and signing, GLFW + graphics contexts, OpenGL/Metal rendering, input/audio, required entitlements/JIT support and device testing. The upstream LWJGL build itself depends on prebuilt/downloaded components and may fail; do not assume uploading libraries makes Minecraft playable. Redistributing parts of code from the original iOS launcher (GPLv3) can impose different licensing conditions: do not copy its launcher code or assets without auditing obligations.

Upstream:
- https://github.com/PojavLauncherTeam/lwjgl3
- https://github.com/PojavLauncherTeam/PojavLauncher_iOS
