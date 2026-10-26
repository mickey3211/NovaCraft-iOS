# NovaEngine 0.2 — iOS hardware diagnostics and launcher UX

This iteration adds a native Metal GPU/command-queue probe and a truthful bundled-JVM availability check. It does **not** include a Java 21 runtime, a LWJGL implementation, a Metal renderer for Minecraft, or executable Minecraft.

Launcher changes:
- Persistent dark/light appearance setting.
- Filter Minecraft versions to installed or all.
- Wi-Fi reminder before downloading large version files.
- Dedicated Settings tab and hardware status card.
- Existing verified Mojang downloads and progress indicator retained.

Next engineering milestones before Minecraft Java can run:
1. Build or integrate a legally distributable, iOS-compatible Java 21 runtime and validate JVM startup on physical hardware within Apple's platform restrictions.
2. Implement native JNI and Minecraft launch arguments/classpath; handle Java version requirements per Minecraft release.
3. Implement LWJGL-compatible input/window/audio and an OpenGL-to-Metal rendering path (or an alternative verified renderer).
4. Run a controlled smoke test of Minecraft main class and debug missing native dependencies, then render a game frame.
5. Test memory pressure, assets, controller/touch mapping and world saves on iPhone.

The Microsoft Minecraft Services HTTP 403 approval process is separate from runtime development.
