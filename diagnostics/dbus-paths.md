# D-Bus cesty (k ověření)

Cesty použité v dokumentaci jsou typické pro Victron battery service, ale **nejsou ověřené na konkrétním systému** — verze n-BMS integrace do Venus OS se může lišit. Ověřit přes `dbus-spy` na Cerbu před použitím v jakékoliv automatizaci.

| Cesta (typicky) | Význam |
|---|---|
| `com.victronenergy.battery.<id>/System/MaxCellVoltage` | napětí nejvyššího článku/skupiny |
| `com.victronenergy.battery.<id>/System/MinCellVoltage` | napětí nejnižšího článku/skupiny |
| `com.victronenergy.battery.<id>/System/MaxVoltageCellId` | který článek/skupina je aktuálně nejvyšší |
| `com.victronenergy.battery.<id>/System/MinVoltageCellId` | který článek/skupina je aktuálně nejnižší |
| `com.victronenergy.battery.<id>/Info/ChargeCurrentLimit` | CCL — aktuální limit nabíjecího proudu hlášený BMS |
| `com.victronenergy.battery.<id>/Info/DischargeCurrentLimit` | DCL — aktuální limit vybíjecího proudu hlášený BMS |
| `com.victronenergy.battery.<id>/Soc` | SOC hlášený BMS (jen pro log/kontext, ne pro řízení) |
| `com.victronenergy.battery.<id>/Voltages/Cell1..N` | napětí jednotlivých článků, pokud driver pole publikuje |
| `com.victronenergy.settings/Settings/SystemSetup/MaxChargeCurrent` (orientačně) | zápisový bod pro omezení max. nabíjecího proudu přes DVCC — přesnou cestu ověřit |

Pro zápis limitu nabíjecího proudu je nutné potvrdit, jestli jde přes obecné DVCC nastavení, nebo přes ESS-specifické `CGwacs/...` cesty — liší se podle toho, jak je systém nakonfigurovaný (ESS vs. bez ESS).
