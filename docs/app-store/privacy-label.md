# App Privacy — odpowiedzi do App Store Connect

## Tracking

- Dane wykorzystywane do śledzenia użytkownika: `Nie`
- Łączenie danych z reklamami lub brokerami danych: `Nie`
- Reklamy i zewnętrzne SDK reklamowe: `Brak`

## Dane zbierane przez Touge Dash Cloud

Wszystkie poniższe dane służą wyłącznie funkcjonalności aplikacji. Są powiązane z kontem użytkownika, gdy użytkownik dobrowolnie włączy synchronizację online.

| Kategoria App Store | Zakres | Powiązane z użytkownikiem | Cel |
| --- | --- | --- | --- |
| Contact Info — Name | nazwa profilu | Tak | App Functionality |
| Contact Info — Email Address | logowanie, zaproszenia i obsługa konta | Tak | App Functionality |
| Identifiers — User ID | identyfikator konta | Tak | App Functionality |
| Identifiers — Device ID | identyfikator zgodnego interfejsu BLE służący przypisaniu auta | Tak | App Functionality |
| Location — Precise Location | punkty trasy, tylko po włączeniu zapisu GPS | Tak | App Functionality |
| Other Data — Other Data Types | próbki telemetrii silnika, znaczniki czasu i informacje o przejeździe | Tak | App Functionality |

## Dane lokalne

Bez konta historia i ustawienia pozostają wyłącznie na urządzeniu. Dane przetwarzane wyłącznie lokalnie nie są zgłaszane jako „collected” w formularzu App Privacy. Bluetooth służy wyłącznie do komunikacji z wybranym interfejsem; Touge Dash nie zbiera listy urządzeń z otoczenia.

## Uprawnienia systemowe

- Bluetooth: odbieranie telemetrii z kompatybilnego interfejsu ECUMaster.
- Lokalizacja podczas używania: opcjonalny zapis trasy razem z telemetrią.
- Powiadomienia: alerty przekroczenia temperatury oleju lub płynu chłodniczego.
- Live Activities: bieżące parametry na ekranie blokady i obsługiwanych widokach CarPlay.

## Usuwanie konta

Ścieżka w aplikacji: `Historia` → sekcja `Touge Dash Cloud` → menu konta → `Usuń konto`.

Operacja usuwa konto, zewnętrzne tożsamości logowania, pojazdy należące do użytkownika, zsynchronizowane przejazdy i próbki, zaproszenia, powiadomienia oraz aktywne tokeny udostępniania. Lokalna historia na urządzeniu pozostaje dostępna do chwili usunięcia jej przez użytkownika lub odinstalowania aplikacji.

