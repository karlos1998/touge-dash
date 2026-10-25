# Touge Dash Android 1.9.0

Android otrzymuje rozbudowany edytor i eksport filmów z telemetrią oraz poprawki
dashboardu zgodne z dopracowaną wersją iOS.

## Nowości i poprawki

- 16 szablonów HUD, widget daty i czasu, przesuwanie i skalowanie widgetów
  gestami oraz zapisywanie własnego układu osobno dla każdego filmu.
- Wspólny wygląd podglądu i gotowego filmu, dokładniejsza synchronizacja
  telemetrii, przycinanie, szybki eksport do 1080p, oryginalna rozdzielczość
  oraz zapis filmu bez HUD-u. Eksport zachowuje dźwięk i działa w tle.
- Bezpośredni import nagrań z kamer 70mai przez Wi-Fi, dopasowanie czasu kamery
  i łączenie klipów z zachowaniem przerw w nagraniu.
- Nagrywanie przejazdu w tle oraz automatyczne dzielenie przejazdów.
- Ulepszona historia, odtwarzanie nagrań z kursorem telemetrii, mapa przejazdu,
  lista incydentów i wykres ciśnienia paliwa.
- Dopracowane karty BT Switch 1–8 i BT Rotary 1–8: potwierdzenie zmian przez
  EMU, zachowanie pozostałych kanałów, obsługa timeoutów i ponownego połączenia.
  Opóźniony błąd Bluetooth nie anuluje już późniejszego polecenia.
- Czytelniejsze switche na wąskich kartach, przywracanie wybranego dashboardu,
  poprawki polskiego interfejsu i widoku poziomego.

## Instalacja

Pobierz `touge-dash-android.apk` z tego wydania lub przez przycisk pobierania
na stronie Touge Dash. Wymagany jest Android 8 lub nowszy. Wydanie korzysta
z dotychczasowego identyfikatora aplikacji i klucza podpisującego, dzięki czemu
aktualizuje istniejącą instalację i zachowuje jej dane.

## Weryfikacja

80 testów jednostkowych i 21 testów urządzeniowych przeszło na Androidzie;
referencyjna seria iOS obejmuje 116 testów, w tym 41 testów EMU. Testy importu
kamery i sterowania ECU korzystają z symulowanych urządzeń. Fizyczny EDL-1
i poszczególne wersje firmware kamer wymagają osobnej weryfikacji sprzętowej.
