# FVE — diagnostika a dokumentace domácí baterie

Dokumentace k diagnostice a řešení problému s kalibrací SOC (state of charge) na domácím FVE systému s homemade LFP battery packem. Vzniklo jako zápis z ladicí session s Claude — zachycuje diagnostikovaný incident, hypotézy o příčině, doporučený postup nápravy a návrh trvalé automatizace, která by měla zabránit opakování.

## Systém (stručně)

- 6× Victron MultiPlus-II 48/3000/35-32 (ACOut2 switchable)
- Fronius Symo 17,5 — AC-coupled FVE
- Baterie: homemade pack, 32 článků (16S2P), LFP, ~400 Ah, ~15 kWh využitelné kapacity
- BMS: n-BMS, komunikace přes CAN-bus do Venus OS (managed battery)
- Aktivní balancer: Enerkey
- GX zařízení: Cerbo GX (Venus OS)

Podrobný popis viz [`docs/system-overview.md`](docs/system-overview.md).

## Obsah repozitáře

- [`docs/system-overview.md`](docs/system-overview.md) — hardware a architektura systému
- [`docs/incident-dvcc-shutdown.md`](docs/incident-dvcc-shutdown.md) — chronologie incidentu: SOC drift → pokus o kalibraci → pád Victronu do OFF
- [`docs/soc-calibration.md`](docs/soc-calibration.md) — jak funguje SOC kalibrace u CAN-bus managed baterie, pojem tail current, proč nejde kalibrovat nevybalancovaný pack
- [`docs/rebalancing-procedure.md`](docs/rebalancing-procedure.md) — doporučený postup bezpečného rebalance a kalibrace horní/dolní meze
- [`automation/node-red-control-logic.md`](automation/node-red-control-logic.md) — návrh trvalé closed-loop automatizace v Node-RED na Cerbu, řízené podle napětí článků místo SOC
- [`diagnostics/dbus-paths.md`](diagnostics/dbus-paths.md) — přehled D-Bus cest potřebných pro diagnostiku a automatizaci
- [`diagnostics/checklist.md`](diagnostics/checklist.md) — otevřené položky k ověření na systému

## Stav

Diagnóza je z velké části **hypotéza odvozená z popisu chování systému, ne ověřená přímo měřením** (viz checklist). Postup rebalance a návrh automatizace zatím nebyly na systému provedeny/nasazeny.

## Licence

[MIT](LICENSE)
