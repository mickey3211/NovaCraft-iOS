# NovaCraft Z-Dev — integracja statycznej Zero JVM z właściwą aplikacją

**Status:** kompilacja eksperymentalna, nie Minecraft.

## Co użytkownik już potwierdził

Na iPhonie 13 / iOS 27.0.1 oddzielna aplikacja `NovaCraft Zero`
uruchomiła oficjalną **OpenJDK Mobile Zero JVM** (JNI_CreateJavaVM = 0)
i wykonała klasę w formacie Java 21 (`major 65`).
Komunikat: `ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=500500`.

To rozwiązuje tylko początkowy problem uruchamiania bytecode na urządzeniu
z ograniczeniami JIT. Nie oznacza działania Minecrafta.

## Potwierdzenie na urządzeniu — Build 16

Użytkownik przesłał zrzut ekranu **NovaCraft Z-Dev Build 16**
z pozytywnym wynikiem **wewnątrz oryginalnego interfejsu SwiftUI**:

```text
ZERO_STEP: JNI_CreateJavaVM returned 0
ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=500500
NOVA_ZERO_INTEGRATED_OK
Kod zwrotny: 0
```

Oznacza to **potwierdzone na iPhonie** działanie statycznego OpenJDK
Zero i wykonywanie kodu Java 21 w NovaCraft. Nie uruchomiono Minecrafta.

### Faza 2 — Build 17: test Java API i archiwum Minecraft

W kolejnej wersji test Java Zero dodatkowo:

- wypisuje `java.version` i nazwę JVM;
- sprawdza moduły `java.base`, `java.desktop`, `java.logging`,
  `java.xml`, `java.net.http`, `java.management`, `jdk.unsupported`;
- próbuje kompresji i dekompresji ZIP;
- tworzy i łączy wątek Java;
- jeśli `client.jar` wybranej wersji został pobrany **wewnątrz
  NovaCraft Z-Dev**, parsuje wyłącznie spis wpisów ZIP i liczy pliki
  `.class`.

Bez uruchamiania Minecrafta, pobierania dodatkowego niezweryfikowanego
kodu, ładowania GLFW i przesyłania danych konta. Wynik
`MINECRAFT_CLIENT_JAR: NOT_DOWNLOADED_IN_THIS_APP` oznacza brak
pliku w tej instalacji, a nie awarię Zero. Wyniki testu nie dowodzą
kompatybilności pełnego klienta ani wydajności.

## Co zawiera bieżąca gałąź

- Cały istniejący interfejs SwiftUI NovaCraft, NovaEngine/Metal,
  bibliotekę pobierania i ustawienia.
- `NovaZeroIntegratedBridge.m`: **oryginalny most JNI** na bazie
  zweryfikowanego testu Zero, statycznie linkowany z OpenJDK Mobile.
- `NovaZeroIntegratedScreen.swift`: test z poziomu oryginalnego
  launchera i eksport logów `NovaCraft-integrated-zero.log`.
- Oficjalny OpenJDK Zero z `openjdk-mobile/ios-tools`, pobierany przez
  GitHub Actions z dwoma przypiętymi SHA-256 (snapshot nowszy niż JDK 21).
- `NovaZeroSmoke.java`: pierwsza klasa Java na potrzeby NovaCraft,
  kompilowana do Java 21 (`--release 21`).
- Osobny identyfikator `pl.novacraft.zero.integrated`, nazwa
  **NovaCraft Z-Dev** i kompilacja `17`, aby NIE zastąpić normalnego
  NovaCraft ani osobnej wcześniejszej aplikacji Zero Proof.

## Test na iPhonie

1. Pobierz artefakt unsigned IPA z GitHub Actions dla gałęzi
   `nova-zero-integration`, podpisz przez iPASide.
2. Otwórz `NovaCraft Z-Dev` → **Ustawienia** →
   **Uruchom test Java Zero w NovaCraft**.
3. Naciśnij `Uruchom Zero w NovaCraft`.
4. Oczekiwany wynik:
   ```text
   ZERO_STEP: JNI_CreateJavaVM returned 0
   ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=500500
   NOVA_ZERO_INTEGRATED_OK
   ```
5. Jeżeli jest awaria, wyślij `NovaCraft-integrated-zero.log` i odpowiedni
   raport `.ips`, po usunięciu prywatnych danych.

Użytkownik musi uruchomić test na fizycznym urządzeniu. Kompilacja CI
nie jest potwierdzeniem działania JNI na iOS.

## Czego nie należy jeszcze robić

**Przycisk Graj jest w tej wersji celowo zablokowany na poziomie
runtime**, ponieważ aktualny launcher wymaga pełnego środowiska
Java 21 i rendererów GLFW/OpenGL, których nie zapewnia statyczny
snapshot Zero. W szczególności:

- Nie podmieniaj `lib/server/libjvm.dylib` na statyczny `libjvm.a`.
- Nie dołączaj starego Server VM do testu, bo na iOS 27 został
  zablokowany przez `CODESIGNING Invalid Page`.
- Nie kopiuj Amethyst pod inną marką. Zależności OpenJDK i LWJGL
  mają własnych twórców i licencje.

## Wymagane dla następnej fazy

1. Dopasować statyczną Zero JVM, moduły `java.base`, `java.desktop`,
   `java.logging`, `java.xml`, `java.net.http` oraz pozostałe
   wymagane moduły **w tej samej wersji/runtime** odpowiednim do
   Minecraft 1.21.5.
2. Testować narastająco: bytecode → classpath → Mojang game bootstrap →
   natywne API LWJGL → OpenGL/Metal → świat i sterowanie.
3. Zapewnić autoryzację Minecraft Java kontem Microsoft i poprawne
   przekazanie tokenów (bez logowania danych wrażliwych).
4. Wydajność na iPhonie 13 trzeba zweryfikować osobno; Zero działa
   bez JIT i może być zauważalnie wolniejszy niż desktopowy HotSpot.

**Autor projektu, interfejsu i nowego mostu:** mickey3211/NovaCraft.
**OpenJDK Mobile:** osobny projekt open-source i osobne obowiązki licencyjne.

Źródła:
https://github.com/openjdk/mobile
https://github.com/openjdk-mobile/ios-tools

## Kontrola nagłówków klas klienta — następny etap

Diagnostyka czyta osiem bajtów nagłówka każdej bazowej klasy w `client.jar`:
sprawdza magic `CAFEBABE`, wersję class file względem uruchomionej JVM
oraz odrzuca klasy preview (test nie włącza preview). Raport pokazuje
liczbę błędnych i nieobsługiwanych nagłówków, najwyższą wersję bytecode
oraz obecność `net/minecraft/client/main/Main.class` dla nowoczesnego klienta.
Brak tej klasy nie jest ogólnym testem poprawności dawnych wersji Minecraft.

Wpisy `META-INF/versions/` są liczone osobno, bez deklarowania ich zgodności.
`MINECRAFT_BASE_CLASS_HEADERS: COMPATIBLE` dotyczy wyłącznie nagłówków
bazowych klas. Nie sprawdza pełnej struktury bytecode, zależności,
podpisów archiwum ani GLFW/OpenGL i nie oznacza gotowości do gry.
Nie są ładowane ani wykonywane klasy Minecrafta.

Test regresyjny `ZeroIntegration/Tests/NovaZeroReadinessTest.java` sprawdza
zgodny i zbyt nowy bytecode, preview, uszkodzone nagłówki/ZIP, pusty klient,
brak klasy startowej i wpisy multi-release. Workflow `zero-readiness-check.yml`
kompiluje i uruchamia go na Java 21.

## Build 19 — jeden raport, bez przycisków testów

Usunięto ręczne testy JVM/Metal z ustawień i test Java 21 z ekranu Start.
Przycisk Graj uruchamia sprawdzenie Zero raz w procesie, na dedykowanym
wątku. Kolejne naciśnięcia używają tego samego wyniku. Ustawienia zawierają
jeden ekran Raport diagnostyczny z udostępnianiem istniejącego logu.
Zmiana wersji po uruchomieniu JVM wymaga restartu i jest jawnie zgłaszana.

Paczka upstream zawiera tylko java.base; potwierdza to workflow
openjdk-mobile/ios-tools combine-xcframework.yml (`--add-modules java.base`).
Archiwum java_bundle-device zawiera tylko release i lib/modules, bez tzdb.dat.
Nie dodajemy do niego niezgodnych modułów z desktopowego JDK.
Pełne środowisko iOS nadal wymaga zbudowania/portowania brakujących modułów.

ZIP używa stałego lokalnego znacznika czasu, żeby nie wymagał tzdb do
sprawdzenia samej kompresji. Osobna automatyczna kontrola stref czasowych
ujawnia brak tzdb. Dokładna przyczyna i stos błędów ZIP/stref trafiają do
raportu; nie uznajemy tego za potwierdzoną naprawę na iPhonie przed jego
uruchomieniem. Minecraft pozostaje zablokowany z wyraźnym komunikatem.
