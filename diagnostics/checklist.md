# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [x] Topologie packu — potvrzeno uživatelem: **2× nezávislý 16S string paralelně** (ne 16S2P), tedy 32 samostatných balančních bodů. Viz [system-overview.md](../docs/system-overview.md).
- [x] Vyrovnává Enerkey balancer i **mezi oběma stringy**, nebo jen v rámci jednoho stringu? — **Potvrzeno: jen v rámci stringu.** Existují 2 samostatné fyzické jednotky ("Horní", "Dolní"), žádné křížové propojení. Nerovnováha mezi stringy jako celky se aktivně neřeší vůbec.
- [ ] Aktuální cell voltage spread (přes dbus-spy nebo Node-RED) — trend viz "Průběžná měření" níže, ale potvrdit přímo v n-BMS/dbus-spy.
- [ ] Discharge cutoff napětí na článek nastavené v n-BMS vs. skutečné napětí nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe)
- [ ] n-BMS OV warning threshold vs. hard disconnect threshold (má n-BMS měkčí varovný stupeň před tvrdým odpojením?)
- [x] Enerkey — přesný aktivační (RunVol) a stop (StopVol) práh nastavený na konkrétním zařízení. **Potvrzeno ze screenshotů appky**: Horní RunVol 3,480 V / StopVol 3,400 V / Max EquCur 0,5 A; Dolní RunVol 3,350 V / StopVol 3,180 V / Max EquCur 4,0 A. Viz [system-overview.md](../docs/system-overview.md) pro plnou tabulku.
- [ ] **Akce**: aplikovat doporučené sjednocené nastavení obou Enerkey jednotek (viz [system-overview.md](../docs/system-overview.md#doporučené-nastavení-sjednocené-ke-zvážení)) a ověřit chování po aplikaci — před tím potvrdit OV warning threshold v n-BMS (položka výše).
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] **Retest**: jak nízko lze pack reálně vybít po vypnutí/úpravě noční automatizace, která ho dobíjela na 50 % (viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bod 6)
- [ ] Přesné D-Bus cesty pro čtení cell voltages a zápis MaxChargeCurrent (viz [dbus-paths.md](dbus-paths.md)) — ověřit přes dbus-spy

**Pozn.:** položky týkající se proudových špiček z Fronia (2 A nastaveno, reálně naskakuje na 30 A) byly přesunuty do samostatné kapitoly — viz [`../fronius/README.md`](../fronius/README.md). Řeší se odděleně od kalibrace baterie.

## Průběžná měření (cell voltage spread)

Sledovat trend v čase — klesající spread = balancer/pomalé nabíjení funguje.

| Kdy / za jakých podmínek | Spread (max − min napětí článku) |
|---|---|
| V okamžiku incidentu (nabíjení na 100 %, viz [incident](../docs/incident-dvcc-shutdown.md)) | ~270 mV |
| Nabíjení packu výkonem ~5 kW (12.8.2026) | ~100 mV |
| SOC ~99 %, max. nabíjecí proud omezen na 2 A (12.8.2026) | ~64 mV |

