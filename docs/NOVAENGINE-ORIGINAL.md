# NovaCraft iOS — niezależny silnik NovaEngine

**Autor projektu i marki NovaCraft:** `mickey3211`
**Własny kod aplikacji:** Swift / SwiftUI / C / Metal.
**Licencja kodu stworzonego na potrzeby NovaCraft:** patrz [LICENSE](../LICENSE).

## Co zostało napisane na potrzeby NovaCraft

- `Native/NovaCraft/NovaVoxelEngine.swift`: własna scena voxelowa i renderer
  Metal, bez kopiowania implementacji Amethyst/PojavLauncher.
- `Native/NovaCraft/NovaBlockPreview.swift`: prototyp perspektywy i bufora głębi.
- `Native/NovaCraft/NovaMetalPreview.swift`: test tworzenia pierwszych klatek GPU.
- `Native/NovaCraft/NovaEngineCore.swift`: parser i weryfikator metadanych Minecraft.
- `Native/NovaCraft/NovaGameRunner.swift` oraz `NovaJNIInvoker.c`:
  niezależny adapter dla publicznych interfejsów OpenJDK JNI/JLI.
- `Native/NovaCraft/LauncherView.swift`: oryginalny interfejs NovaCraft.
- `Native/NovaCraft/InputRouter.swift`: lokalne wejścia i kontrolery.

### Co działa w nowym rendererze

Renderer konstruuje deterministyczny teren 24×24 bloków.
Dla każdej kolumny generuje górną powierzchnię oraz wyłącznie odsłonięte
boczne ściany, dzięki czemu nie renderuje wewnętrznych, niewidocznych
ścian. Tworzy bufor wierzchołków, kompiluje własny shader Metal,
ustawia kamerę i projekcję 3D, włącza test głębokości i obsługuje
gesty przeciągania oraz powiększania.

To **realne polecenia renderowania GPU**, a nie animowany obrazek.
Nie jest to jednak zgodny z Minecraft Java silnik OpenGL/GLFW.

### Czego jeszcze nie ma

1. Warstwy emulującej/implementującej pełne API GLFW i OpenGL dla
   Minecraft Java przy użyciu Metal.
2. Kompletnie zintegrowanych zdarzeń klawiatury, dotyku i myszy
   przekazywanych do JVM uruchomionej w tym samym procesie.
3. Sprawdzonego na fizycznym iPhonie 13 uruchomienia Java 21 na iOS 27
   z podpisem aplikacji z darmowego Apple ID.
4. Weryfikacji, że gra uruchamia się i wyświetla świat, a nie jedynie
   wstępnego parsowania/ładowania JVM.
5. Pełnego wsparcia JIT lub alternatywy bez JIT o wystarczającej
   wydajności na aktualnym iOS.

**Nie oznaczaj NovaCraft jako działającego launchera Minecraft Java,
dopóki test gry na urządzeniu nie zostanie wykonany.**

## Kod Amethyst a NovaCraft

Wcześniej do tego repozytorium zaimportowano źródła Amethyst na dwie
osobne gałęzie. Na wyraźne życzenie właściciela zostały one usunięte.
Nigdy nie były częścią oryginalnego drzewa źródłowego `main`.
Usunięcie gałęzi nie gwarantuje usunięcia historycznych archiwów,
logów GitHub Actions, kopii osób trzecich ani wcześniej
opublikowanego, pochodnego IPA GPL.

Kod `NovaVoxelEngine.swift` został napisany niezależnie, a nie
skopiowany z repozytorium Amethyst. Inspiracją są ogólne idee silników
gier: renderowanie 3D, widoczność powierzchni i sterowanie dotykiem.
Ogólne idee nie są tożsame z kopiowaniem kodu źródłowego.

## Zależności zewnętrzne

**Silnik NovaEngine Metal należy rozróżnić od niezależnych bibliotek
OpenJDK oraz LWJGL.** Aplikacja wciąż może zawierać te komponenty do
eksperymentalnego uruchomienia Java; obowiązują je prawa ich autorów,
a nie wyłącznie licencja NovaCraft. Minecraft i jego pliki również
nie są własnością twórcy NovaCraft.

Informacje o licencjach zewnętrznych: [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Informacja dla użytkowników

NovaCraft jest niezależnym, eksperymentalnym projektem i nie jest
oficjalnym launcherem Mojang/Microsoft. Należy przestrzegać zasad
korzystania z Minecrafta oraz obowiązujących licencji bibliotek.
