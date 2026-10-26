# Java 21 on iOS

NovaCraft currently has no working Java 21 runtime. This change adds an optional packaging step for a future iOS-arm64 Java runtime framework. A macOS JDK is not an iOS runtime.

The build checks for `Vendor/NovaJavaRuntime.framework/NovaJavaRuntime`, validates its arm64 architecture and exported `JNI_CreateJavaVM` symbol, then embeds it into the app. Without the framework, the existing launcher builds normally. The final signer must sign embedded frameworks as well.

The app currently probes JNI symbols but does not create a JVM. A compatible licensed Java 21 runtime, JNI startup, LWJGL-to-Metal implementation, and actual Minecraft device tests are still required. Offline profiles do not bypass authentication on premium servers.
