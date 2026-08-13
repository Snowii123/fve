# Doporučený postup: rebalance a bezpečná kalibrace horní/dolní meze

Cíl: dostat pack na rozumnou úroveň vyrovnání článků, a teprve pak nechat proběhnout čistý "full charge sync" a zjistit reálný dolní bod (empty). Postup je odvozený, **zatím neověřený/neprovedený na systému** — viz [checklist](../diagnostics/checklist.md).

## 0. Diagnostika před zásahem

- Zjistit aktuální **cell voltage spread** živě (dbus-spy / Node-RED) — je pořád ~270 mV, nebo se změnil?
- V n-BMS zkontrolovat log **CCL/DCL** v okamžiku minulého pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe).
- Zjistit **discharge cutoff napětí na článek** nastavené v n-BMS a porovnat ho s napětím nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %.

## 1. Sjednotit nastavení obou Enerkey balancerů

**Hotovo (12.8.2026).** Obě jednotky sjednoceny a Equalize zapnuto — viz [system-overview.md](system-overview.md#bms-a-balancing) (RunVol **3,350 V** / StopVol **3,180 V** / Startup DifVol 0,005 V / Max EquCur 4,0 A na obou; hodnoty převzaté z původní Dolní jednotky, ne z dřívějšího návrhu 3,400 V/3,300 V). OV threshold v n-BMS mezitím přímo potvrzen: `Info/MaxChargeVoltage` = **3,5625 V/článek** (57,0 V pack) — viz [dbus-paths.md](../diagnostics/dbus-paths.md).

## 2. Rebalance packu (předpoklad pro cokoliv dalšího)

- Držet pack **24–48+ hodin** těsně pod (nově sjednoceným) aktivačním prahem Enerkey balanceru — **3,350 V/článek**.
- Sledovat spread živě po celou dobu, na obou stringech zvlášť.
- Pokračovat dál až po poklesu spreadu na cílovou hodnotu (orientačně < 20–30 mV) — na **obou** stringech, ne jen v průměru.
- **Aktualizace (12.-13.8.2026): tenhle krok proběhl a fungoval.** Spread klesl 270 mV → 82 mV → ~33 mV → opakovaně 2-3 mV při klidném běhu s proudovým omezením (viz [fronius/README.md](../fronius/README.md)). Kroky 2-3 tady popsané se v praxi prolnuly s živým řešením nestability nabíjecího proudu, ne jako čistě oddělená fáze.

## 3. Pomalé dojetí na skutečných 100 %

- Nabíjecí proud snížit na výrazně nižší hodnotu než běžný (řádově C/100–C/200, např. ~2 A na 400 Ah pack).
- Nízký proud primárně pomáhá tím, že snižuje rozdíly v napětí způsobené vnitřním odporem jednotlivých článků (IR drop) — čím nižší proud, tím míň se rozjezd napětí uměle zveličuje.
- Sledovat napětí **nejvyššího** článku vůči `Info/MaxChargeVoltage` = **3,5625 V/článek** (potvrzeno přímo z n-BMS, viz [dbus-paths.md](../diagnostics/dbus-paths.md)) — pokud se blíží, snížit proud dál nebo pozastavit nabíjení. Počítat i s tím, že n-BMS reaguje na vlastní alarm s odstupem až ~2 s (viz [fronius/README.md](../fronius/README.md)), takže "blíží se" znamená přiměřenou rezervu, ne čekání na poslední chvíli.
- Řídicí kritérium: **napětí nejvyššího článku**, ne SOC ani celkové napětí packu (viz [soc-calibration.md](soc-calibration.md)).
- Teprve když je pack vyrovnaný a dosáhne charged voltage s nízkým tail proudem **bez** toho, aby jeden článek narazil na OV práh, je to bezpečný moment pro "full charge sync". Ověřit v n-BMS, že se sync skutečně zaznamenal.

## 4. Kalibrace dolního konce

- Reálnou zátěží vybíjet pack, sledovat spread znovu — spodní část LFP křivky je taky dost plochá a pak prudce spadne, takže nevybalancovaný pack narazí nejnižším článkem na cutoff dřív.
- Zastavit těsně nad nastaveným discharge cutoffem.
- Pokud n-BMS podporuje explicitní "empty sync", provést ho v tomto bodě.

## 5. Dlouhodobě

- Nedělat top-charge jen jednou za půl roku — **kratší pravidelné cykly** udrží balancer v provozu průběžně a zabrání opakování stejného driftu.
- Nahradit tenhle manuální postup trvalou automatizací — viz [automation/node-red-control-logic.md](../automation/node-red-control-logic.md).
