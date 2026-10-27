# NovaCraft iOS — darmowa kompilacja IPA przez Codemagic

**Cel:** zbudować `NovaCraft-Java21-LWJGL-UNSIGNED.ipa` bez korzystania z płatnych GitHub Actions i bez Maca. Repozytorium jest prywatne; nie publikuj kodu tylko po to, by otrzymać darmowe minuty.

## Uruchomienie (konto indywidualne)

1. Wejdź na https://codemagic.io/start/ i załóż konto lub zaloguj się przez GitHub.
2. Upewnij się, że wybrane jest konto **Personal**, a nie **Team**. 500 bezpłatnych minut macOS M2 co miesiąc przysługuje kontom indywidualnym. Nie aktywuj płatnego rozliczania, jeśli chcesz uniknąć opłat.
3. W panelu kliknij **Add application**, wybierz **GitHub**, autoryzuj integrację Codemagic CI/CD i nadaj jej dostęp do **tylko** repozytorium `mickey3211/NovaCraft-iOS`.
4. Wybierz repozytorium, typ projektu **Native iOS** i plik konfiguracyjny **codemagic.yaml** (jest już zapisany w głównym katalogu repozytorium).
5. Wybierz gałąź **main** i workflow **NovaCraft iOS - bezplatny IPA (Java 21 + LWJGL)**, a następnie **Start new build**.

## Co zrobi kompilacja?

- Użyje **macOS M2 i Xcode 16.4** (środowiska dostępne w Codemagic).
- **Najpierw** skompiluje aplikację Swift/Objective-C z ustawieniem `CODE_SIGNING_ALLOWED=NO`. Błędy Swift wyjdą przed długim budowaniem LWJGL.
- Zbuduje kod LWJGL dla iOS z przypiętej rewizji `39272d4d0ca119379024e3ca7207699fd3fce237`.
- Pobierze zweryfikowany SHA-256 iOS Java 21 z istniejącego skryptu NovaCraft.
- Umieści Java 21 i LWJGL w pakiecie, wykona audyt arm64/iOS i wygeneruje niepodpisane IPA.

## Skąd pobrać plik?

Po udanej kompilacji otwórz szczegóły uruchomienia i zakładkę **Artifacts**. Pobierz:

`NovaCraft-Java21-LWJGL-UNSIGNED.ipa`

W razie błędu otwórz szczegóły kroku kompilacji. Jeśli powstały logi, będą też w artefaktach jako `dist/build-logs/*.log`. Prześlij tylko komunikaty błędów; sprawdź, czy logi nie zawierają prywatnych danych.

## Instalacja na iPhonie przez iPASide

Ten IPA jest **niepodpisany** — nie można go zainstalować wprost. Po pobraniu zaimportuj IPA do iPASide i podpisz swoim Apple ID. Narzędzie musi podpisywać również wszystkie zawarte biblioteki Mach-O, w tym `Frameworks/NovaJava21.framework/lib/**/*.dylib`, framework Javy i `Frameworks/liblwjgl*.dylib`. Jeśli iPASide nie obsługuje pełnego podpisywania zagnieżdżonych bibliotek, sam podpis aplikacji może nie wystarczyć.

**Ograniczenia:** ukończona kompilacja i poprawne podpisanie nie gwarantują grywalnego Minecraft Java na iOS. Nadal mogą być potrzebne JIT/zgodny tryb interpretera, pełne połączenie renderera LWJGL z iOS oraz diagnostyka uruchamiania JVM. Konto offline nie omija licencji Minecraft na serwerach wymagających konta premium.

## Przydatne linki

- Panel: https://codemagic.io/
- Oficjalne darmowe minuty: https://docs.codemagic.io/billing/pricing/
- Dodawanie prywatnych repozytoriów GitHub: https://docs.codemagic.io/partials/github/
- Konfiguracja `codemagic.yaml`: https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/

**Uwaga:** jedno uruchomienie ma maksymalnie 120 minut; limit 500 minut odnawia się miesięcznie. Brak aktywowanego billing oznacza, że po wyczerpaniu darmowych minut trzeba zaczekać na odnowienie limitu.
