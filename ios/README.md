# Touge Dash for iPhone and Apple Watch

Natywna aplikacja SwiftUI do podglądu telemetrii ECUMaster EMU Black. Projekt zawiera:

- dashboard pionowy i poziomy,
- automatyczne skanowanie oraz ponowne łączenie BLE,
- dekoder strumienia ECUMaster z resynchronizacją i kontrolą checksum,
- automatyczne łączenie z ostatnim interfejsem ECUMaster,
- lokalną historię przejazdów, interaktywne wykresy i opcjonalny zapis GPS,
- automatyczne raporty incydentów z buforem 30 s przed i 60 s po zdarzeniu,
- notatki przypięte do dokładnego momentu telemetrii,
- konfigurowalne reguły per auto z synchronizacją owner/mechanic i obsługą konfliktów,
- opcjonalne konto i kolejkę synchronizacji Touge Dash Cloud,
- mały i średni widget,
- Live Activity ze specjalnym małym układem dla CarPlay,
- aplikację Apple Watch z telemetrią przesyłaną przez WatchConnectivity,
- współdzielone dane przez App Group,
- diagnostykę ramek i testy jednostkowe protokołu.

## Wymagania

- Xcode 26 lub nowszy,
- iPhone z iOS 26 do prezentacji widgetów i Live Activities w CarPlay,
- opcjonalnie Apple Watch z watchOS 26,
- bezpłatne albo płatne konto Apple Developer skonfigurowane w Xcode,
- interfejs ECUMaster obsługujący BLE.

Domyślna konfiguracja używa bundle ID `it.letscode.touge-dash` oraz App Group
`group.it.letscode.touge-dash`. Przed podpisaniem forka zmień je na własne,
jeśli kolidują z identyfikatorami na Twoim koncie Apple Developer.

Nazwę produktu i bundle ID można zmienić w `project.yml` przed utworzeniem rekordu w App Store Connect.

## Zgodność Bluetooth

| Interfejs | Bezpośrednio z iPhone | Uwagi |
|---|---:|---|
| BT CAN z BLE | Tak | Urządzenia produkowane w 2026 mają gwarantowane BLE; starsze trzeba sprawdzić. |
| Nowszy EDL-1 z BLE | Tak | Wymagane aktualne firmware odpowiednie dla wersji EMU. |
| Stary moduł Bluetooth SPP/Classic | Nie | iOS nie udostępnia aplikacjom zwykłego portu SPP. Potrzebny jest BT CAN BLE albo kompatybilny EDL-1. |

Touge Dash rozpoczyna skanowanie od razu po uruchomieniu, odrzuca wszystkie urządzenia niezwiązane z ECUMaster i automatycznie łączy pierwszy pasujący interfejs. Po pierwszym udanym połączeniu identyfikator urządzenia jest zapamiętywany, więc kolejne uruchomienia nie wymagają otwierania listy. Nie należy parować BLE ręcznie w systemowych Ustawieniach iPhone'a.

## Ustawienie EMU Black dla BT CAN

W EMU Black Client otwórz `CAN, Serial → CAN setup`, następnie:

1. ustaw CAN na `500 kbps`,
2. włącz `Send data to BTCAN module`,
3. zapisz ustawienia na stałe klawiszem F2.

Przed jazdą porównaj RPM, MAP, temperatury i ciśnienia z EMU Black Client. Aplikacja nie jest homologowanym przyrządem bezpieczeństwa.

## Historia i zapis trasy

Odebrane próbki są archiwizowane lokalnie w SwiftData z częstotliwością 10 Hz.
Przerwa dłuższa niż 90 sekund zamyka bieżącą sesję i rozpoczyna następną.
Ekran szczegółów pokazuje zsynchronizowane wykresy temperatur, ciśnień,
prędkości i RPM oraz pełny zestaw wartości dla wskazanego momentu. Na iPadzie
wykresy automatycznie przechodzą w układ dwóch kolumn.

Zapis pozycji jest opcjonalny i domyślnie wyłączony. Po włączeniu przełącznika
`Zapis trasy` aplikacja prosi o zgodę na lokalizację i może zapisywać ją razem
z telemetrią również po zablokowaniu telefonu. Trasa jest rysowana na mapie,
a kursor wykresu przesuwa odpowiadający mu punkt na trasie.

Dane zawsze trafiają najpierw do lokalnego SwiftData. Konto jest opcjonalne.
Po zalogowaniu sesje oczekujące są wysyłane partiami, a po utracie internetu
zapis działa dalej. UUID urządzenia Bluetooth rozdziela archiwum różnych aut.
Nowy EMULOGGER wymaga jednorazowego nadania nazwy.

## Incydenty i notatki

Niezależny bufor incydentów pobiera do 25 próbek/s. Reguły mają krótkie czasy
potwierdzenia, dzięki czemu pojedynczy błędny pakiet nie tworzy raportu. Po
wykryciu niskiego ciśnienia oleju lub paliwa, ubogiej mieszanki pod boostem,
overboostu, temperatury płynu/oleju albo spadku napięcia aplikacja zachowuje
30 sekund wcześniejszych danych i kolejne 60 sekund. Jeśli połączenie zostanie
przerwane wcześniej, zapisuje dostępny fragment zamiast go odrzucać.

Zakładka `Alerty` pozwala ustawić te progi osobno dla każdego auta, wyłączyć
nieużywany kanał i dobrać czas potwierdzenia warunku. Ustawienia działają
lokalnie bez internetu, a po zalogowaniu są wersjonowane i synchronizowane z
panelem WWW. Właściciel oraz mechanik mogą je edytować; konflikt dwóch zmian
wymaga świadomego wyboru wersji zamiast cichego nadpisania. Te same progi sterują
raportami, kolorami dashboardu, Live Activity/CarPlay, Apple Watchem i
powiadomieniami temperaturowymi.

Każdy raport ma zsynchronizowane wykresy, warunki pracy, mapę i notatki. Notatkę
można dodać również do dowolnego momentu zwykłego przejazdu. Przejazdy, raporty
i notatki trafiają do kolejki offline i są wysyłane w tej kolejności po
odzyskaniu internetu.

## Gwarancja trybu tylko do odczytu

Warstwa CoreBluetooth dopuszcza wyłącznie `setNotifyValue` i `readValue`.
Charakterystyki oferujące zapis są jawnie ignorowane, a test jednostkowy blokuje
przypadkowe rozszerzenie tej polityki. Touge Dash nie wysyła ustawień ani poleceń
do EMU/EMULOGGERA.

## Synchronizacja online

Zakładka `Historia` zawiera kartę Touge Dash Cloud. Dostępne są konto
e-mail/hasło, natywne Sign in with Apple oraz logowanie Google/Facebook przez
panel WWW. Wariant webowy przekazuje aplikacji jednorazowy kod ważny trzy
minuty; tokeny nie są umieszczane w adresie callbacku. Sesja i refresh token są
przechowywane w Keychain.

Domyślna konfiguracja lokalna:

```text
API: http://localhost:8181
Web: http://localhost:4200
```

Na fizycznym iPhonie `localhost` oznacza telefon. W rozwijanej sekcji `Adres
serwera` podaj nazwę lub adres Maca widoczny w tej samej sieci, np.
`http://macbook.local:8181` i `http://macbook.local:4200`. W produkcji oba
adresy będą HTTPS.

## Uruchomienie

Projekt Xcode jest już wygenerowany i można otworzyć go bez dodatkowych kroków:

```bash
open TougeDash.xcodeproj
```

Jeśli zmienisz `project.yml`, odtwórz projekt:

```bash
brew install xcodegen
xcodegen generate
```

W Xcode wybierz własny Development Team dla targetów `TougeDash`,
`TougeDashWidgets` i `TougeDashWatch`, następnie wybierz iPhone i naciśnij Run.
Przy pierwszym podpisaniu Apple może poprosić o utworzenie App Group i profilu
dla rozszerzenia widgetów.

## CarPlay

Touge Dash nie udaje pełnej aplikacji CarPlay i nie wymaga entitlementu z kategorii nawigacja/audio. Korzysta z oficjalnych powierzchni systemowych:

- `Touge Dash` jako widget `systemSmall`, który można dodać na ekranie widgetów CarPlay,
- Live Activity uruchamiana automatycznie razem z aplikacją; system pokazuje ją w CarPlay Dashboard lub jako powiadomienie. Przycisk `Stop card` pozwala ją ręcznie wyłączyć.

Live Activity ma układ `ActivityFamily.small` z ciśnieniem i temperaturą oleju,
boostem, AFR oraz temperaturą płynu chłodniczego. Na iOS 26 aktywność jest
uruchamiana przed skanowaniem BLE, dzięki czemu CoreBluetooth zachowuje swoje
uprawnienia również po zablokowaniu telefonu. Elementy na CarPlay są tylko
informacyjne — system nie uruchomi aplikacji po stuknięciu karty, ponieważ
projekt nie deklaruje pełnej aplikacji CarPlay.

## Apple Watch

Target `TougeDashWatch` jest osadzony w aplikacji iPhone. Po instalacji pojawi
się na sparowanym zegarku automatycznie albo będzie dostępny w aplikacji Watch
na iPhonie. Telemetria — wraz z temperaturą płynu chłodniczego — jest przesyłana
na żywo, gdy aplikacja zegarkowa jest otwarta; `applicationContext` zapewnia
również ostatnią znaną próbkę po chwilowej utracie łączności. Przejście w stan
krytyczny wywołuje haptyczne ostrzeżenie.

## Alerty temperatury

Po przekroczeniu progów temperatury skonfigurowanych dla danego auta aplikacja:

- wysyła na iPhonie pilne powiadomienie z dźwiękiem,
- uruchamia haptyczne ostrzeżenie w otwartej aplikacji Apple Watch,
- zmienia kartę Live Activity i CarPlay na czerwony stan `TEMP ALERT`.

Alert jest zatrzaskiwany i uzbraja się ponownie dopiero po spadku temperatury
o co najmniej 5°C poniżej ustawionego limitu, więc wahania pomiaru nie powodują
serii powiadomień. iOS może również przekazać powiadomienie na Apple Watch zgodnie z
ustawieniami mirroringu. Powiadomienie używa poziomu `timeSensitive`; tryb
`critical`, omijający wyciszenie i Focus, wymaga osobnego entitlementu Apple.

## Diagnostyka pierwszego połączenia

Po wybraniu `Bluetooth` ekran połączenia pokazuje:

- wykryte usługi i charakterystyki GATT,
- liczbę odebranych pakietów i bajtów,
- pierwsze pakiety w hex,
- liczbę poprawnych ramek, błędów checksum i pominiętych bajtów.

Jeśli licznik pakietów rośnie, ale `Valid frames` pozostaje równy zero, prześlij zrzut sekcji `Protocol` i `Diagnostics`. Oznacza to inny wariant opakowania danych BLE; zebrane bajty wystarczą do dopasowania dekodera bez ponownego projektowania aplikacji.

## Testy z terminala

```bash
xcodebuild \
  -project TougeDash.xcodeproj \
  -scheme TougeDash \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Testy obejmują fragmentację notyfikacji BLE, szum, złą sumę kontrolną,
resynchronizację, skalowanie kanałów, wartości ze znakiem, podział sesji,
częstotliwość zapisu, politykę Bluetooth tylko do odczytu oraz wszystkie reguły
incydentów z buforem przed i po zdarzeniu.
