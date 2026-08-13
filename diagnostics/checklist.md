# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [x] Topologie packu — potvrzeno uživatelem: **2× nezávislý 16S string paralelně** (ne 16S2P), tedy 32 samostatných balančních bodů. Viz [system-overview.md](../docs/system-overview.md).
- [x] Vyrovnává Enerkey balancer i **mezi oběma stringy**, nebo jen v rámci jednoho stringu? — **Potvrzeno: jen v rámci stringu.** Existují 2 samostatné fyzické jednotky ("Horní", "Dolní"), žádné křížové propojení. Nerovnováha mezi stringy jako celky se aktivně neřeší vůbec.
- [x] Aktuální cell voltage spread — **vyřešeno přímo z Enerkey appky** (nemuselo se řešit přes dbus-spy/Node-RED, appka má vlastní STATUS obrazovku s live daty). Trend viz "Průběžná měření" níže.
- [x] Discharge cutoff napětí na článek nastavené v n-BMS — **vyřešeno 13.8.2026**: `Info/BatteryLowVoltage` = 2,9 V/článek (46,4 V pack), přímo z n-BMS. Srovnání s napětím při SOC ~47 % je teď spíš historická otázka (viz retest níže — 47% jev se od té doby nereprodukoval).
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe) — relevantní i pro **druhý** pád do OFF (12.8.2026, po prvním zapnutí Equalize switche), ne jen původní incident.
- [x] n-BMS OV threshold — **vyřešeno 13.8.2026**: `Info/MaxChargeVoltage` = 3,5625 V/článek (57,0 V pack), přímo z n-BMS. Nuance: je to BMS-udávaný cíl nabíjení, ne nutně doslovný hard-disconnect trip point, ale prakticky ekvivalentní pro naše účely — viz [fronius/README.md](../fronius/README.md). Samostatný "warning" stupeň se nepodařilo najít (viz alarm položka níže — všech 12 alarm polí jsou binární OK/Warning/Alarm bez samostatné napěťové hodnoty prahu).
- [x] Enerkey — přesný aktivační (RunVol) a stop (StopVol) práh. **Potvrzeno a od 12.8.2026 sjednoceno na obou jednotkách**: RunVol 3,350 V / StopVol 3,180 V / Max EquCur 4,0 A / Startup DifVol 0,005 V. Viz [system-overview.md](../docs/system-overview.md).
- [x] **Klíčový nález**: obě jednotky měly vypnutý hlavní přepínač **Equalizing** — balancery neběžely vůbec, nezávisle na RunVol/StopVol. Od 12.8.2026 zapnuto na obou. Viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md).
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] **Retest**: jak nízko lze pack reálně vybít po vypnutí/úpravě noční automatizace, která ho dobíjela na 50 % (viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bod 6)
- [ ] **Nová položka**: kontrolovaně odlišit, jestli druhý pád do OFF (12.8.2026) způsobilo zapnutí balanceru samotné, nebo souběžné nabíjení přes "Keep batteries charged" na už nevyrovnaném packu na SOC 100 % — otestovat zapnutí Equalize při nulovém nabíjecím proudu.
- [x] Přesné D-Bus cesty pro čtení cell voltages — **vyřešeno 13.8.2026**, viz [dbus-paths.md](dbus-paths.md). Zápisová cesta pro MaxChargeCurrent přes DVCC/ESS zůstává neověřená (nižší priorita).
- [x] **SSH a D-Bus service names zjištěny (13.8.2026)**: SSH funkční (root heslo nastaveno přes Settings → General → Set root password), battery service = `com.victronenergy.battery.socketcan_can1` (jediná služba pro celý pack, ne dvě), grid = `com.victronenergy.grid.cgwacs_ttyUSB0_mb1`, PV/Fronius = `com.victronenergy.pvinverter.pv_44_2366585`. [`scripts/poll-cerbo.sh`](scripts/poll-cerbo.sh) aktualizován a připraven k použití pro měření napěťové výchylky při proudové špičce (viz [fronius/README.md](../fronius/README.md)).
- [ ] **Nová položka**: ověřit, jestli Dolní jednotka byla 12.8.2026 v klidovém stavu (`System ready`, 0 A) kvůli duty-cyclingu nebo kvůli verzí-specifické nuanci RunVol/StopVol brány — viz [enerkey-balancer-mechanism.md](../docs/enerkey-balancer-mechanism.md).
- [x] **n-BMS alarm pole zjištěna (13.8.2026)**: 12 polí (`LowVoltage`, `HighCellVoltage`, `CellImbalance`, `ChargeBlocked`, `DischargeBlocked`, `HighChargeCurrent`, `HighDischargeCurrent`, `HighTemperature`, `LowTemperature`, `HighChargeTemperature`, `LowChargeTemperature`, `InternalFailure`), aktuálně všechna 0=OK. Dostupná jen přes dotaz na kořenovou cestu `/` battery service, ne jako jednotlivé D-Bus objekty (driver `can-bus-bms` je takhle nepublikuje samostatně) — viz [dbus-paths.md](dbus-paths.md). Per-modulová diagnostika (`Diagnostics/Module0-2/Alarms/*`) je vždy prázdná, nejde přes ni určit, který string by alarm spustil.
- [x] **Identita n-BMS zjištěna**: výrobce SHEnergy, produkt CAN-SMARTBMS-BAT, driver `can-bus-bms` v0.71.

**Pozn.:** položky týkající se proudových špiček z Fronia (2 A nastaveno, reálně naskakuje na 30 A) byly přesunuty do samostatné kapitoly — viz [`../fronius/README.md`](../fronius/README.md). Řeší se odděleně od kalibrace baterie.

## Průběžná měření (cell voltage spread)

Sledovat trend v čase — klesající spread = balancer/pomalé nabíjení funguje.

| Kdy / za jakých podmínek | Spread (max − min napětí článku) |
|---|---|
| V okamžiku incidentu (nabíjení na 100 %, viz [incident](../docs/incident-dvcc-shutdown.md)) | ~270 mV |
| Nabíjení packu výkonem ~5 kW (12.8.2026) | ~100 mV |
| SOC ~99 %, max. nabíjecí proud omezen na 2 A (12.8.2026) | ~64 mV |
| SOC 100 % (VRM), balancer ještě vypnutý, obě extrémy v jednom stringu (12.8.2026) | ~82 mV |
| Po zapnutí Equalize na obou jednotkách, pack se vybíjí (12.8.2026, 19:25) — Horní `EquRun` 4,011 A / DifVol 31 mV, Dolní `System ready` 0 A / DifVol 18 mV, napříč oběma stringy max 3,364 V / min 3,331 V | **~33 mV** |
| Pod zátěží, vybíjení 22 A (12.8.2026) — konkrétní článek neidentifikován | ~200 mV (pod zátěží, IR efekt — viz řádek níže) |
| **V klidu** (no load), 53,3 V pack, Pack 1 nejnižší 3,219 V / Pack 2 nejvyšší 3,231 V (12.8.2026) | **~12 mV** — potvrzuje, že 200 mV pod zátěží byl hlavně IR efekt, ne reálná nerovnováha náboje |
| **Živě zachycená událost** (13.8.2026, 14:24-14:25 UTC, Fronius stabilní ~4,1 kW, žádné mraky) — `alarm_high_cell_voltage` naskočil při 3,682 V, následoval reálný CCL=0 cutoff při 3,607 V s automatickým 2A-krokovým ramp-up zotavením, pak `alarm_cell_imbalance` při skoku min napětí 3,22→2,82 V (možný CAN glitch, neověřeno) | až **~850 mV** špičkově; podrobná časová osa a důsledky viz [fronius/README.md](../fronius/README.md#živě-zachycená-událost-1382026-nestabilita-i-za-ideálních-podmínek) — **kritické: nestabilita nastala BEZ kolísání PV výkonu**, což znamená prakticky nulovou rezervu i za ideálních podmínek |

