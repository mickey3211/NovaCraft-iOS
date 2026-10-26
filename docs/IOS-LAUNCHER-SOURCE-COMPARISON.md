# Review of open-source Minecraft Java launchers on iOS

This is a **component-level compatibility review**, not a fork or wholesale import of another launcher's UI or account code. NovaCraft remains a separate SwiftUI application.

## Reviewed source projects

| Codebase | Relevant engineering technique | Decision in NovaCraft |
| --- | --- | --- |
| [PojavLauncher_iOS](https://github.com/PojavLauncherTeam/PojavLauncher_iOS) | JAVA_HOME, libjli.dylib, JLI_Launch, iOS rendering adapters | Implement independently a JLI adapter for bundled Java 21 |
| [Amethyst](https://github.com/zodiuss/Amethyst) | Java Launcher Interface and HotSpot primordial guard-page flags | Use validated bootstrap option names for Java 21 |
| [Zenith](https://github.com/thenullastris/Zenith-Launcher) | Mobile JVM configuration, JIT detection, advanced graphics paths | Retain non-JIT interpreter startup while isolating JVM crash |
| [MaLauncher](https://github.com/TomaTheLoser/MaLauncher) | Runtime management and GL4ES/ANGLE renderer selection | Renderer remains a separate future compatibility task |
| [Hynis](https://github.com/HynisDev/Hynis-JE) | Mobile control and OpenJDK/LWJGL native stack | No UI or proprietary assets copied |
| [FlameLauncher](https://flamelaunchers.github.io/) | JVM and graphics integration on iOS | Reviewed as a design reference; no AGPL source imported |
| [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) | Metal backend for Fabric Minecraft | Not a replacement for the Java bootstrap and not required for this fix |

The five reviewed launcher repositories above include GPLv3 license files. Do not paste their source files into NovaCraft without proper attribution and GPLv3 redistribution review. NovaCraft's C adapter is implemented separately using the published Java Launcher Interface ABI and independently authored glue code.

## Why the October 26 on-device crash matters

NovaCraft's recorded native checkpoint was **JNI_CreateJavaVM**. That indicates the app reached JVM creation but exited before entering the Minecraft main class, so a graphics renderer change alone cannot repair this crash.

### Changes made for iOS Java21

1. Prefer the Java launcher entry point `JLI_Launch` from the bundled `libjli.dylib` instead of directly invoking `JNI_CreateJavaVM` for the Java21 runtime. Keep the direct JNI path for other Java majors if later supported.
2. Set `JAVA_HOME` and `INTERNAL_JLI_PATH` to the **bundled**, signed iOS Java21 runtime.
3. Include the same HotSpot startup guards used by multiple upstream iOS ports: `-XX:+UnlockExperimentalVMOptions` and `-XX:+DisablePrimordialThreadGuardPages`.
4. Remove the unrelated static OpenJDK XCFramework and extra module image from the app. Mixing two different embedded JVM implementations risks symbol conflicts and makes debugging impossible.
5. Add native binary audit before releasing test IPAs: inspect `JLI_Launch`, `JNI_CreateJavaVM`, iOS architecture and platform, and inventory all nested Mach-O binaries needing signing.

The actual JRE21 archive remains SHA-256-pinned in `scripts/build-vendor-ios-jre21.sh`. The separately compiled iOS LWJGL fork remains pinned in `.github/workflows/build-ios-lwjgl.yml`.

## What is NOT proven

- JLI startup must be tried on a physical iPhone after all nested binaries are signed. A successful unsigned IPA build only proves the files exist and the app compiles.
- Java21 library signing and entitlement compatibility depend on the signing tool and installation method.
- LWJGL dylibs alone do not implement a complete GLFW window, OpenGL-to-Metal translation, audio or touch input bridge.
- This change does not confirm a world can render or that multiplayer will work.
