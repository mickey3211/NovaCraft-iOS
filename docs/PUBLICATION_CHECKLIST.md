# Lista kontroli przed zmianą repozytorium NovaCraft-iOS na Public

**Nie upubliczniaj kodu tylko po to, by można było pobrać IPA.** Jeśli
najważniejsze jest niedopuszczenie do pobrania Twoich źródeł, pozostaw
oryginalne repozytorium prywatne i utwórz osobne publiczne repozytorium
wydawnicze zawierające tylko gotowe pliki, instrukcje i niezbędne licencje.

## Prawa do kodu

- [x] Dołączono `LICENSE`: wszelkie prawa zastrzeżone do oryginalnego kodu.
- [x] README nie opisuje już NovaCraft jako projektu na licencji MIT.
- [x] Dodano `THIRD_PARTY_NOTICES.md` z informacją o bibliotekach zewnętrznych.
- [ ] Sprawdź, czy wszystkie oryginalne elementy są faktycznie Twoją własnością lub masz prawo je publikować.
- [ ] Sprawdź wcześniejsze upublicznienia / umowy / zgody współautorów. Nowy plik LICENSE nie cofa wcześniej ważnie udzielonych praw.
- [ ] Przed publikacją IPA sprawdź i dołącz wymagane licencje i powiadomienia OpenJDK, LWJGL i wszystkich bibliotek objętych pakietem. Możliwe są obowiązki udostępnienia kodu odpowiednich komponentów.

## Bezpieczeństwo publicznego repozytorium

- [ ] Sprawdź **całą historię commitów**, również stare, usunięte pliki. GitHub zachowuje historię po zmianie widoczności.
- [ ] Sprawdź wcześniejsze **logi GitHub Actions**, artefakty, pliki issue i PR: po zmianie na Public staną się widoczne.
- [ ] Zweryfikuj, że nigdy nie zapisano rzeczywistych haseł, prywatnych kluczy, tokenów dostępu, certyfikatów i plików `.p12` / `.mobileprovision`.
- [ ] Jeśli kiedykolwiek sekret był zapisany, **unieważnij i wymień** go przed publikacją. Samo usunięcie z ostatniego commita nie usuwa sekretu z historii.
- [ ] Sprawdź dane osobowe, prywatne adresy serwerów, raporty awarii i ścieżki katalogów użytkowników.
- [ ] Jeśli używasz repozytorium do CI: upewnij się, że nie dołączasz plików podpisu, profilów Apple ani prawdziwych tokenów do artefaktów.

Dodany `.gitignore` ogranicza ryzyko przypadkowego dodania takich plików
w przyszłości, ale **nie usuwa tego, co już jest w historii**.

## Skutki ustawienia Public

GitHub publicznie udostępnia cały kod i historię, a inni mogą oglądać,
forkować i pobierać pliki repozytorium. LICENSE określa prawa do ponownego
wykorzystania Twojego oryginalnego kodu, lecz **nie blokuje kopiowania
technicznie**. Nie da się niezawodnie zapobiec kradzieży źródeł
z publicznego repozytorium.

**Zalecany wybór przy potrzebie maksymalnej ochrony:**
utrzymaj `mickey3211/NovaCraft-iOS` jako prywatne. Udostępnij publicznie
osobne repozytorium lub stronę z wydaniami IPA, opisem i wymaganymi
informacjami o licencjach, **bez źródeł NovaCraft**. Codemagic potrafi
pracować z prywatnym repozytorium GitHub i nie wymaga jego upublicznienia.

## Ręczna zmiana widoczności (tylko po zaakceptowaniu ryzyka)

GitHub → repozytorium NovaCraft-iOS → **Settings → General →
Danger Zone → Change repository visibility → Make public**.

Oficjalne wyjaśnienie konsekwencji:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility

## Ochrona praw, gdy ktoś naruszy zakaz

Zachowaj oryginalną historię tworzenia projektu, pliki źródłowe,
dokumentację i datowane commity jako materiał dowodowy. Zgłoszenia
naruszeń praw autorskich kieruj do hostingu zgodnie z jego procedurami.
Przed działaniem prawnym warto skonsultować zakres swoich praw z prawnikiem.
