# Touge Dash EMU Simulator

Natywna aplikacja macOS udająca `EMULOGGER` przez Bluetooth Low Energy. Służy
do testowania Touge Dash bez uruchamiania samochodu.

Symulator reklamuje usługę GATT `FFE0`, charakterystykę `FFE1` z odczytem i
notyfikacjami oraz wysyła ramki w formacie używanym przez aplikację mobilną.
Przyjmuje wyłącznie poprawne ramki testowe `BT Switch` / `BT Rotary` i zwraca ich
stan w kanałach loopback 254–252. Nie komunikuje się z prawdziwym ECU.

## Użycie

1. Uruchom `Touge Dash EMU Simulator.app` na Macu i zaakceptuj dostęp do Bluetooth.
2. Zostaw włączony logger. Status zmieni się na „iPhone połączony”, gdy telefon
   zasubskrybuje `FFE1`.
3. W Touge Dash włącz nagrywanie przejazdu, jeśli chcesz sprawdzić kamerę.
4. Wybierz scenariusz albo ustaw parametry ręcznie.
5. `Zatrzymaj logger` kończy transmisję. `Rozłącz i połącz ponownie` sprawdza
   automatyczny reconnect.

Scenariusze alarmowe celowo przekraczają domyślne progi i mogą generować
powiadomienia oraz raporty incydentów. Przejazdy symulatora pozostają lokalne i
nie są przypisywane do samochodu w Touge Dash Cloud.

## Build

```bash
xcodegen generate --spec tools/EMULoggerSimulator/project.yml
xcodebuild \
  -project tools/EMULoggerSimulator/EMULoggerSimulator.xcodeproj \
  -scheme EMULoggerSimulator \
  -destination 'platform=macOS' \
  test
```
