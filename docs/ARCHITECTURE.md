# NovaCraft iOS — architecture roadmap

## Phase 1: Browser prototype (implemented)

Single-file HTML/CSS/JS, designed for mobile Safari:
- Fetch official Mojang version manifest over HTTPS.
- Select releases and snapshots.
- Store nickname, selected version and future runtime preferences in localStorage.
- Show meaningful runtime status and errors.
- Explicitly avoid pretending to launch Minecraft.
- Editable touch-control overlay with draggable buttons and local persistence.
- Browser-level gamepad detection and keyboard/mouse event testing (hardware-dependent).
- Saved multiplayer server addresses (no live server connection yet).
- Microsoft account placeholder with no credential collection.

No authentication or game runtime exists yet.

## Phase 2: Native SwiftUI app

Proposed source tree:

```text
NovaCraft/
  App/NovaCraftApp.swift
  Features/
    Home/HomeView.swift
    Versions/VersionListView.swift
    Accounts/AccountView.swift
    Settings/SettingsView.swift
    Logs/LogView.swift
  Services/
    MinecraftManifestService.swift
    MinecraftDownloadService.swift
    MicrosoftAuthService.swift
    GameLaunchCoordinator.swift
  Runtime/
    JavaRuntimeBridge.swift
    GraphicsBridge.swift
    TouchControls.swift
    ControllerInputBridge.swift
    KeyboardMouseBridge.swift
  Multiplayer/
    ServerListStore.swift
    JavaServerConnector.swift
  Models/
    MinecraftVersion.swift
    LauncherProfile.swift
```

- Use URLSession with HTTPS, checksums, cancellation, progress, and background downloads where possible.
- Use Keychain for tokens, never localStorage or plaintext files.
- Use Microsoft authorization code + PKCE through an approved sign-in flow. Verify game ownership.
- Validate every download against official metadata; handle filesystem sandboxing.
- Separate UI from runtime bridge with testable interfaces.
- Use Apple GameController framework for supported controllers and UIKit input APIs for keyboard/pointer input; actual Minecraft bindings depend on the game runtime.
- Multiplayer must be implemented inside a functioning Java client; a saved address is not a connection to a server.

## Phase 3: Minecraft runtime research

Minecraft Java on iOS is a substantial independent engineering challenge:
- Java VM compatibility with the iOS code-signing and execution model.
- JIT entitlement/restrictions; AOT/interpreter alternatives require investigation.
- LWJGL compatibility and translating OpenGL rendering to iOS graphics APIs.
- Audio, input, controller and touch mapping.
- Minecraft version-specific native libraries.
- Resource limits and thermal throttling on iPhone 13.

**No guarantee of full compatibility on iOS 27.** A working UI or signed IPA is not evidence of a working Java runtime.

## Phase 4: Build and distribution

Native iOS binaries normally require Xcode/macOS build infrastructure and code signing. iPhone-only authoring is possible using a browser, but not equivalent to an on-device Xcode environment. Consider remote macOS CI with appropriately protected signing secrets. Distribution/sideloading is subject to Apple rules and platform restrictions.

## Legal and privacy

Use original code and assets or correctly licensed dependencies. Do not redistribute Minecraft game binaries as part of the launcher. Respect Mojang/Microsoft terms and branding. Never solicit account passwords in a custom form.
