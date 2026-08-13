# D-Bus cesty

## Skutečné D-Bus services na tomto systému (ověřeno 13.8.2026)

Zjištěno přímo přes `ssh root@<cerbo> "dbus -y"` (viz [scripts/poll-cerbo.sh](scripts/poll-cerbo.sh) pro postup a ověření, že je to čistě čtecí příkaz).

| Service | Co to je |
|---|---|
| `com.victronenergy.battery.socketcan_can1` | n-BMS — **jediná battery service pro celý pack**. **Oprava (13.8.2026)**: D-Bus hlásí `Manufacturer: SHEnergy`, ale to je jen artefakt CAN protokolu — fyzický hardware je **Seplos** (potvrzeno uživatelem + komunitní zkušenosti: Seplos BMS se po nahrání Victron-CAN profilu navenek hlásí jako "SHEnergy", viz [Victron Community](https://communityarchive.victronenergy.com/questions/257352/victron-shunt-and-seplos-bms.html)). Nevíme jistě, jestli jde o V2 nebo V3 generaci — ověřit podle štítku na fyzické jednotce. Driver na Venus OS: `can-bus-bms` (v0.71), `ProductName: CAN-SMARTBMS-BAT`. n-BMS prezentuje oba paralelní 16S stringy Venus OS jako jednu sjednocenou baterii, takže `System/MaxCellVoltage`/`MinCellVoltage` už zahrnují všech 32 článků najednou, ne jen jeden string. Installed capacity 400 Ah (aktuálně 411 Ah), SOH 100 %. |
| `com.victronenergy.grid.cgwacs_ttyUSB0_mb1` | grid meter (Carlo Gavazzi, přes Modbus/USB) |
| `com.victronenergy.pvinverter.pv_44_2366585` | Fronius (AC-coupled PV inverter) |
| `com.victronenergy.vebus.ttyS4` | cluster MultiPlus-II (6×) |
| `com.victronenergy.system` | systémové agregáty |
| `com.victronenergy.fronius` | řídicí/management service k Froniu (odlišná od `pvinverter` service výše, která nese naměřená data) |

Pozn.: v seznamu je jen jedna battery service (`can1`), ne dvě — takže interní topologie "2× 16S string" popsaná v [system-overview.md](../docs/system-overview.md) je vyřešená uvnitř n-BMS, Venus OS ji vidí zvenku jako jeden celek.

## Cesty na battery service

**Důležitá zvláštnost tohoto driveru (can-bus-bms)**: individuální dotazy typu `dbus -y <service> /Alarms/LowVoltage GetValue` vrací prázdno, **i když ta hodnota reálně existuje a je 0 (OK)**. Tenhle driver zjevně nepublikuje `Alarms/*` (a řadu dalších polí) jako samostatně adresovatelné D-Bus objekty — jsou dostupné jen přes dotaz na **kořenovou cestu `/`**, která vrátí celý stav jako jeden vnořený slovník. Ověřeno 13.8.2026:

```
ssh root@<cerbo> "dbus -y com.victronenergy.battery.socketcan_can1 / GetValue"
```

[`scripts/poll-cerbo.sh`](scripts/poll-cerbo.sh) proto čte battery data přes tenhle jediný root dotaz, ne přes 25 jednotlivých cest — je to jednodušší i rychlejší.

### Kompletní výpis klíčových polí z root dumpu (13.8.2026)

| Pole | Hodnota (13.8.2026) | Význam |
|---|---|---|
| `Dc/0/Voltage` | 54,73 V | celková voltáž packu |
| `Dc/0/Current` | 98,8 A | okamžitý DC proud |
| `Dc/0/Temperature` | 37,9 °C | teplota (pack-level, jiný senzor než System/*CellTemperature) |
| `System/MaxCellVoltage` / `MinCellVoltage` | 3,443 V / 3,410 V | napětí nejvyššího/nejnižšího článku napříč packem |
| `System/MaxVoltageCellId` / `MinVoltageCellId` | `Pack-01#` / `Pack-01#` | který "Pack" (16článková skupina), ne konkrétní článek — na to je potřeba appka n-BMS |
| `System/MaxCellTemperature` / `MinCellTemperature` | 29,0 °C / 26,0 °C | teplotní rozsah mezi moduly |
| `System/MaxTemperatureCellId` / `MinTemperatureCellId` | `Pack-02#` / `Pack-01#` | potvrzuje existenci obou modulů (Pack-01, Pack-02) |
| `System/NrOfModulesOnline` | 2 | oba stringy online |
| `Info/MaxChargeCurrent` | 190 A | CCL. **Oprava**: dřív jsem uváděl špatnou cestu `Info/ChargeCurrentLimit` |
| `Info/MaxDischargeCurrent` | 360 A | DCL |
| **`Info/MaxChargeVoltage`** | **57,0 V (= 3,5625 V/článek)** | **Nejdůležitější nález** — cíl/limit nabíjecího napětí, který BMS udává. Nejbližší reálná hodnota k dlouho hledanému `V_hard` — viz [fronius/README.md](../fronius/README.md) a poznámka o nuanci "cíl vs. tvrdé odpojení" tam. |
| **`Info/BatteryLowVoltage`** | **46,4 V (= 2,9 V/článek)** | Odpověď na otázku "kde je bezpečné dno" z diskuze o vybíjení — sedí přesně do dřívějšího odhadu 2,8–3,0 V/článek. |
| `Soc` / `Soh` | 97,0 % / 100,0 % | SOC (jen log/kontext, viz [soc-calibration.md](../docs/soc-calibration.md)) a State of Health |
| `Capacity` / `InstalledCapacity` | 411 Ah / 400 Ah | aktuální vs. instalovaná kapacita |
| `Alarms/LowVoltage`, `HighCellVoltage`, `CellImbalance`, `ChargeBlocked`, `DischargeBlocked`, `HighChargeCurrent`, `HighDischargeCurrent`, `HighTemperature`, `LowTemperature`, `HighChargeTemperature`, `LowChargeTemperature`, `InternalFailure` | všech 12 = 0 (OK) | 0=OK, 1=Warning, 2=Alarm — **kompletní ověřený seznam** (pozn.: žádné samostatné `Alarms/HighVoltage`, jen `HighCellVoltage`) |
| `Diagnostics/Module0..2/Alarms/*` | `[]` (prázdné) | per-modulová diagnostika **není** tímhle driverem publikovaná — nejde přes ni zjistit, který konkrétní modul by alarm spustil |

`com.victronenergy.vebus.ttyS4/State` — 0=Off, 2=Fault, 3=Bulk, 4=Absorption, 5=Float, 252=External control atd. — zachytí přesný okamžik pádu do OFF ([zdroj](https://community.victronenergy.com/questions/14089/ve-bus-state-codes.html)). Tahle cesta funguje standardně (individuální dotaz), rootdump quirk se týká jen battery service.

`com.victronenergy.settings/Settings/SystemSetup/MaxChargeCurrent` — zápisový bod pro omezení max. nabíjecího proudu přes DVCC — **potvrzeno**, viz níže.

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

## BMS je Seplos, ne "SHEnergy" — přímá konfigurace přes výrobcův software

Fyzický BMS hardware je **Seplos** (nejspíš V2 nebo V3 generace, ověřit podle štítku) — "SHEnergy" v D-Bus datech je jen jméno, kterým se Seplos hlásí po nahrání Victron-CAN protokolu, ne skutečný výrobce.

**Oficiální konfigurační software** (RS485 připojení k PC, jiný port než CAN do Cerba):
- **Battery Manager** (Seplos V2 BMS) nebo **BMS Studio** (Seplos V3 BMS) — ke stažení na [seplos.com/download.html](https://www.seplos.com/download.html)
- Návod: [BMS 3.0 Operation Instruction of Upper Computer](https://www.seplos.com/bms-3.0-operation-instruction-of-upper-computer.html)

**Přímo relevantní komunitní vlákna** k chování nabíjecího proudu, které jsme pozorovali (rampování, časté omezování):
- [Seplos Reducing Current Toward Full Charge — DIY Solar Power Forum](https://diysolarforum.com/threads/seplos-reducing-current-toward-full-charge.83366/)
- [Seplos BMS v2 Charging Current Restricted to 100A — DIY Solar Power Forum](https://diysolarforum.com/threads/seplos-bms-v2-charging-current-restricted-to-100a.73263/)
- [Seplos V3 BMS charger/balancer help — DIY Solar Power Forum](https://diysolarforum.com/threads/seplos-v3-bms-charger-balancer-help.102569/)

**Doporučený přístup**: vnější řízení přes Victron (DVCC teď, Node-RED později) zůstává primární bezpečnostní vrstva — je ověřené funkční (viz [fronius/README.md](../fronius/README.md)) a nezávisí na tom, jestli je interní logika BMS dobře nastavená. Přímé ladění v Seplos software je hodnotný doplněk (a výše uvedená vlákna vypadají přímo relevantní k našemu problému), ale nejdřív software jen stáhnout a prozkoumat offline, než cokoliv měnit na živém systému — riziko špatně pochopeného zásahu do vnitřních ochranných prahů je vyšší než u vnějšího omezení proudu.

## Ověření, že je čtení bezpečné (GetValue vs. SetValue)

`dbus -y <service> <path> GetValue` je zdokumentovaný oficiální způsob čtení (Venus OS command line manual, `victronenergy/velib_python` na GitHubu). Zápis vyžaduje jinou, argumentovou metodu (`SetValue <hodnota>`), která se nikde v tomto repozitáři nepoužívá. Zdroje:
- [Venus OS Operational Command Line Manual — Victron Energy](https://www.victronenergy.com/live/open_source:ccgx:commandline?do=export_pdf&rev=1615037933)
- [commandline operational — victronenergy/venus Wiki, GitHub](https://github.com/victronenergy/venus/wiki/commandline---operational)
- [velib_python/vedbus.py — victronenergy/velib_python, GitHub](https://github.com/victronenergy/velib_python/blob/master/vedbus.py)
