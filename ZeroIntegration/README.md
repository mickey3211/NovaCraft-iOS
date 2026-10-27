# NovaCraft Z-Dev — integracja statycznej Zero JVM z właściwą aplikacją

**Status:** kompilacja eksperymentalna, nie Minecraft.

## Co użytkownik już potwierdził

Na iPhonie 13 / iOS 27.0.1 oddzielna aplikacja `NovaCraft Zero`
uruchomiła oficjalną **OpenJDK Mobile Zero JVM** (JNI_CreateJavaVM = 0)
i wykonała klasę w formacie Java 21 (`major 65`).
Komunikat: `ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=500500`.

To rozwiązuje tylko początkowy problem uruchamiania bytecode na urządzeniu
z ograniczeniami JIT. Nie oznacza działania Minecrafta.

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
  **NovaCraft Z-Dev** i kompilacja `16`, aby NIE zastąpić normalnego
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
