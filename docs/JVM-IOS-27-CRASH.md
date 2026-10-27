# NovaCraft — JVM Java 21 / iOS 27: diagnoza

Data: 27 października 2026 r.

## Co wiadomo

Ostatni zrzut ekranu pokazuje, że JVM zatrzymuje się podczas
`JNI_CreateJavaVM`, **po udanym załadowaniu `libjava.dylib`**.
To już inny błąd niż wcześniejsze `AppGraph.shared may only be set once!`
związane ze ścieżką `JLI_Launch`.

W ZIP/IPA NovaCraft jest:
- środowisko OpenJDK 21.0.8 zbudowane dla iOS ARM64,
- `lib/server/libjvm.dylib`, który identyfikuje się jako
  **OpenJDK 64-Bit Server VM**, a nie jako Zero VM;
- Java 21 i biblioteki LWJGL iOS;
- natywny `libjava.dylib`, który HotSpot zdołał załadować.

**Nie mamy pełnego `hs_err_pid*.log` ani raportu iOS `.ips`
z fizycznego iPhone'a. Nie można więc potwierdzić, czy przyczyną
jest pamięć wirtualna, ograniczenia JIT, podpis innej biblioteki,
JNI lub wewnętrzny błąd tego builda HotSpot.**

## Wprowadzone poprawki diagnostyki

1. Usunięto zbędny `dlopen(libjli.dylib)` z trybu bezpośredniego
   JNI. Powiązania biblioteki `libjvm.dylib` na iOS ARM64 nie
   wymagają `libjli`.
2. Oddzielono prosty test JVM od argumentów, klas i bibliotek Minecrafta:
   uruchamia tylko pierwszą klasę Java w pakiecie NovaCraft.
3. Test uruchamia JVM z małym stosem sterowanym przez dedykowany
   `Thread`, `-Xint`, `-Xms32m`, `-Xmx256m`,
   `-XX:ReservedCodeCacheSize=32m` i `UseSerialGC`.
4. Rozszerzono log HotSpot o diagnostykę OS, wątków,
   inicjalizacji GC oraz użytych argumentów.
5. Dodano ekran **Ustawienia → Pełny raport awarii Java 21**.
   Raport zawiera dostępne logi Java, HotSpot i `hs_err_pid*.log`.
   Nic nie jest wysyłane automatycznie. Przed udostępnieniem
   należy usunąć prywatne informacje.

## Jak testować

1. Podpisz nowy IPA, w tym **wszystkie zagnieżdżone pliki .dylib**.
2. W NovaCraft wejdź w **Ustawienia → Uruchom samą Java 21 (test)**.
3. Jeśli aplikacja zniknie, ponownie otwórz NovaCraft.
4. Wybierz **Ustawienia → Pełny raport awarii Java 21**.
5. Przejrzyj raport, usuń tokeny i dane osobowe oraz prześlij
   bezpiecznie treść raportu JVM.
6. Jeśli raportu `hs_err_pid*.log` nie ma, poszukaj
   `NovaCraft*.ips` w danych analiz iOS.

Sukces małego testu to komunikaty
`JVM_ENTRY_REACHED` oraz `JVM_PROBE_OK`.
Nie jest dowodem uruchomienia Minecrafta ani renderera GLFW.

## Wariant Server a Zero

Źródła OpenJDK Mobile wskazują, że na iOS domyślnie
buduje się **Zero VM**, bo zwykłe aplikacje iOS nie mogą swobodnie
tworzyć stron pamięci z jednoczesnymi uprawnieniami zapisu i wykonywania.

Źródło:
https://github.com/openjdk/mobile

Obecny NovaCraft ma **Server VM**, której nawet z `-Xint` mogą
być potrzebne natywne fragmenty kodu maszynowego lub pamięć
wykonywalna, których podpisanie darmowym Apple ID nie zapewnia.

**Kolejny etap inżynierski**, jeśli sam test JVM nadal kończy się
awarią: przygotowanie i podpisanie zgodnego, w pełni zweryfikowanego
iOS ARM64 OpenJDK Zero Runtime na bazie OpenJDK Mobile albo analiza
konkretnej ścieżki błędu z `hs_err` i logu systemowego iOS.
Nie należy instalować do aplikacji JDK dla macOS/Linux — to
niezgodne binaria. Nie należy również kopiować cudzych
launcherów lub ich kodu bez stosowania ich licencji.

Nawet sprawna JVM nie uruchomi poprawnie Minecraft Java, dopóki
NovaCraft nie otrzyma pełnej, zgodnej z Minecraftem obsługi
GLFW/OpenGL i renderowania na iOS.


## Test z 27/28 października 2026 — Build 15 (iPhone 13 / iOS 27.0.1)

Zebrany przez użytkownika dziennik natywnej JVM daje mocniejszy,
aczkolwiek nadal niepełny punkt zaczepienia:

- Test `-Dnovacraft.jvmProbeOnly=true`: **tak** — brak klienta Minecraft,
  assetów, LWJGL i zależności Minecraft w classpath.
- `-Xmx256m`, `-Xms32m`, `-XX:ReservedCodeCacheSize=32m`,
  `-XX:-UseCompressedOops`, `-XX:-UseCompressedClassPointers`,
  `-Xint`, `-XX:+UseSerialGC`.
- `libjava.dylib`: `shared library load ... was successful`.
- `Compressed Oops: Disabled`; `Heap Max Capacity: 256M`.
- `VM Periodic Task Thread` rozpoczęty po ok. 17 ms.
- `VM Thread` rozpoczęty po ok. 42 ms.
- Log kończy się około 43 ms; w oddzielnym stdout widnieje
  `JNI_CreateJavaVM entered, options=21`.
- Ostatni checkpoint: `Tworzenie maszyny Java (JNI_CreateJavaVM)`.
- **Nie ma** `JVM_ENTRY_REACHED`, `JVM_PROBE_OK` ani
  `NovaCraft-hs_err_pid*.log` w przekazanym raporcie.

**Wniosek:** awaria następuje podczas *natywnego tworzenia JVM*,
a nie pobierania Minecrafta, sprawdzania jego licencji, alokacji
wielkiej sterty, rozwiązywania bibliotek LWJGL czy wykonywania bytecode
Java. Nie ma podstaw, aby ponownie przeprojektowywać system pobierania
lub zwiększać pamięć. Jest za wcześnie, aby wskazać JIT jako
potwierdzoną przyczynę — brakuje sygnału iOS i stack trace.

### Pilnie potrzebny dowód: iOS .ips

Na iPhonie: **Ustawienia → Prywatność i ochrona → Analizy i
ulepszenia → Dane analiz**; znajdź raport `NovaCraft-...`
lub `JetsamEvent-...` odpowiadający godzinie zamknięcia aplikacji.
Otwórz go i przez **Udostępnij** zapisz do aplikacji Pliki.
Przed wysłaniem usuń dane prywatne (ścieżki, identyfikatory, tokeny).
Najbardziej istotne pola:

- `exception.type`, `exception.subtype`, `termination.reason` i `signal`;
- `faultingThread`, `triggeredThread`, `threads[*].frames`;
- `usedImages` oraz informacje o `libjvm.dylib` i `libsystem_pthread.dylib`;
- w przypadku `JetsamEvent` — `reason`, `pageSize`,
  `rpages`, `states`, `limit`.

Jeśli nie ma raportu `hs_err`, system może zatrzymać proces bez
możliwości zakończenia procedury fatal error w HotSpot — dlatego log
HotSpot może urywać się na rozpoczęciu `VM Thread`, a nie w miejscu
rzeczywistego błędu.

### Wariant Zero JVM jako odrębny projekt

Projekt OpenJDK Mobile wyjaśnia, że dla **iOS domyślne
JVM to Zero**. To wariant bez klasycznego JIT, natomiast obecna
`lib/server/libjvm.dylib` NovaCraft jest **Server VM**.
`-Xint` nie zamienia pliku binarnego Server VM w Zero.

OpenJDK Mobile publikuje wskazówki budowania biblioteki
`lib/zero/libjvm.a` z kodu źródłowego. To statyczna biblioteka
wymagająca właściwej integracji z aplikacją i dopasowanych klas
Java; **nie należy jej bezpośrednio podmieniać** za istniejącą
`lib/server/libjvm.dylib` innej wersji JDK. W październiku 2026
oficjalne workflow `openjdk-mobile/ios-tools` buduje nowszy JDK,
więc nie jest automatycznym zamiennikiem 21.0.8 używanego
przez Minecraft 1.21.5.

Źródła:
- https://github.com/openjdk/mobile
- https://github.com/openjdk-mobile/ios-tools/blob/main/.github/workflows/build-openjdk.yml
- https://github.com/AngelAuraMC/Amethyst-iOS/issues/255

**Zasada dalszej naprawy:** dopóki `JVM_PROBE_OK` nie pojawia się w
minimalnym teście, nie można zapewniać użytkownika, że nowy IPA
uruchomi Minecraft. Najpierw odczytaj `.ips`, następnie wybierz
kompatybilny runtime / napraw natywną awarię, a dopiero potem
integruj GLFW/OpenGL.


## Potwierdzona przyczyna z raportu iOS .ips — 28 października 2026 (Build 15)

Użytkownik dostarczył pełny raport analityczny `.ips` dla NovaCraft
**1.1.0 (15)** na **iPhone 13 / iOS 27.0.1**, z godziny
**2026-10-28 00:00:37 +0100**. Raportu nie należy zamieszczać
w całości publicznie: zawiera indywidualne identyfikatory urządzenia
i instalacji. Poniżej tylko techniczne, nieidentyfikujące pola.

### Rozstrzygające pola

```text
exception.type = EXC_BAD_ACCESS
exception.subtype = KERN_PROTECTION_FAILURE
exception.signal = SIGKILL
termination.namespace = CODESIGNING
termination.indicator = Invalid Page
ktriageinfo = Failed to fault in a page with execute permissions
faultingThread = 6 ("NovaCraft-Java-21")
esr = (Instruction Abort) Permission fault
faulting region = Untagged, rw-/rwx, SM=COW
stack (top native frames):
  <anonymous executable address>
  InstanceKlass::call_class_initializer(JavaThread*)
  InstanceKlass::initialize_impl(JavaThread*)
  Threads::initialize_java_lang_classes(JavaThread*, JavaThread*)
  Threads::create_vm(JavaVMInitArgs*, bool*)
  JNI_CreateJavaVM
  nova_jni_invoke_main
  NovaGameRunner.run(_:javaMajor:)
```

### Co wiemy na pewno

1. **Jest to wymuszone zakończenie procesu przez ochronę
   wykonywania kodu / code signing w iOS** — nie komunikat o
   braku pamięci, braku licencji Minecrafta ani typowy
   Java-level exception. `SIGKILL` wystąpił w połączeniu
   z `CODESIGNING / Invalid Page`.
2. Program próbował wykonać instrukcję ze strony pamięci
   oznaczonej jako zapisywalna, ale nie wykonywalna
   (`rw-/rwx`). iOS odmówił nadania dostępu do wykonania.
   Raport nie pokazuje legalnie wykonywalnej strony podpisanej
   biblioteki, tylko anonimowy obszar pamięci powiązany
   z natywną inicjalizacją JVM.
3. **HotSpot Server VM** używany przez NovaCraft może
   generować kod maszynowy również z opcją `-Xint`
   (stub-y runtime/interpretera). `-Xint` nie robi z
   Server VM maszyny Zero i nie gwarantuje uniknięcia ochrony
   pamięci wykonywalnej.
4. Minimalny test Java 21 przy `-Xmx256m`, `-Xint`
   oraz wyłączonym compressed oops nie uruchomił żadnej
   klasy użytkownika. Nie ma sensu próbować wciąż
   zmieniać `-Xmx`, pobierać Minecrafta od nowa ani
   przełączać LWJGL, zanim sama JVM przejdzie test.
5. **Nie wolno stwierdzić**, że źródłem jest niepodpisany
   `libjvm.dylib` jako całość: bibliotekę załadowano, a
   odmowa nastąpiła dopiero podczas wykonania strony
   ze zmiennymi prawami dostępu. Samo ponowne podpisanie
   identycznego Server VM może nie pomóc.

### Naprawa docelowa (nie wdrożona)

**A. JVM bez generowania kodu wykonywalnego:** przygotować
spójny, prawidłowo zbudowany dla iPhone ARM64 wariant
**OpenJDK Zero**, najlepiej Java 21 (Minecraft 1.21.5),
z klasami i natywnymi bibliotekami **z tego samego builda**.
Oficjalny `openjdk/mobile` używa dla iOS Zero i produkuje
statyczną bibliotekę `lib/zero/libjvm.a`. Jej prawidłowa
integracja wymaga linkowania w natywnym projekcie iOS,
dołączenia dopasowanego `java.base` i innych modułów
wymaganych przez grę oraz dokładnych testów JNI.
**Nie podmieniaj** istniejącego `lib/server/libjvm.dylib`
plikiem `libjvm.a`; to niezgodne formaty i zwykle
różne wersje Java. Dostępny snapshot OpenJDK Mobile
zawiera nowsze JDK, nie jest zamiennikiem JRE 21.0.8.

**B. Uprawniony tryb debugowania JIT:** ewentualnie
uruchamiać Server VM tylko, jeśli iOS faktycznie zezwala
danej podpisanej aplikacji na wykonywanie dynamicznego
kodu w ramach dostępnej konfiguracji deweloperskiej.
Samo zaznaczenie JIT w ustawieniach launchera czy wpis
uprawnienia w IPA nie nadaje brakujących praw systemowych.
Nie sugerujemy obchodzenia bezpieczeństwa systemu
niezaufanymi binariami.

**Kryterium zaliczenia:** na fizycznym iPhonie 13,
z podpisem, który użytkownik może legalnie uzyskać
bez opłat, samodzielny test drukuje `JVM_ENTRY_REACHED`
i `JVM_PROBE_OK` bez zakończenia procesu. Dopiero wtedy
można testować Minecraft 1.21.5 i pełny renderer
GLFW/OpenGL. Na dziś ten warunek **nie jest spełniony**.

Źródła:
- https://github.com/openjdk/mobile
- https://openjdk-mobile.github.io/ios/helloworld/
- https://support.apple.com/pl-pl/guide/security-pdf/sec15bfe098e/1/web/1
- https://github.com/openjdk-mobile/ios-tools/blob/main/docs/helloworld.md
