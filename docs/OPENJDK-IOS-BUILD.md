# Building the actual iOS JVM for NovaCraft

Source: [OpenJDK/mobile](https://github.com/openjdk/mobile), an OpenJDK fork with iOS target support. Its README documents building a **static iOS ARM64 Zero JVM**. This is the first actual source build step beyond fake placeholder frameworks.

## Prerequisites

- Mac + Xcode with the iPhoneOS SDK, autoconf and a boot JDK compatible with the OpenJDK/mobile checkout (upstream instructions currently use JDK 24).
- Checkout of `openjdk/mobile` (use a reviewed pinned commit for reproducible distribution).
- Matching iOS libffi and CUPS support archives per the upstream README. Do not mix macOS or simulator builds with device archives.
- Several GB of free build storage and sufficient RAM.

## Build

```bash
git clone https://github.com/openjdk/mobile.git
brew install autoconf
OPENJDK_MOBILE_SRC="$PWD/mobile" \
IOS_JDK_SUPPORT="/absolute/path/to/extracted-support" \
BOOT_JDK="/absolute/path/to/boot-jdk/Contents/Home" \
bash scripts/build-openjdk-mobile-ios.sh
```

The build script invokes `configure` for `aarch64-macos-ios` and `make static-libs-image` using the iOS Zero interpreter and validates the resulting `libjvm.a` exists.

## What still must be engineered

The static archive **does not** satisfy NovaCraft's `dlopen("NovaJava21.framework")` contract. The next integration must link compatible OpenJDK runtime/class libraries into a single signed Mach-O framework, bundle `lib/modules` and resources, expose the JNI symbols, and run on an iOS device. OpenJDK/mobile's current development branch is not guaranteed to be Java 21 (verify the actual build's Java major). An iOS-native LWJGL + GL compatibility implementation is a **separate, essential component**, as are input/audio. Do not claim that Minecraft launches from this script alone.

Upstream documentation: https://github.com/openjdk/mobile
