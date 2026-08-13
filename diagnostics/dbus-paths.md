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
| `com.victronenergy.battery.socketcan_can1/Dc/0/Voltage` | celková voltáž packu |
| `com.victronenergy.battery.socketcan_can1/System/MaxCellVoltage` | napětí nejvyššího článku (napříč celým packem) |
| `com.victronenergy.battery.socketcan_can1/System/MinCellVoltage` | napětí nejnižšího článku |
| `com.victronenergy.battery.socketcan_can1/System/MaxVoltageCellId` | který "Pack" (16článková skupina) je aktuálně nejvyšší — ne konkrétní článek, na to je potřeba appka n-BMS |
| `com.victronenergy.battery.socketcan_can1/System/MinVoltageCellId` | který "Pack" je aktuálně nejnižší |
| `com.victronenergy.battery.socketcan_can1/Info/MaxChargeCurrent` | CCL — aktuální limit nabíjecího proudu hlášený BMS. **Oprava**: dřív jsem uváděl `Info/ChargeCurrentLimit`, což je špatně (vracelo prázdno) — správná cesta ověřena přes [dbus-systemcalc-py zdroj](https://github.com/victronenergy/dbus-systemcalc-py/blob/master/delegates/dvcc.py). |
| `com.victronenergy.battery.socketcan_can1/Info/MaxDischargeCurrent` | DCL — analogicky, nezávisle neověřeno na tomhle systému |
| `com.victronenergy.battery.socketcan_can1/Dc/0/Temperature` | teplota (pokud ji n-BMS na tuhle cestu publikuje — neověřeno, viz [scripts/poll-cerbo.sh](scripts/poll-cerbo.sh)) |
| `com.victronenergy.battery.socketcan_can1/Soc` | SOC hlášený BMS (jen pro log/kontext, ne pro řízení — viz [soc-calibration.md](../docs/soc-calibration.md)) |
| `com.victronenergy.battery.socketcan_can1/Dc/0/Current` | okamžitý DC proud baterie |
| `com.victronenergy.battery.socketcan_can1/Alarms/LowVoltage`, `HighVoltage`, `HighCellVoltage`, `CellImbalance`, `HighChargeCurrent`, `HighChargeTemperature`, `LowChargeTemperature` | 0=OK, 1=Warning, 2=Alarm — **potenciálně klíčové**: pokud n-BMS hlásí Warning před tvrdým odpojením, tohle může přímo odhalit `V_warn`/`V_hard` v reálném čase ([zdroj](https://github.com/victronenergy/venus/wiki/dbus)) |
| `com.victronenergy.vebus.ttyS4/State` | 0=Off, 2=Fault, 3=Bulk, 4=Absorption, 5=Float, 252=External control atd. — zachytí přesný okamžik pádu do OFF ([zdroj](https://community.victronenergy.com/questions/14089/ve-bus-state-codes.html)) |
| `com.victronenergy.settings/Settings/SystemSetup/MaxChargeCurrent` | zápisový bod pro omezení max. nabíjecího proudu přes DVCC — **potvrzeno**, viz níže |

## Cesty pro zápis (potvrzeno z exportu Node-RED flow, viz [`automation/current-node-red-flow.md`](../automation/current-node-red-flow.md))

Node-RED addon (`node-red-contrib-victron`) adresuje services přes `service/instance-číslo` (např. `com.victronenergy.battery/512`), ne přes syrové D-Bus jméno jako `dbus-spy` výše (`com.victronenergy.battery.socketcan_can1`) — pravděpodobně stejný fyzický systém, jen jinak adresovaný. Node/instance čísla zjištěná z exportovaného flow:

| Service (Node-RED instance) | Odpovídá (dbus-spy) | Poznámka |
|---|---|---|
| `com.victronenergy.battery/512` | `com.victronenergy.battery.socketcan_can1` (nejisté, k ověření) | SOC |
| `com.victronenergy.pvinverter/20` | `com.victronenergy.pvinverter.pv_44_2366585` | Fronius |
| `com.victronenergy.grid/30` | `com.victronenergy.grid.cgwacs_ttyUSB0_mb1` | grid meter |
| `com.victronenergy.vebus/276` | `com.victronenergy.vebus.ttyS4` | MultiPlus-II cluster |
| `com.victronenergy.system/0` | `com.victronenergy.system` | agregáty, spotřeba po fázích, relé |

Zápisové cesty použité aktuální automatizací:

| Cesta | Zápis | Účel |
|---|---|---|
| `com.victronenergy.settings/Settings/SystemSetup/MaxChargeCurrent` | float | DVCC limit nabíjecího proudu — obecné DVCC nastavení, ne ESS-specifické |
| `com.victronenergy.settings/Settings/CGwacs/AcPowerSetPoint` | integer (W) | ESS grid set-point (export/import cíl) |
| `com.victronenergy.settings/Settings/CGwacs/MaxFeedInPower` | integer (W) | strop pro export do sítě (`-1` = neomezeno, `>= 0` = limit) |
| `com.victronenergy.settings/Settings/CGwacs/BatteryLife/State` | enum (1–12) | ESS BatteryLife/optimized mode stav, včetně „Keep batteries charged" (9) |
| `com.victronenergy.vebus/276/Mode` | enum (1 Charger Only, 2 Inverter Only, 3 On, 4 Off) | přepínání on/off-grid — `2`/`3` používá aktuální automatizace |

Tohle zodpovídá dřívější otevřenou otázku, jestli zápis limitu nabíjecího proudu jde přes obecné DVCC nastavení nebo ESS-specifické `CGwacs/...` — jde přes DVCC (`SystemSetup/MaxChargeCurrent`), `CGwacs/...` se používá pro ESS grid set-point/feed-in/BatteryLife zvlášť.

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
