# NovaCraft 1.1.0 (build 2)

NovaCraft iOS maintenance release containing the latest launcher, version downloads, offline profiles, server status, JNI launch infrastructure and upstream LWJGL integration preparation.

- Bundle identifier remains `pl.novacraft.launcher` so the update targets the existing app, provided it is signed with a compatible identity.
- `CFBundleShortVersionString`: `1.1.0`; `CFBundleVersion`: `2`.
- GitHub Actions produces **unsigned** `NovaCraft-UNSIGNED.ipa`, which requires signing before iPhone installation.
- Actual Minecraft Java gameplay is **not verified**: signed iOS JVM and LWJGL renderer binaries remain prerequisites. The release number must not be presented as proof of gameplay compatibility.
- Before installing, preserve backups of important app data; signing changes may prevent in-place upgrades.
