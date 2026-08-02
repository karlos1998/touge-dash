# Touge Dash

Dashboard do podglądu danych z ECUMaster EMU Black. Powstał po to, żeby nie
wozić telefonu z eDash przyklejonego do szyby i mieć najważniejsze parametry
silnika również na ekranie CarPlay.

Repo zawiera natywną aplikację na iPhone'a oraz prosty dashboard WWW dla
macOS/Raspberry Pi. Kod protokołu jest niezależną implementacją — projekt nie
zawiera kodu ani zasobów z oficjalnego eDash.

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="390" alt="Touge Dash na iPhone" />
  <img src="docs/screenshots/live-activity.png" width="390" alt="Touge Dash Live Activity" />
</p>

<p align="center">
  <img src="docs/screenshots/carplay.png" width="350" alt="Touge Dash w CarPlay Dashboard" />
</p>

## Co działa

- automatyczne wykrywanie i łączenie z interfejsami ECUMaster BLE,
- odczyt ramek z `EMULOGGER` przez GATT `FFE0` / `FFE1`,
- RPM, boost/MAP, TPS, AFR/lambda, temperatury, ciśnienia i napięcie,
- dashboard SwiftUI w pionie i poziomie,
- Live Activity uruchamiana automatycznie razem z aplikacją,
- mały widok Live Activity przygotowany pod CarPlay,
- widgety iOS,
- diagnostyka pakietów BLE bezpośrednio w aplikacji,
- dashboard WWW dla starszych interfejsów Bluetooth Classic/SPP.

## Sprawdzony zestaw

Aktualna wersja była testowana na:

- iPhone 14 Pro z iOS 26.5.2,
- ECUMaster EMU Black,
- EDL-1 widocznym w BLE jako `EMULOGGER`.

Połączenie jest nawiązywane automatycznie. Aplikacja zapamiętuje ostatni
interfejs, więc przy kolejnych uruchomieniach nie trzeba otwierać listy
Bluetooth.

## iPhone

Wymagany jest Xcode 26 oraz iPhone z iOS 26. Projekt Xcode jest dołączony do
repozytorium:

```bash
open ios/TougeDash.xcodeproj
```

Przed pierwszym uruchomieniem wybierz swój Development Team dla targetów
`TougeDash` i `TougeDashWidgets`. Jeżeli domyślne identyfikatory są zajęte na
Twoim koncie Apple Developer, zmień bundle ID oraz App Group w
[`ios/project.yml`](ios/project.yml).

Dokładniejsze informacje o podpisywaniu, BLE i diagnostyce są w
[`ios/README.md`](ios/README.md).

### CarPlay

Touge Dash nie jest pełną aplikacją CarPlay i nie pojawia się na liście ikon.
Używa Live Activity w rozmiarze `ActivityFamily.small`. Po podłączeniu telefonu
aktywność pojawia się w CarPlay Dashboard albo jako powiadomienie. Pokazuje
ciśnienie oleju, boost, AFR i temperaturę oleju.

## Dashboard WWW na macOS

Wersja desktopowa korzysta z Bluetooth Classic/RFCOMM. Przydaje się do
starszych modułów `EMUCANBT_SPP`, których CoreBluetooth na iOS nie obsługuje.

```bash
chmod +x scripts/install-macos.sh
./scripts/install-macos.sh
.venv/bin/emu-dash --web --port 8090
```

Strona jest domyślnie dostępna tylko lokalnie pod `127.0.0.1`. Bez samochodu
można uruchomić generator danych:

```bash
.venv/bin/emu-dash --web --demo --port 8090
```

Surowy strumień da się nagrać i później odtworzyć:

```bash
.venv/bin/emu-dash --web --mac AA:BB:CC:DD:EE:FF --log-raw logs/run.bin
.venv/bin/emu-dash --web --replay logs/run.bin
```

## Protokół

Strumień ECUMaster składa się z pięciobajtowych ramek:

```text
[channel] [0xA3] [value high] [value low] [checksum]
```

`checksum` to najmłodszy bajt sumy pierwszych czterech bajtów. Parser działa
strumieniowo, radzi sobie z ramkami rozdzielonymi pomiędzy notyfikacje BLE i
wraca do synchronizacji po uszkodzonych danych.

## Układ repozytorium

```text
ios/                 aplikacja SwiftUI, widgety i Live Activity
src/emu_dash/        parser i dashboard Python/WWW
tests/               testy protokołu i serwera
scripts/             instalacja na macOS i Raspberry Pi
deploy/              przykładowe pliki usługi systemd
```

## Testy

Python:

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

iOS:

```bash
xcodebuild \
  -project ios/TougeDash.xcodeproj \
  -scheme TougeDash \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## Ważne

To dodatkowy wyświetlacz, a nie homologowany przyrząd. Przed użyciem w czasie
jazdy porównaj wskazania z ECUMaster Client. Projekt nie jest powiązany ani
autoryzowany przez ECUMaster.

## Licencja

MIT — szczegóły w pliku [`LICENSE`](LICENSE).
