# NovaCraft Launcher — iOS prototype

An independent, from-scratch **Minecraft Java launcher UI prototype** built for mobile Safari on iPhone.

## Status

- [x] Mobile-friendly launcher interface
- [x] Official Minecraft version manifest (releases and snapshots)
- [x] Local profiles and settings
- [x] Version search and selection
- [x] Status and activity log
- [ ] Minecraft game file installer
- [ ] Microsoft OAuth login and Minecraft entitlement check
- [ ] Native SwiftUI iOS app / IPA
- [ ] Java runtime, graphics bridge and touch input
- [ ] Launching Minecraft Java on iOS

**Important:** This repository is currently a web UI prototype, **not** a functional Minecraft Java runtime. Clicking Play explains what remains to be implemented. Running Minecraft Java on iOS has significant technical and platform restrictions (JVM/JIT, graphics and signing). It is not guaranteed to work on iOS 27.

## Run

Open `index.html` in a browser or host it on any static HTTPS host. Version lists require network access to `piston-meta.mojang.com`.

On an iPhone, you can use Safari's Share → Add to Home Screen after hosting the page.

## Project layout

- `index.html` — standalone responsive prototype (HTML/CSS/JS)
- `docs/ARCHITECTURE.md` — intended native launcher architecture and milestones
- `LICENSE` — MIT license for this project's original source code

## Security

No Minecraft credentials or Microsoft tokens are requested or stored. Settings are saved only to localStorage. Minecraft is owned by Mojang/Microsoft; this project is not affiliated with them.
