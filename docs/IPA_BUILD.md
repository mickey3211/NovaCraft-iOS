# Build an unsigned iPhone IPA

The manually triggered GitHub Actions workflow **Build unsigned iPhone IPA** compiles NovaCraft for **physical iOS devices** (not the simulator), creates `Payload/NovaCraft.app` and uploads `NovaCraft-UNSIGNED.ipa` as an artifact.

## How to run from an iPhone

1. Open GitHub → repository `mickey3211/NovaCraft-iOS` → **Actions**.
2. Select **Build unsigned iPhone IPA**.
3. Tap **Run workflow** → choose `main` → **Run workflow**.
4. Open the completed run and download artifact `NovaCraft-unsigned-iPhone-IPA`.
5. The artifact ZIP contains `NovaCraft-UNSIGNED.ipa`.

## Important

- The IPA is **unsigned**. It cannot be installed directly on a normal iPhone by tapping the file.
- Installation requires appropriate Apple code signing and provisioning through a supported method. An Apple Developer account and macOS/Xcode build/signing environment are commonly used.
- Never share your Apple ID password, private signing keys or certificates in GitHub issues or repository files.
- An unsigned IPA does not bypass iOS security or grant JIT.
- This is a native launcher prototype. Minecraft Java runtime, LWJGL graphics and multiplayer gameplay are **not** implemented.
- A successful simulator compile does not guarantee a successful device build. Check Actions logs if the workflow fails.
