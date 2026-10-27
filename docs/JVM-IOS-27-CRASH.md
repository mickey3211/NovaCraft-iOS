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
