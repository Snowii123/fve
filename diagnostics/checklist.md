# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [x] Topologie packu — potvrzeno uživatelem: **2× nezávislý 16S string paralelně** (ne 16S2P), tedy 32 samostatných balančních bodů. Viz [system-overview.md](../docs/system-overview.md).
- [ ] Vyrovnává Enerkey balancer i **mezi oběma stringy**, nebo jen v rámci jednoho stringu? (Důležité kvůli topologii výše — pokud jen v rámci stringu, nerovnováha mezi stringy jako celky se řešit nebude.)
- [ ] Aktuální cell voltage spread (přes dbus-spy nebo Node-RED) — trend viz "Průběžná měření" níže, ale potvrdit přímo v n-BMS/dbus-spy.
- [ ] Discharge cutoff napětí na článek nastavené v n-BMS vs. skutečné napětí nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe)
- [ ] n-BMS OV warning threshold vs. hard disconnect threshold (má n-BMS měkčí varovný stupeň před tvrdým odpojením?)
- [ ] Enerkey — přesný aktivační (EqualizationVol) a stop (Sleepvol) práh nastavený na konkrétním zařízení. Komunitně doporučované hodnoty pro LFP jsou cca **3,41–3,44 V start / o ~0,01–0,03 V níž stop** ([DIY Solar Forum vlákno](https://diysolarforum.com/threads/how-to-calibrate-neey-enerkey-active-balancer-voltage.97277/)), ale tovární default se může lišit a nejde spolehlivě dohledat obecně na netu — nutno ověřit přímo v appce Enerkey (Bluetooth připojení, výchozí heslo `123456`, obrazovka s parametry balanceru → pole **EqualizationVol** a **Sleepvol**).
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] **Retest**: jak nízko lze pack reálně vybít po vypnutí/úpravě noční automatizace, která ho dobíjela na 50 % (viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bod 6)
- [ ] **DVCC "Limit managed battery charge current" toggle** (Settings → DVCC na GX konzoli) — ověřit, že je zapnutý na "Yes", ne jen vyplněné číslo v poli. Pravděpodobné vysvětlení, proč nastavených 2 A neodpovídá reálně měřeným 5-6 A (viz [node-red-control-logic.md](../automation/node-red-control-logic.md))
- [ ] Přesné D-Bus cesty pro čtení cell voltages a zápis MaxChargeCurrent (viz [dbus-paths.md](dbus-paths.md)) — ověřit přes dbus-spy

## Průběžná měření (cell voltage spread)

Sledovat trend v čase — klesající spread = balancer/pomalé nabíjení funguje.

| Kdy / za jakých podmínek | Spread (max − min napětí článku) |
|---|---|
| V okamžiku incidentu (nabíjení na 100 %, viz [incident](../docs/incident-dvcc-shutdown.md)) | ~270 mV |
| Nabíjení packu výkonem ~5 kW (12.8.2026) | ~100 mV |
| SOC ~99 %, max. nabíjecí proud omezen na 2 A (12.8.2026) | ~64 mV |

