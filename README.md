# FVE — diagnostika a dokumentace domácí baterie

Dokumentace k diagnostice a řešení problémů na domácím FVE systému s homemade LFP battery packem. Vzniklo jako zápis z ladicí session s Claude. Repozitář je rozdělený na dvě provázané, ale samostatně řešené kapitoly — viz níže.

## Systém (stručně)

- 6× Victron MultiPlus-II 48/3000/35-32 (ACOut2 switchable)
- Fronius Symo 17,5 — AC-coupled FVE
- Baterie: homemade pack, 32 článků, **2× nezávislý 16S string paralelně**, LFP, ~400 Ah, ~15 kWh využitelné kapacity
- BMS: n-BMS, komunikace přes CAN-bus do Venus OS (managed battery)
- Aktivní balancer: Enerkey (samostatná jednotka pro každý string)
- GX zařízení: Cerbo GX (Venus OS)

Podrobný popis viz [`docs/system-overview.md`](docs/system-overview.md).

## Kapitoly

### 1. Kalibrace a rebalance baterie — **aktivní práce**

Diagnostika DVCC shutdownu po pokusu o kalibraci SOC, nevybalancovaný pack, doporučený postup nápravy a návrh trvalé automatizace.

- [`docs/system-overview.md`](docs/system-overview.md) — hardware a architektura systému, včetně ověřených nastavení Enerkey balancerů a doporučení k jejich sjednocení
- [`docs/incident-dvcc-shutdown.md`](docs/incident-dvcc-shutdown.md) — chronologie incidentu: SOC drift → pokus o kalibraci → pád Victronu do OFF
- [`docs/soc-calibration.md`](docs/soc-calibration.md) — jak funguje SOC kalibrace u CAN-bus managed baterie, pojem tail current, proč nejde kalibrovat nevybalancovaný pack
- [`docs/rebalancing-procedure.md`](docs/rebalancing-procedure.md) — doporučený postup bezpečného rebalance a kalibrace horní/dolní meze
- [`automation/node-red-control-logic.md`](automation/node-red-control-logic.md) — návrh trvalé closed-loop automatizace v Node-RED na Cerbu, řízené podle napětí článků místo SOC
- [`diagnostics/dbus-paths.md`](diagnostics/dbus-paths.md) — přehled D-Bus cest potřebných pro diagnostiku a automatizaci
- [`diagnostics/checklist.md`](diagnostics/checklist.md) — otevřené položky k ověření na systému, včetně průběžných měření cell voltage spread

### 2. Fronius / battery power mismatch — **odloženo, řeší se po dokončení kapitoly 1**

Fronius (17,5 kW inverter, aktuálně osazeno 12,5 kWp panelů) je podle oficiální Victron sizing guidance předimenzovaný vůči ~400 Ah packu — pack má cca poloviční kapacitu, než Victron pro lithiové baterie doporučuje už jen pro současné osazení panelů. Skokové PV výkonové špičky při rychlé změně ozáření mohou krátkodobě přestřelit nastavený nabíjecí limit (pozorováno 2 A nastaveno → ~30 A reálně) — pravděpodobně přímá souvislost s tím, proč byla historicky zavedená 96% cap automatizace (viz kapitola 1) a proč dobití na 100 % shazuje systém do OFF. Obsahuje i nastřelený návrh řešení (buffer řízený napětím článků, ne SOC).

- [`fronius/README.md`](fronius/README.md) — popis problému s podloženými čísly, souvislost s kapitolou 1, návrh řešení a otevřené otázky

## Stav

Diagnóza je z velké části **hypotéza odvozená z popisu chování systému, postupně ověřovaná měřením** (viz checklist). Některá zjištění (topologie packu, nastavení Enerkey) jsou už potvrzená přímo ze zařízení. Postup rebalance, doporučené sjednocení balancerů a návrh automatizace zatím nebyly na systému aplikovány.

## Licence

[MIT](LICENSE)
