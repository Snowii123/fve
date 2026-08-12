# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [x] Topologie packu — potvrzeno uživatelem: **2× nezávislý 16S string paralelně** (ne 16S2P), tedy 32 samostatných balančních bodů. Viz [system-overview.md](../docs/system-overview.md).
- [x] Vyrovnává Enerkey balancer i **mezi oběma stringy**, nebo jen v rámci jednoho stringu? — **Potvrzeno: jen v rámci stringu.** Existují 2 samostatné fyzické jednotky ("Horní", "Dolní"), žádné křížové propojení. Nerovnováha mezi stringy jako celky se aktivně neřeší vůbec.
- [x] Aktuální cell voltage spread — **vyřešeno přímo z Enerkey appky** (nemuselo se řešit přes dbus-spy/Node-RED, appka má vlastní STATUS obrazovku s live daty). Trend viz "Průběžná měření" níže.
- [ ] Discharge cutoff napětí na článek nastavené v n-BMS vs. skutečné napětí nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe) — relevantní i pro **druhý** pád do OFF (12.8.2026, po prvním zapnutí Equalize switche), ne jen původní incident.
- [ ] n-BMS OV warning threshold vs. hard disconnect threshold — **stále nejdůležitější neznámá**, viz `V_hard` v žebříčku prahů ve [fronius/README.md](../fronius/README.md).
- [x] Enerkey — přesný aktivační (RunVol) a stop (StopVol) práh. **Potvrzeno a od 12.8.2026 sjednoceno na obou jednotkách**: RunVol 3,350 V / StopVol 3,180 V / Max EquCur 4,0 A / Startup DifVol 0,005 V. Viz [system-overview.md](../docs/system-overview.md).
- [x] **Klíčový nález**: obě jednotky měly vypnutý hlavní přepínač **Equalizing** — balancery neběžely vůbec, nezávisle na RunVol/StopVol. Od 12.8.2026 zapnuto na obou. Viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md).
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] **Retest**: jak nízko lze pack reálně vybít po vypnutí/úpravě noční automatizace, která ho dobíjela na 50 % (viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bod 6)
- [ ] **Nová položka**: kontrolovaně odlišit, jestli druhý pád do OFF (12.8.2026) způsobilo zapnutí balanceru samotné, nebo souběžné nabíjení přes "Keep batteries charged" na už nevyrovnaném packu na SOC 100 % — otestovat zapnutí Equalize při nulovém nabíjecím proudu.
- [ ] Přesné D-Bus cesty pro čtení cell voltages a zápis MaxChargeCurrent (viz [dbus-paths.md](dbus-paths.md)) — ověřit přes dbus-spy (nyní nižší priorita, appka dala potřebná data bez toho)
- [ ] **Nová položka**: ověřit, jestli Dolní jednotka byla 12.8.2026 v klidovém stavu (`System ready`, 0 A) kvůli duty-cyclingu nebo kvůli verzí-specifické nuanci RunVol/StopVol brány — viz [enerkey-balancer-mechanism.md](../docs/enerkey-balancer-mechanism.md).

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

