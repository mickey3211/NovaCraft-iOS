# NovaCraft iOS: JVM launch crash mitigation (October 26, 2026)

## Physical-device finding
After tapping **Graj**, NovaCraft closed at `JNI_CreateJavaVM`. Another unsigned IPA with `JLI_Launch` also closed on the user's iPhone 13, so building libraries successfully is insufficient proof of game compatibility.

## Upstream implementation differences
The GPLv3 iOS Minecraft Java launcher family uses a dedicated native launch thread and a complete OpenJDK Java home (including `libjli` and `libjvm`) and separately signs every nested Mach-O file. The upstream runtime and LWJGL libraries in NovaCraft are already sourced separately; do not copy another app's account management, UI or other GPLv3 source files into this project without licensing and attribution review.

This change is an independently authored integration:
- Start the Java VM on its **own dedicated Thread with a 16 MiB stack**, rather than reserving a shared Swift cooperative worker indefinitely.
- Check `JAVA_HOME/lib/server/libjvm.dylib` with `dlopen` before calling JLI and return a useful failure code if iOS rejects its signature or any missing dependencies.
- Record the exact native failure stage. Remove stale stage logs before a new launch.
- Ask HotSpot to save a fatal VM report to `Documents/NovaCraft-hs_err_pid<process>.log` and let the user explicitly copy it.
- Keep conservative interpreter-only startup while debugging iOS code-signing and thread constraints.

## Important signer limitation
The integrated IPA is **unsigned** and includes about 42 native Mach-O images inside the JRE and LWJGL folders. **All** must be signed with a compatible iPhone provisioning profile/certificate, not merely `NovaCraft.app` and `NovaJava21.framework/NovaJava21`. The binary inventory is attached to the CI build as `NovaCraft-iOS-native-signing-inventory`. An iOS certificate may lack JIT/extended virtual memory entitlements; those capabilities cannot be added by copying files from another launcher.

## How to capture a useful crash report
1. Sign and install the latest integrated Java 21 + LWJGL IPA using a tool that recursively signs nested Mach-O.
2. Tap **Graj**. If the app closes, reopen it and use **Kopiuj etap awarii**.
3. If available use **Kopiuj raport JVM** for the first 16 KiB of HotSpot's native crash report.
4. For iOS-level terminations where HotSpot cannot write the report, inspect **Ustawienia → Prywatność i ochrona → Analizy i udoskonalenia → Dane analiz** for a NovaCraft crash report.
5. Do not post account credentials, tokens, device identifiers, or personal file paths without redacting them.

A successful CI build only verifies the unsigned IPA structure. It does **not** verify that Java, GLFW/OpenGL, or Minecraft can run on an iPhone.
