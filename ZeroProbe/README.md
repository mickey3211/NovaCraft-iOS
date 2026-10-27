# NovaCraft Zero — osobny test JVM bez JIT

## Wynik testu na fizycznym iPhone

**28 października 2026 — potwierdzony przez użytkownika.**

- Urządzenie: iPhone 13; iOS 27.0.1.
- Osobna aplikacja `NovaCraft Zero` uruchomiła się po podpisaniu IPA.
- `JNI_CreateJavaVM returned 0`.
- `ZERO_JVM_PROBE_OK Java bytecode major 65 | suma=500500`.
- `ZERO_JVM_PROBE_OK: JNI class executed on physical iOS device`.

Oznacza to, że statycznie dołączona maszyna Zero z oficjalnego
snapshotu OpenJDK Mobile potrafi na urządzeniu wykonać klasę
skompilowaną w formacie Java 21. **Nie oznacza** to jeszcze, że
snapshot jest środowiskiem JDK 21 ani że Minecraft jest grywalny.
To pozytywny test JNI i podstawowego bytecode w niezależnej aplikacji.

Kolejne wymagania przed pełnym NovaCraft:
- spójny runtime iOS Zero dla wymaganej wersji Java i wszystkich modułów;
- integracja statycznej JVM z oryginalnym interfejsem NovaCraft;
- kompletne sprawdzenie Java API, bibliotek gry i natywnych zależności;
- renderowanie Minecraft przez obsługę OpenGL/GLFW na iOS;
- test na urządzeniu i analiza wydajności Zero bez JIT.


**Cel:** potwierdzić na iPhonie 13 z iOS 27, że **statycznie
zlinkowana maszyna Zero** potrafi utworzyć `JavaVM` i uruchomić jedną
klasę Java, gdy dotychczasowy OpenJDK 21 Server VM dostaje
`CODESIGNING Invalid Page`.

To niezależny projekt testowy, **nie jest aktualizacją launchera
NovaCraft**, nie zawiera Minecrafta i nie uruchamia gry. Nie używa
kodu launchera Amethyst.

## Źródło i autorstwo

- Interfejs Objective-C, wywołanie JNI i klasa `NovaZeroSmoke`:
  oryginalny kod projektu NovaCraft (mickey3211).
- JVM statyczna, dostarczana przez OpenJDK Mobile:
  [openjdk-mobile/ios-tools](https://github.com/openjdk-mobile/ios-tools),
  [openjdk/mobile](https://github.com/openjdk/mobile).
- Oficjalny snapshot OpenJDK Mobile zawiera **nowszy JDK niż 21**
  (aktualny workflow upstream używa JDK 26). Klasa testowa jest
  kompilowana jako **Java 21 (major 65)**. To sprawdza wyłącznie
  możliwość wykonania kodu Java 21 na danej maszynie iOS, a **nie**
  zgodność Minecrafta 1.21.5, LWJGL, bibliotek natywnych ani API JDK.
- Kod OpenJDK ma własną licencję GPLv2 z wyjątkiem Classpath
  (sprawdź licencję danego wydania i wszystkie zależności).
  Nie twierdzimy, że NovaCraft napisał OpenJDK.

## Jak działa

1. GitHub Actions pobiera oficjalną bibliotekę `OpenJDK.xcframework`
   i `java_bundle-device` **z sumami SHA-256** przypiętymi
   do znanych wydanych plików.
2. Kompiluje `NovaZeroSmoke.java` poleceniem `javac --release 21`.
3. Kompiluje prostą aplikację iOS z **wbudowaną statyczną biblioteką
   OpenJDK Zero**. Nie pobiera binarnego HotSpot Server VM.
4. Generuje **niepodpisany** `NovaCraft-Zero-Probe-UNSIGNED.ipa`,
   który trzeba podpisać przy pomocy właściwego konta/certyfikatu.
5. Po instalacji naciśnij **Uruchom test JVM Zero**.
6. Jedynym wynikiem pozytywnym jest na ekranie:
   `ZERO_JVM_PROBE_OK Java bytecode major 65`.
   Jeśli wystąpi awaria, wyeksportuj log i zgłoś `.ips`.

## Ograniczenia

Sukces testu nie uruchamia Minecraft Java. Docelowa Java 21 Zero
musi być zbudowana spójnie ze wszystkimi modułami, przystosowana
do iOS i zintegrowana ze źródłami NovaCraft. Niedozwolone jest
na ślepo podmieniać statyczny plik `libjvm.a` za istniejący
dynamiczny `lib/server/libjvm.dylib`.

Odnośniki:
- https://github.com/openjdk-mobile/ios-tools/blob/main/docs/helloworld.md
- https://github.com/openjdk/mobile
- https://github.com/mickey3211/NovaCraft-iOS/blob/main/docs/JVM-IOS-27-CRASH.md
