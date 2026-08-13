# D-Bus cesty

## Skutečné D-Bus services na tomto systému (ověřeno 13.8.2026)

Zjištěno přímo přes `ssh root@<cerbo> "dbus -y"` (viz [scripts/poll-cerbo.sh](scripts/poll-cerbo.sh) pro postup a ověření, že je to čistě čtecí příkaz).

| Service | Co to je |
|---|---|
| `com.victronenergy.battery.socketcan_can1` | n-BMS — **jediná battery service pro celý pack**. n-BMS prezentuje oba paralelní 16S stringy Venus OS jako jednu sjednocenou baterii, takže `System/MaxCellVoltage`/`MinCellVoltage` už zahrnují všech 32 článků najednou, ne jen jeden string. |
| `com.victronenergy.grid.cgwacs_ttyUSB0_mb1` | grid meter (Carlo Gavazzi, přes Modbus/USB) |
| `com.victronenergy.pvinverter.pv_44_2366585` | Fronius (AC-coupled PV inverter) |
| `com.victronenergy.vebus.ttyS4` | cluster MultiPlus-II (6×) |
| `com.victronenergy.system` | systémové agregáty |
| `com.victronenergy.fronius` | řídicí/management service k Froniu (odlišná od `pvinverter` service výše, která nese naměřená data) |

Pozn.: v seznamu je jen jedna battery service (`can1`), ne dvě — takže interní topologie "2× 16S string" popsaná v [system-overview.md](../docs/system-overview.md) je vyřešená uvnitř n-BMS, Venus OS ji vidí zvenku jako jeden celek.

## Cesty na battery service

| Cesta | Význam |
|---|---|
| `com.victronenergy.battery.socketcan_can1/System/MaxCellVoltage` | napětí nejvyššího článku (napříč celým packem) |
| `com.victronenergy.battery.socketcan_can1/System/MinCellVoltage` | napětí nejnižšího článku |
| `com.victronenergy.battery.socketcan_can1/System/MaxVoltageCellId` | který článek je aktuálně nejvyšší |
| `com.victronenergy.battery.socketcan_can1/System/MinVoltageCellId` | který článek je aktuálně nejnižší |
| `com.victronenergy.battery.socketcan_can1/Info/ChargeCurrentLimit` | CCL — aktuální limit nabíjecího proudu hlášený BMS |
| `com.victronenergy.battery.socketcan_can1/Info/DischargeCurrentLimit` | DCL — aktuální limit vybíjecího proudu hlášený BMS |
| `com.victronenergy.battery.socketcan_can1/Soc` | SOC hlášený BMS (jen pro log/kontext, ne pro řízení — viz [soc-calibration.md](../docs/soc-calibration.md)) |
| `com.victronenergy.battery.socketcan_can1/Dc/0/Current` | okamžitý DC proud baterie |
| `com.victronenergy.settings/Settings/SystemSetup/MaxChargeCurrent` (orientačně) | zápisový bod pro omezení max. nabíjecího proudu přes DVCC — přesnou cestu ještě ověřit |

Pro zápis limitu nabíjecího proudu je nutné potvrdit, jestli jde přes obecné DVCC nastavení, nebo přes ESS-specifické `CGwacs/...` cesty.

## Grid a PV (Fronius) — přímo přes reálné services

Používá [`scripts/poll-cerbo.sh`](scripts/poll-cerbo.sh). Standardní Victron konvence pro meter/pvinverter services — cesty `/Ac/L1/Power`, `/Ac/L2/Power`, `/Ac/L3/Power` (po fázích), `/Ac/Power` (celkem u PV inverteru). Systém je 3fázový (potvrzeno uživatelem, 6× MultiPlus-II, 2 na fázi).

| Cesta | Význam |
|---|---|
| `com.victronenergy.grid.cgwacs_ttyUSB0_mb1/Ac/L1..L3/Power` | výkon ze/do sítě, po fázích |
| `com.victronenergy.pvinverter.pv_44_2366585/Ac/L1..L3/Power` | výkon Fronia, po fázích |
| `com.victronenergy.pvinverter.pv_44_2366585/Ac/Power` | výkon Fronia celkem |

## Ověření, že je čtení bezpečné (GetValue vs. SetValue)

`dbus -y <service> <path> GetValue` je zdokumentovaný oficiální způsob čtení (Venus OS command line manual, `victronenergy/velib_python` na GitHubu). Zápis vyžaduje jinou, argumentovou metodu (`SetValue <hodnota>`), která se nikde v tomto repozitáři nepoužívá. Zdroje:
- [Venus OS Operational Command Line Manual — Victron Energy](https://www.victronenergy.com/live/open_source:ccgx:commandline?do=export_pdf&rev=1615037933)
- [commandline operational — victronenergy/venus Wiki, GitHub](https://github.com/victronenergy/venus/wiki/commandline---operational)
- [velib_python/vedbus.py — victronenergy/velib_python, GitHub](https://github.com/victronenergy/velib_python/blob/master/vedbus.py)
