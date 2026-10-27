# NovaCraft iOS — Minecraft Java Launcher (wersja eksperymentalna)

**NovaCraft** to niezależny projekt launchera Minecraft Java Edition na iPhone'a
i iPada, prowadzony przez **mickey3211**. Aplikacja jest rozwijana w SwiftUI,
z obsługą instalacji plików gry, wersji Minecraft, logowania Microsoft
i eksperymentalnego uruchamiania Java 21 oraz LWJGL na iOS.

**NovaEngine Metal:** własny kod renderowania sceny voxelowej 24×24,
perspektywa 3D, generowanie widocznych ścian i sterowanie dotykowe.
Otwórz **Ustawienia → Uruchom autorski świat NovaEngine**, żeby
uruchomić niezależny test silnika graficznego.

[Architektura własnego NovaEngine](docs/NOVAENGINE-ORIGINAL.md).
Kod tego silnika nie jest kopią Amethyst ani jego portem.

> **Stan projektu:** prototyp / eksperymentalny silnik. Udana kompilacja IPA
> **nie** potwierdza, że Minecraft uruchomi się i będzie grywalny. Nadal
> potrzebna jest pełna integracja wyświetlania grafiki, natywnych bibliotek,
> sterowania i uprawnień iOS/JIT lub odpowiedniego trybu bez JIT.

## Prawa autorskie — Original code: ALL RIGHTS RESERVED

**Copyright (c) 2026 mickey3211. Wszelkie prawa zastrzeżone.**

Kod NovaCraft jest udostępniony do wglądu, a **nie jako otwarte
oprogramowanie na licencji MIT lub innej licencji zezwalającej na jego
ponowne wykorzystanie.**

Bez wcześniejszej pisemnej zgody właściwego właściciela praw autorskich
**nie udziela się zezwolenia** na:

- kopiowanie, przerabianie lub rozpowszechnianie oryginalnego kodu NovaCraft;
- używanie oryginalnego kodu NovaCraft do tworzenia innych launcherów,
  w tym własnych wersji Minecraft launcherów;
- sprzedaż lub sublicencjonowanie oryginalnych fragmentów projektu.

Sama publiczna dostępność repozytorium nie jest licencją na ponowne
wykorzystanie kodu. **GitHub nadal pozwala użytkownikom oglądać i forkować
publiczne repozytoria na zasadach swojej usługi**, a prawa wynikające
z obowiązującego prawa i wcześniejszych ważnych licencji pozostają nienaruszone.
Nie ma technicznego sposobu, aby całkowicie zablokować pobieranie
kodu z publicznego repozytorium.

Dokładne informacje: **[LICENSE](LICENSE)**.

**Uwaga:** ten zakaz dotyczy wyłącznie oryginalnego kodu i materiałów,
do których przysługują odpowiednie prawa. Nie obejmuje obcych bibliotek
ani kodu już udostępnionego na innych licencjach.
**[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)** opisuje m.in.
OpenJDK i LWJGL. Jeśli chcesz skorzystać z oryginalnego kodu NovaCraft,
skontaktuj się z właścicielem repozytorium i uzyskaj pisemną zgodę.

## Co zawiera projekt?

- Aplikację SwiftUI z interfejsem startowym, listą wersji i profilami.
- Mechanizm pobierania i weryfikowania plików Minecraft.
- Kod OAuth Microsoft/Minecraft (wymagający własnej konfiguracji i testów).
- Przygotowanie uruchamiania Java 21 i bibliotek LWJGL dla iOS.
- Raporty diagnostyczne startu JVM i błędów po naciśnięciu **Graj**.
- Eksperymentalne ekrany testowe Metal i sterowania dotykowego.
- **Autorski renderer terenu voxelowego Metal** z własnym shaderem, kamerą
  obrotową, powiększaniem i cieniowaniem powierzchni.
- Proces tworzenia niepodpisanego IPA w Codemagic.

## Kompilacja

**Za darmo na macOS w chmurze:**
[Instrukcja Codemagic](docs/CODEMAGIC-DARMOWE-IPA.md).
Konfiguracja znajduje się w pliku `codemagic.yaml`. Powstały IPA jest
**niepodpisany**. Przed instalacją na iPhonie wszystkie zagnieżdżone
frameworki i biblioteki natywne muszą otrzymać prawidłowy podpis.

Dokumentacja szczegółowa:
- [Architektura](docs/ARCHITECTURE.md)
- [Diagnostyka awarii Java na iPhonie](docs/IPHONE-JVM-CRASH-DIAGNOSTICS.md)
- [Informacje o bibliotekach zewnętrznych](THIRD_PARTY_NOTICES.md)
- [Lista kontroli przed upublicznieniem](docs/PUBLICATION_CHECKLIST.md)

## Informacje prawne

NovaCraft nie jest oficjalnym produktem Minecraft, Mojang, Microsoft ani
Apple. Znak Minecraft i pliki gry należą do ich właścicieli. Korzystanie
z gry wymaga przestrzegania jej warunków i odpowiednich uprawnień do konta.

**English:** The original NovaCraft source is *source-available for inspection,
not open-source licensed*. All rights are reserved. No permission is granted
to copy, modify, redistribute, sublicense, or incorporate original NovaCraft
code into another launcher without written permission, subject to applicable
law, GitHub's Terms of Service, existing valid grants, and third-party
licenses. See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
