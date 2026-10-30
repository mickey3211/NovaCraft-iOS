# NovaCraft: implementation findings for iOS 27

Reviewed 2026-10-29. Target: iPhone 13, iOS 27.0.1, Minecraft Java 1.21.5.
No Amethyst application source is imported or rebranded.

## What existing launchers actually provide

| Layer | Pojav/Amethyst architecture | NovaCraft consequence |
| --- | --- | --- |
| VM | Patched OpenJDK Server VM with debugger/JIT mechanisms on normally signed devices | Cannot assume `-Xint` removes executable-memory requirements; NovaCraft's confirmed no-JIT route is static Zero |
| Java image | Versioned runtime, class libraries and runtime data | The ios-tools example image has only java.base. Replace it with a matching source-built image, including tzdb.dat and configuration |
| LWJGL | iOS-specific Java/native bindings; desktop classifier artifacts are replaced | Downloading Mojang's desktop jars is insufficient; the iOS fork is a separate dependency |
| Window/input | Launcher-owned native context, window and input bridge | The original NovaEngine voxel demo does not implement GLFW |
| Graphics | GL4ES, MobileGlues, ANGLE or Mesa/MoltenVK paths depending on game/version | A Metal view alone cannot satisfy desktop OpenGL calls. An independent bridge plus a separately licensed translator is required |
| Accounts | Microsoft game entitlement and game token passed to Java | Argument builder now carries the account UUID, username and token; CI verifies online/offline arguments and token redaction. Actual Zero client execution remains blocked |
| New game versions | Changing native library requirements | Keep 1.21.5 as initial target; 26.3 has an SDL dependency beyond the existing 3.3.3 iOS LWJGL set |

## Evidence specifically about iOS 27

Amethyst issue 240 (iOS 27 beta black screen) was closed with a maintainer
comment pointing to a fixed July build. It is not evidence that all later
versions remain broken. Issue 355, reported for iOS 27.0.1, reaches Minecraft
Main.main and then fails to load org.lwjgl.sdl.SDL for Minecraft 26.3.
This establishes an executed client bootstrap in that report, not a playable
world or universal iOS 27 compatibility. That report uses debugger-assisted
JIT and a patched Java 25 runtime; it does not validate NovaCraft Zero.

The official Amethyst installation documentation requires JIT for normal
sideloading. Unofficial “no JIT” downloads are not a verified substitute for
reviewed source and matching native libraries.

## Implemented runtime build

`scripts/build-nova-zero-runtime.sh` pins OpenJDK/mobile and ios-tools commits
and verifies the libffi binary digest. It builds the VM and selected class
modules from one source revision, uses the matching host jmod/jlink tools,
packages the generated tzdb.dat, trust store, security data and per-module
configuration, and checks the module inventory. Matching macOS tools are built
separately to avoid the cross-build configuration inheriting Linux linker flags.
The build generates linker roots for exported Java JNI methods and per-library
initializers so static archive members remain discoverable by the JVM. It preserves third-party licenses and source identifiers.

Required image modules: java.base, java.desktop, java.datatransfer, java.prefs,
java.logging, java.xml, java.net.http, java.management, java.naming,
java.security.sasl, jdk.unsupported, jdk.crypto.ec, jdk.charsets, jdk.zipfs.

Important limit: OpenJDK Mobile excludes desktop AWT native libraries on iOS
in make/modules/java.desktop/Lib.gmk. Including java.desktop *classes* does
not implement native AWT. Native features and any required AWT replacement
must still be integrated independently. The build is not proof of device
execution, graphics compatibility or Minecraft performance.

## Remaining work, with concrete completion conditions

1. Runtime: successful source build and packaged image contains tzdb and the
   required modules; validate timezone and actual dependency loading on Zero.
2. Classpath/auth: connect the account-aware argument builder to the Zero
   client invocation; include the installed client and allowed iOS libraries.
   Argument identity checks pass in CI, but the Zero path still runs only the
   existing readiness routine.
3. GLFW bridge: native window/context creation, buffer swaps, resize events,
   keyboard/mouse/touch callbacks and function lookup on the correct thread.
4. Graphics: compile a reviewed translator for iOS ARM64 and connect it to the
   GLFW bridge; show a real Minecraft frame, not the NovaCraft voxel demo.
5. Runtime lifecycle: a single JVM per process, usable memory budget, safe
   app background/foreground behavior and exported crash diagnostics.

No extra test buttons are introduced. Build-time verification stays in CI;
user-facing launch remains Play with one saved diagnostic report.

## Primary sources

- https://github.com/HynisDev/Hynis-JE (another Amethyst fork, documents JIT; not an independent no-JIT graphics implementation)
- https://github.com/PojavLauncherTeam/PojavLauncher_iOS (archived predecessor)
- https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/README.md
- https://wiki.angelauramc.dev/wiki/getting_started/INSTALL
- https://github.com/AngelAuraMC/Amethyst-iOS/issues/240
- https://github.com/AngelAuraMC/Amethyst-iOS/issues/355
- https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/Natives/egl_bridge.m (architecture reference only)
- https://github.com/MobileGL-Dev/MobileGlues (separate LGPL-2.1 project)
- https://github.com/PojavLauncherTeam/lwjgl3/blob/39272d4d0ca119379024e3ca7207699fd3fce237/ci_build_ios.bash
- https://github.com/openjdk/mobile
- https://github.com/openjdk-mobile/ios-tools/blob/main/.github/workflows/combine-xcframework.yml
- https://github.com/openjdk-mobile/ios-tools/blob/main/docs/patches/symbol-keeper.md
