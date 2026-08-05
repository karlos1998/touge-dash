# Touge Dash EMU Simulator

Natywna aplikacja macOS udająca `EMULOGGER` przez Bluetooth Low Energy. Służy
do testowania Touge Dash bez uruchamiania samochodu.

Symulator reklamuje usługę GATT `FFE0`, charakterystykę `FFE1` z odczytem i
notyfikacjami oraz wysyła ramki w formacie używanym przez aplikację mobilną.
Przyjmuje wyłącznie poprawne ramki testowe `BT Switch` / `BT Rotary` i zwraca ich
stan w kanałach loopback 254–252. Panel `BT SWITCH / ROTARY` pokazuje zmiany
wysłane z telefonu i pozwala ręcznie zasymulować zmianę po stronie loggera. Nie
komunikuje się z prawdziwym ECU.

To jest urządzenie **Bluetooth Low Energy GATT**, a nie klasyczny port szeregowy
Bluetooth SPP/RFCOMM. Reklamuje dokładną nazwę `EMULOGGER`, ponieważ bieżący
eDash filtruje znalezione urządzenia po nazwie jeszcze przed połączeniem.
Mac ma jednak własny identyfikator Bluetooth, dlatego Touge Dash widzi symulator
jako osobny interfejs i może przypisać mu osobne auto testowe.

## Użycie

1. Uruchom `Touge Dash EMU Simulator.app` na Macu i zaakceptuj dostęp do Bluetooth.
2. Zostaw włączony logger. Status zmieni się na „Telefon połączony”, gdy telefon
   zasubskrybuje `FFE1`.
3. W Touge Dash włącz nagrywanie przejazdu, jeśli chcesz sprawdzić kamerę.
4. Wybierz scenariusz albo ustaw parametry ręcznie.
5. `Zatrzymaj logger` kończy transmisję. `Rozłącz i połącz ponownie` sprawdza
   automatyczny reconnect.

Scenariusze alarmowe celowo przekraczają domyślne progi i mogą generować
powiadomienia oraz raporty incydentów. Symulator należy nazwać w Touge Dash jako
osobne auto testowe; jego przejazdy mogą wtedy przechodzić zwykłą synchronizację.

## Oryginalny eDash

Bieżący eDash na Androidzie wykrywa nazwę `EMULOGGER`, paruje się z Makiem i
łączy w trybie BLE. Nie oznacza to jednak pełnej zgodności strumienia. macOS
udostępnia w swojej współdzielonej bazie GATT również własne usługi systemowe,
a eDash wybiera pierwszą znalezioną charakterystykę z notyfikacjami zamiast
ograniczyć wyszukiwanie do `FFE0/FFE1`. W efekcie może wyświetlić „Connected via
BLE”, ale nie zasubskrybować telemetrii symulatora.

CoreBluetooth pozwala aplikacji usunąć wyłącznie usługi opublikowane przez tę
aplikację, więc symulator nie może bezpiecznie ukryć systemowych usług macOS.
Do testów Touge Dash używamy `FFE0/FFE1` bez tego problemu. Do pełnego testu
oryginalnego eDash potrzebny byłby osobny adapter/peryferium (np. ESP32), którego
baza GATT zawiera tylko profil loggera. Klasyczny SPP/RFCOMM jest osobnym
transportem; sam ekran parowania i kod PIN nie dowodzą, że połączenie działa po
SPP.

## Build

```bash
xcodegen generate --spec tools/EMULoggerSimulator/project.yml
xcodebuild \
  -project tools/EMULoggerSimulator/EMULoggerSimulator.xcodeproj \
  -scheme EMULoggerSimulator \
  -destination 'platform=macOS' \
  test
```
