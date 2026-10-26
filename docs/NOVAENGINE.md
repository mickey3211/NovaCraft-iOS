# NovaEngine 0.1 — zakres i ograniczenia

NovaEngine jest własną warstwą integracyjną projektu NovaCraft. Nie używa kodu
PojavLauncher ani Amethyst. Nie jest jeszcze samodzielną JVM ani rendererem.

## Zaimplementowane

- Odczyt oficjalnego `version.json` pobranego przez `MinecraftInstaller`.
- Rozpoznanie `mainClass`, wymaganego numeru Java (`javaVersion.majorVersion`, jeśli istnieje)
  i nowego/starego formatu argumentów.
- Zebranie istniejących plików JAR do classpath i raport brakujących bibliotek.
- Kontrola obecności indeksu zasobów, sprawdzenie identyfikatora wersji i ścieżek bibliotek.
- Diagnostyka w aplikacji: **Sprawdź zgodność NovaEngine**.
- Bezpieczne odmówienie uruchomienia, jeśli brakuje JVM/mostu graficznego.
- Test parsera: `swiftc Native/NovaCraft/NovaEngineCore.swift tests/NovaEngineSmoke.swift -o /tmp/novaengine-smoke && /tmp/novaengine-smoke`.

## Niezrobione

- Osadzenie i uruchomienie zgodnej JVM na iOS, w tym ograniczenia JIT.
- Rzeczywiste budowanie argumentów startowych (w tym reguł i zmiennych).
- Renderer LWJGL/OpenGL na Metal, natywne biblioteki i okno gry.
- Obsługa wszystkich historycznych formatów manifestów i reguł zależności.
- Uruchomienie gry, integracja sterowania i połączenia z serwerami.
- Test na fizycznym iPhonie i potwierdzenie działania na iOS 27.

## Docelowa zgodność

Wersje Minecraft wymagają różnych środowisk Java, bibliotek i argumentów.
Obsługa wszystkich wersji to **cel projektu**, nie obecna funkcja. Gdy manifest
nie określa `javaVersion`, NovaEngine zgłasza brak informacji zamiast zgadywać.
Dalsze etapy wymagają rzeczywistej JVM, grafiki i testów per wersja.
