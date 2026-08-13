# FVE — diagnostika a dokumentace domácí baterie

Dokumentace k diagnostice a řešení problémů na domácím FVE systému s homemade LFP battery packem. Vzniklo jako zápis z ladicí session s Claude. Repozitář je rozdělený na dvě provázané, ale samostatně řešené kapitoly — viz níže.

## Systém (stručně)

- 6× Victron MultiPlus-II 48/3000/35-32 (ACOut2 switchable)
- Fronius Symo 17,5 — AC-coupled FVE
- Baterie: homemade pack, 32 článků, **2× nezávislý 16S string paralelně**, LFP, ~400 Ah, ~15 kWh využitelné kapacity
- BMS: n-BMS, fyzicky **Seplos**, komunikace přes CAN-bus do Venus OS (managed battery)
- Aktivní balancer: Enerkey (samostatná jednotka pro každý string)
- GX zařízení: Cerbo GX (Venus OS)

Podrobný popis viz [`docs/system-overview.md`](docs/system-overview.md).

## Kapitoly

### 1. Kalibrace a rebalance baterie — **aktivní práce**

Diagnostika DVCC shutdownu po pokusu o kalibraci SOC, nevybalancovaný pack, doporučený postup nápravy a návrh trvalé automatizace.

- [`docs/system-overview.md`](docs/system-overview.md) — hardware a architektura systému, včetně ověřených nastavení Enerkey balancerů a doporučení k jejich sjednocení
- [`docs/enerkey-balancer-mechanism.md`](docs/enerkey-balancer-mechanism.md) — jak Enerkey/NEEY balancer skutečně funguje uvnitř (sekvenční přenos energie, globální RunVol/StopVol brána) a proč to má důsledky pro naše nastavení
- [`docs/incident-dvcc-shutdown.md`](docs/incident-dvcc-shutdown.md) — chronologie incidentu: SOC drift → pokus o kalibraci → pád Victronu do OFF
- [`docs/soc-calibration.md`](docs/soc-calibration.md) — jak funguje SOC kalibrace u CAN-bus managed baterie, pojem tail current, proč nejde kalibrovat nevybalancovaný pack
- [`docs/rebalancing-procedure.md`](docs/rebalancing-procedure.md) — doporučený postup bezpečného rebalance a kalibrace horní/dolní meze
- [`automation/current-node-red-flow.md`](automation/current-node-red-flow.md) — rozbor Node-RED automatizace, která na systému aktuálně běží (SOC-only řízení DVCC, prodej do sítě, on/off-grid přepínání) — nalezené chyby a doporučená vylepšení
- [`automation/node-red-control-logic.md`](automation/node-red-control-logic.md) — návrh trvalé closed-loop automatizace v Node-RED na Cerbu, řízené podle napětí článků místo SOC
- [`diagnostics/dbus-paths.md`](diagnostics/dbus-paths.md) — přehled D-Bus cest potřebných pro diagnostiku a automatizaci
- [`diagnostics/checklist.md`](diagnostics/checklist.md) — otevřené položky k ověření na systému, včetně průběžných měření cell voltage spread

### 2. Fronius / battery power mismatch — **aktivní práce, prolnulo s kapitolou 1**

Fronius (17,5 kW inverter, aktuálně osazeno 12,5 kWp panelů) je podle oficiální Victron sizing guidance předimenzovaný vůči ~400 Ah packu. Původní hypotéza — že za nedodržováním proudového limitu stojí skokové PV výkonové špičky — byla **13.8.2026 vyvrácena**: nestabilita byla živě zachycena i při naprosto stabilním PV výkonu (~4,1 kW, žádné mraky). Skutečná příčina: vlastní rampovací algoritmus BMS (CCL roste v krocích až ke svému stropu 190 A) v kombinaci s nevyrovnaným packem, s odstupem ~2 s mezi prvním varovným alarmem a vlastním odříznutím proudu BMS. Na základě plné analýzy logu (35 alarmových epizod za 42 min) odvozen a **empiricky ověřený bezpečný proudový limit 10 A**.

- [`fronius/README.md`](fronius/README.md) — popis problému s podloženými čísly, souvislost s kapitolou 1, návrh řešení a otevřené otázky

## Stav

Většina klíčových čísel je už **potvrzená přímo ze zařízení** (topologie packu, Enerkey nastavení, `Info/MaxChargeVoltage` = 3,5625 V/článek, `Info/BatteryLowVoltage` = 2,9 V/článek, BMS = Seplos), ne jen odhad. Sjednocení Enerkey balancerů a rebalance packu **proběhly a fungují** (12.-13.8.2026, spread 270 mV → 2-3 mV). Bezpečný nabíjecí proud (10 A) je empiricky ověřený z živých dat. Návrh trvalé automatizace ([`automation/node-red-control-logic.md`](automation/node-red-control-logic.md)) je aktualizovaný podle těchto zjištění, ale **zatím neimplementovaný** na systému.

## Licence

[MIT](LICENSE)
