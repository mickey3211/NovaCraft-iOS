# UIKit GLFW integration checkpoint

Verified source: 3fba56ba30803dd00dc742b3fd0f513cf767bc5c
Successful iOS ARM64 workflow: https://github.com/mickey3211/NovaCraft-iOS/actions/runs/41017352230

The original NovaCraft UIKit adapter builds GLFW 3.4 with a CAMetalLayer-backed
EGL window, a game-thread event queue, touch pointer/button delivery, window
resize and focus changes. The build checks all 117 eagerly resolved entrypoints
from pinned LWJGL 39272d4d0ca119379024e3ca7207699fd3fce237. No new settings controls.

This is a library component, not a runnable Minecraft IPA. No rendered frame or
on-device execution has been verified.

## Remaining integration dependencies

1. Reconcile the integration branch with the successful complete runtime at
   5c6b4204c8599dcf0798d68c80e55f83913b6d45 before building another application.
2. The pinned OpenJDK mobile os_bsd.cpp returns the default process handle from
   os::dll_load whenever the VM is statically linked. os_posix.cpp opens this
   handle with RTLD_FIRST on Apple. Preloading a dynamic LWJGL library alone does
   not establish correct JNI lookup. NativeLibraries.c already handles built-in
   libraries independently via JNI_OnLoad_<name>; external native loading needs
   a reviewed runtime change and runtime verification.
3. Embed and sign the actual MobileGlues EGL/GLES framework dependencies plus
   matching LWJGL binaries/JARs and their notices. Audit every Mach-O dependency.
4. Host the UIKit view in SwiftUI before GLFW creates its window. Keep it alive
   until the Java thread destroys that window; coordinate background suspension.
5. Replace the diagnostic-only Zero launch path with invocation of the client's
   main class and resolved account/classpath/options. Preserve exception logs
   without recording tokens; do not start a diagnostic VM first.
6. Complete touch/keyboard/controller controls and native audio dependencies.
7. Verify actual Minecraft startup and rendering on a physical device before
   labeling an IPA playable. A successful component build is insufficient.

Known limits: one window, no raw mouse motion; primary touch maps to left click.
Public key/text/scroll injection exists but has not been connected to UI controls.
Focus notifications are not a complete background GPU suspension mechanism.
