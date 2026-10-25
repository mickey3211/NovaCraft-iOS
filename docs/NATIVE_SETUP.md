# NovaCraft native iOS — build and configuration

## What is implemented in source code

- SwiftUI tabbed launcher UI with version selection, download progress, local server list.
- Official Mojang version manifest retrieval.
- Download of the **client JAR** and version JSON for a selected release, with SHA-1 and file-size verification.
- Microsoft OAuth 2.0 authorization code with PKCE, followed by Xbox Live, XSTS and Minecraft Services requests to check entitlement and fetch a profile.
- Touch overlay with movable controls and input event routing.
- GameController adapter for common gamepad buttons and movement axes.
- Explicit fail-closed MinecraftRuntime interface: it throws an error instead of pretending to run Minecraft.
- Manual GitHub Actions simulator compilation workflow.

## What is NOT implemented

- A complete Minecraft installation: libraries, asset objects, native dependencies, JVM selection and per-version launch arguments.
- Working JVM / JIT / AOT runtime on iOS 27.
- LWJGL and OpenGL-to-Metal compatibility layer.
- Integration of input events into the Java game.
- A playable multiplayer client.
- A signed IPA for iPhone installation.
- Tested successful Microsoft login. The application registration is not configured.

These items require additional development, compatible platform permissions and real-device testing. Do not label them complete.

## Generate a native Xcode project

On macOS with Xcode and XcodeGen:

```sh
brew install xcodegen
xcodegen generate
open NovaCraft.xcodeproj
```

Set your own bundle identifier and signing team in Xcode.

The manually triggered GitHub Actions workflow `Validate native iOS app` runs a **simulator compile check only**, not a signed IPA build. It may consume GitHub Actions minutes.

## Configure Microsoft login

1. Register a Microsoft Entra application that supports **personal Microsoft accounts** and native/public clients.
2. Configure redirect URI `novacraft://auth` and register the URL scheme in the app (included in `Info.plist`).
3. Replace `YOUR_MICROSOFT_CLIENT_ID` in `Native/NovaCraft/Info.plist` (`MicrosoftClientID`) with the public application (client) ID. Do **not** put a client secret in the app. The app now reads the ID from Info.plist and fails clearly if it is not configured.
4. Verify that the chosen redirect URI is accepted by the registration platform and matches the value in `MicrosoftMinecraftAuth.swift`; the current code uses `novacraft://auth`.
5. Ensure the application has appropriate Microsoft/Xbox permissions and that the Xbox Live and Minecraft services flow is available for the registration. This may require additional provider configuration.
6. Test authorization code with PKCE, XBL, XSTS, entitlement and profile responses on a signed iPhone build.
7. Tokens are currently **in-memory only**. Before release, implement secure Keychain token persistence, refresh, logout and error handling.

Do not commit any secret or a user's access token to GitHub.

## iPhone-only development

You can edit files and run GitHub Actions from Safari. You cannot run Xcode directly on iPhone. Building and signing an installable IPA generally requires access to macOS/Xcode build infrastructure and Apple signing credentials. A simulator build cannot be installed on an iPhone.

## Legal / licensing

This is an independent launcher. Download game files from official sources, authenticate owners properly and follow Microsoft/Mojang terms. Do not redistribute proprietary Minecraft game assets in the app.
