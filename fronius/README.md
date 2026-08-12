# Fronius / battery power mismatch

**Status: problém je popsaný a je jasná jeho souvislost s battery kalibrací (viz [`../docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md)), ale řešení zatím není navrženo ani implementováno.** Řeší se záměrně odděleně od kalibrace SOC/rebalance baterie (viz [`../docs`](../docs)) — jsou to provázané, ale odlišné problémy s odlišným řešením.

## Problém

- **Fronius Symo 17,5 kW** (AC-coupled) je výrazně předimenzovaný vůči battery packu, který bezpečně zvládá jen řádově **~12,5 kW** nabíjecího/vybíjecího výkonu (pack ~400 Ah, homemade LFP — viz [`../docs/system-overview.md`](../docs/system-overview.md)). Fronius tedy nikdy neběží na svůj plný výkon — je omezen packem.
- I tak ale při **rychlých změnách slunečního záření** (typicky hrana mraku, prudké projasnění) může regulace AC-coupled přebytku — řízená přes DVCC pomocí frequency-shift power control (posun síťové frekvence na výstupu Multiplusů, na který Fronius reaguje omezením výkonu) — krátkodobě zaostat za skutečností. Pozorováno konkrétně: nastavený limit nabíjecího proudu **2 A** byl reálně občas překročen až na **~30 A**.
- Tenhle mismatch je pravděpodobně přímo provázaný s [hlavním battery incidentem](../docs/incident-dvcc-shutdown.md): **96% cap byla nejspíš improvizovaná obrana právě proti tomuhle jevu.** Držením SOC pod 96 % zůstávala rezerva, takže i kdyby proudová špička krátkodobě přestřelila, nejvyšší článek nedosáhl OV prahu v n-BMS. Jakmile SOC šel na 100 %, žádná rezerva už nebyla — špička narazila na OV a systém spadl do OFF (stejné chování/hláška jako při běžném pokusu o dobití na 100 %).

## Proč se řeší odděleně od kalibrace baterie

| | Battery kalibrace (aktivní práce) | Fronius mismatch (odloženo) |
|---|---|---|
| Co se opravuje | Nastavení balancerů, SOC sync, rebalance packu | Skoková PV výkonová špička na DC straně |
| Kde | Enerkey appka, n-BMS, ruční postup | DVCC/frequency-shift regulace, případně vlastní curtailment |
| Vlastník řešení | Software/nastavení na úrovni balanceru a BMS | Řízení výkonové špičky, pravděpodobně přes Node-RED |
| Stav | Řeší se teď — viz [`../docs`](../docs) | Řeší se až po dokončení battery kalibrace |

## Otevřené otázky / možná řešení (nerozpracováno)

- Logovat výkon Fronia (PV output) společně s nabíjecím proudem a nastaveným limitem přes Node-RED — potvrdit/vyvrátit, že špičky na ~30 A časově korelují se skokovými změnami PV výkonu.
- Zavést v Node-RED vlastní, rychlejší reakci na PV výkonové špičky než defaultní DVCC frequency-shift smyčka — např. reagovat na rychlost změny výkonu (derivaci), ne jen na aktuální hodnotu, nebo na predikci z irradiance dat.
- Prověřit, jestli Venus OS/DVCC nabízí agresivnější nebo rychlejší curtailment nastavení než výchozí.
- Ověřit, jestli DVCC limit skutečně reguluje všechny cesty, kterými proud do packu teče (AC-coupled Fronius přes Multiplusy), nebo jen některé.
- Dlouhodobě zvážit rozšíření battery packu (větší kapacita = větší absorpční schopnost špiček) — mimo scope softwarové opravy, jen jako možnost do budoucna.

## Návaznost

Jakmile bude battery kalibrace ([`../docs/rebalancing-procedure.md`](../docs/rebalancing-procedure.md)) dokončená a pack vybalancovaný, dává smysl řešit tohle jako další krok — ideálně taky formou trvalé Node-RED automatizace na Cerbu, podobně jako [`../automation/node-red-control-logic.md`](../automation/node-red-control-logic.md) pro battery stranu.
