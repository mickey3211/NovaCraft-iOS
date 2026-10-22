# NovaCraft Launcher — iOS prototype

An independent, from-scratch **Minecraft Java launcher UI prototype** built for mobile Safari on iPhone.

## Native iOS implementation

The repository now contains a native SwiftUI app foundation under `Native/NovaCraft`, an XcodeGen `project.yml`, a manually triggered simulator build workflow and setup instructions in [docs/NATIVE_SETUP.md](docs/NATIVE_SETUP.md). It is **source code, not a built IPA or a working Java runtime**. Microsoft login needs an app registration and has not been tested on device. The installer currently downloads the verified client JAR and version JSON only, not the full game assets/libraries.

## Status

- [x] Mobile-friendly launcher interface
- [x] Official Minecraft version manifest (releases and snapshots)
- [x] Local profiles and settings
- [x] Version search and selection
- [x] Draggable, editable touchscreen control layout (local demo)
- [x] Gamepad detection using Gamepad API and keyboard/mouse input tester (browser support varies)
- [x] Saved multiplayer server favorites and copy-address action (not game connections)
- [x] Microsoft account UI explaining planned secure OAuth, without collecting credentials
- [x] Status and activity log
- [x] Native SwiftUI app source scaffold (not compiled or signed)
- [x] Partial Minecraft installer: verified client JAR + version JSON
- [x] Microsoft OAuth PKCE/Xbox/XSTS/entitlement code (configuration and testing required)
- [x] Native GameController input adapter and touch overlay (not connected to Java)
- [ ] Complete Minecraft game file installer
- [ ] Microsoft OAuth login and Minecraft entitlement check (NOT YET AVAILABLE)
- [ ] Signed, tested native iOS IPA
- [ ] Java runtime, graphics bridge and touch input
- [ ] Launching Minecraft Java on iOS
- [ ] Actual gameplay input integration and multiplayer connections

**Important:** This repository is currently a web UI prototype, **not** a functional Minecraft Java runtime. Clicking Play explains what remains to be implemented. Touch controls, external input and server management are UI-level demonstrations and do not control Minecraft. Running Minecraft Java on iOS has significant technical and platform restrictions (JVM/JIT, graphics and signing). It is not guaranteed to work on iOS 27.

## Run

Open `index.html` in a browser or host it on any static HTTPS host. Version lists require network access to `piston-meta.mojang.com`.

On an iPhone, you can use Safari's Share → Add to Home Screen after hosting the page.

## Project layout

- `index.html` — standalone responsive prototype (HTML/CSS/JS)
- `docs/ARCHITECTURE.md` — intended native launcher architecture and milestones
- `LICENSE` — MIT license for this project's original source code

## Security

No Minecraft credentials or Microsoft tokens are requested or stored. Settings are saved only to localStorage. Minecraft is owned by Mojang/Microsoft; this project is not affiliated with them.
