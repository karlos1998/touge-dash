# Touge Dash for iPhone and Apple Watch

Natywna aplikacja SwiftUI do podglądu telemetrii ECUMaster EMU Black. Projekt zawiera:

- dashboard pionowy i poziomy,
- automatyczne skanowanie oraz ponowne łączenie BLE,
- dekoder strumienia ECUMaster z resynchronizacją i kontrolą checksum,
- automatyczne łączenie z ostatnim interfejsem ECUMaster,
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
| Stary moduł Bluetooth SPP/Classic | Nie | iOS nie udostępnia aplikacjom zwykłego portu SPP. Potrzebny BT CAN BLE, kompatybilny EDL-1 albo późniejszy most Raspberry Pi. |

Touge Dash rozpoczyna skanowanie od razu po uruchomieniu, odrzuca wszystkie urządzenia niezwiązane z ECUMaster i automatycznie łączy pierwszy pasujący interfejs. Po pierwszym udanym połączeniu identyfikator urządzenia jest zapamiętywany, więc kolejne uruchomienia nie wymagają otwierania listy. Nie należy parować BLE ręcznie w systemowych Ustawieniach iPhone'a.

## Ustawienie EMU Black dla BT CAN

W EMU Black Client otwórz `CAN, Serial → CAN setup`, następnie:

1. ustaw CAN na `500 kbps`,
2. włącz `Send data to BTCAN module`,
3. zapisz ustawienia na stałe klawiszem F2.

Przed jazdą porównaj RPM, MAP, temperatury i ciśnienia z EMU Black Client. Aplikacja nie jest homologowanym przyrządem bezpieczeństwa.

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

Testy obejmują fragmentację notyfikacji BLE, szum, złą sumę kontrolną, resynchronizację, skalowanie kanałów oraz wartości ze znakiem.
