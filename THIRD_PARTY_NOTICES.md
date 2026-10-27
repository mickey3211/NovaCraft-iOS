# Third-party components and intellectual-property notices

NovaCraft iOS is a separate launcher project. **The proprietary notice in
[LICENSE](LICENSE) covers only code and assets for which the NovaCraft
copyright holder owns the necessary rights. It does not apply to external
components or erase their licensing requirements.**

## Downloaded or built during the iOS CI process

| Component | Source | License / notes |
| --- | --- | --- |
| LWJGL 3 iOS fork | https://github.com/PojavLauncherTeam/lwjgl3 | LWJGL 3 is distributed under BSD-3-Clause. Review the **exact pinned fork revision** and all native dependencies for additional notices and changes. |
| Java 21 iOS runtime / OpenJDK | https://openjdk.org/legal/gplv2+ce.html | OpenJDK components are generally GPLv2 with the Classpath Exception. Confirm the exact archive, included components and their license notices before redistributing a compiled runtime. |
| libffi iOS binary | https://github.com/openjdk-mobile/ios-tools | Separate prebuilt library; check the archive's original licensing and any attribution/source obligations before redistribution. |
| Minecraft Java client and libraries | https://www.minecraft.net/ | Minecraft and its assets belong to their respective rights holders; Mojang/Microsoft terms apply. They are downloaded separately, not covered by the NovaCraft source notice. |

The build workflows may incorporate additional transitive dependencies.
The final IPA must preserve all notices and satisfy the licenses **of what
is actually packaged**. Building or distributing an IPA containing OpenJDK,
LWJGL or other third-party code may require delivering corresponding license
texts, copyright acknowledgments and/or access to source code.

## Source implementation references (not licensed under this project's notice)

- PojavLauncher iOS: https://github.com/PojavLauncherTeam/PojavLauncher_iOS
- Amethyst iOS: https://github.com/AngelAuraMC/Amethyst-iOS

Consult each upstream repository's LICENSE and notices. Do not assume code
from these launchers is available for proprietary reuse. Any code derived
from copyleft-licensed upstream material must satisfy the applicable
license; adding a proprietary label does not change those obligations.

## Trademarks

"Minecraft", "Mojang", "Microsoft", "Apple", "iOS" and other third-party
names and marks remain the property of their respective owners. NovaCraft
is an independent project and is not endorsed by them.

## Release gate

Do not publish a signed/unsigned IPA or repackage downloaded native libraries
as a product until the exact redistributable artifacts and license obligations
have been reviewed. This document is a project notice, not a substitute for
the license texts from each component.
