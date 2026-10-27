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

### Rozbudowa aplikacji (październik 2026)

- **Pobieranie Minecraft w tle (iOS 17+):** systemowa sesja
  `URLSessionConfiguration.background` z zapisywanym na dysku planem,
  weryfikacją SHA-1 wszystkich pobranych plików, kolejką ograniczającą
  liczbę połączeń, próbami ponownego pobrania oraz obsługą wznowienia
  po ponownym otwarciu aplikacji i zdarzeń systemowego budzenia.
  Manifest wersji i indeks assetów przygotowuje się przy otwartej
  aplikacji, a duże pliki klienta, bibliotek i zasobów są pobierane w tle.
  Postęp liczony jest według liczby **zweryfikowanych plików**. Transfery
  mogą być opóźniane przez iOS, a wymuszone zamknięcie aplikacji może
  je zatrzymać; nie ma gwarancji nieprzerwanego pobierania.
- **Biblioteka NovaCraft:** podgląd lokalnej zajętości pamięci (gry,
  biblioteki, assety, światy), bezpieczny import paczek zasobów ZIP bez
  ich rozpakowywania lub wykonywania, eksport logów Java/HotSpot przez
  standardowy arkusz udostępniania i czyszczenie wyłącznie diagnostyki.
- **Wydajność:** konfigurowalny limit pamięci `-Xmx` (384–1024 MB
  lub do 1536 MB na urządzeniach z większą ilością RAM), 20/30/45/60
  FPS podglądu Metal i rozmiar terenu 24–48 kolumn.
- **NovaEngine 3D:** powtarzalne generowanie terenu za pomocą seeda,
  trzy oryginalne palety (neon/las/lawa), rysowanie tylko widocznych
  ścian, bufor głębi, obracanie i przybliżanie gestami.
- **Start:** szybkie skróty do świata NovaEngine oraz biblioteki.
- **Bezpieczeństwo:** import paczek ograniczony do .zip <=256 MB;
  pliki .jar lub dylib nie są instalowane jako mody.

**Rozmiar IPA nie jest miarą kompatybilności:** 55–60 MB
skompresowanego NovaCraft zawiera około 160 MB plików po rozpakowaniu.
Większy IPA Amethyst ma dodatkowe zewnętrzne środowiska Java i renderery.
Nie kopiujemy ich kodu do autorskiego silnika NovaEngine; dodatkowe
funkcje uruchamiania Minecraft Java wciąż wymagają implementacji.

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
