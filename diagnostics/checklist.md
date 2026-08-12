# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [x] Topologie packu — potvrzeno uživatelem: **2× nezávislý 16S string paralelně** (ne 16S2P), tedy 32 samostatných balančních bodů. Viz [system-overview.md](../docs/system-overview.md).
- [x] Vyrovnává Enerkey balancer i **mezi oběma stringy**, nebo jen v rámci jednoho stringu? — **Potvrzeno: jen v rámci stringu.** Existují 2 samostatné fyzické jednotky ("Horní", "Dolní"), žádné křížové propojení. Nerovnováha mezi stringy jako celky se aktivně neřeší vůbec.
- [ ] Aktuální cell voltage spread (přes dbus-spy nebo Node-RED) — trend viz "Průběžná měření" níže, ale potvrdit přímo v n-BMS/dbus-spy.
- [ ] Discharge cutoff napětí na článek nastavené v n-BMS vs. skutečné napětí nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe)
- [ ] n-BMS OV warning threshold vs. hard disconnect threshold (má n-BMS měkčí varovný stupeň před tvrdým odpojením?)
- [x] Enerkey — přesný aktivační (RunVol) a stop (StopVol) práh nastavený na konkrétním zařízení. **Potvrzeno ze screenshotů appky**: Horní RunVol 3,480 V / StopVol 3,400 V / Max EquCur 0,5 A; Dolní RunVol 3,350 V / StopVol 3,180 V / Max EquCur 4,0 A. Viz [system-overview.md](../docs/system-overview.md) pro plnou tabulku.
- [ ] **Nová položka**: zvážit sjednocení/přiblížení nastavení Horního balanceru k Dolnímu (nižší RunVol/StopVol, vyšší Max EquCur) — Horní string má výrazně slabší a pozdější balancing. Bez konkrétního doporučení, dokud nebude potvrzeno, na kterém stringu vznikl původní OV trip.
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] **Retest**: jak nízko lze pack reálně vybít po vypnutí/úpravě noční automatizace, která ho dobíjela na 50 % (viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bod 6)
- [x] ~~DVCC "Limit managed battery charge current" toggle~~ — **vyvráceno**: uživatel potvrdil, že přepínač je aktivní a hodnota 2 A vyplněná. Přesto byly pozorovány špičky nabíjecího proudu až **30 A**. Nová vedoucí hypotéza: zpoždění/nepřesnost regulace AC-coupled PV přebytku (frequency-shift curtailment) při rychlých změnách výkonu Fronia — viz [node-red-control-logic.md](../automation/node-red-control-logic.md).
- [ ] **Nová položka**: logovat výkon Fronia (PV output) společně s nabíjecím proudem a nastaveným limitem, abychom potvrdili/vyvrátili, že špičky na 30 A časově korelují se skokovými změnami PV výkonu (např. hrana mraku)
- [ ] Přesné D-Bus cesty pro čtení cell voltages a zápis MaxChargeCurrent (viz [dbus-paths.md](dbus-paths.md)) — ověřit přes dbus-spy

## Průběžná měření (cell voltage spread)

Sledovat trend v čase — klesající spread = balancer/pomalé nabíjení funguje.

| Kdy / za jakých podmínek | Spread (max − min napětí článku) |
|---|---|
| V okamžiku incidentu (nabíjení na 100 %, viz [incident](../docs/incident-dvcc-shutdown.md)) | ~270 mV |
| Nabíjení packu výkonem ~5 kW (12.8.2026) | ~100 mV |
| SOC ~99 %, max. nabíjecí proud omezen na 2 A (12.8.2026) | ~64 mV |

