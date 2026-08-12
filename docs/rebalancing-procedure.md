# Doporučený postup: rebalance a bezpečná kalibrace horní/dolní meze

Cíl: dostat pack na rozumnou úroveň vyrovnání článků, a teprve pak nechat proběhnout čistý "full charge sync" a zjistit reálný dolní bod (empty). Postup je odvozený, **zatím neověřený/neprovedený na systému** — viz [checklist](../diagnostics/checklist.md).

## 0. Diagnostika před zásahem

- Zjistit aktuální **cell voltage spread** živě (dbus-spy / Node-RED) — je pořád ~270 mV, nebo se změnil?
- V n-BMS zkontrolovat log **CCL/DCL** v okamžiku minulého pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe).
- Zjistit **discharge cutoff napětí na článek** nastavené v n-BMS a porovnat ho s napětím nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %.

## 1. Rebalance packu (předpoklad pro cokoliv dalšího)

- Držet pack **24–48+ hodin** těsně pod aktivačním prahem Enerkey balanceru (odhad ~3,40–3,45 V/článek, ověřit v datasheetu).
- Sledovat spread živě po celou dobu.
- Pokračovat dál až po poklesu spreadu na cílovou hodnotu (orientačně < 20–30 mV).

## 2. Pomalé dojetí na skutečných 100 %

- Nabíjecí proud snížit na výrazně nižší hodnotu než běžný (řádově C/100–C/200, např. ~2 A na 400 Ah pack).
- Nízký proud primárně pomáhá tím, že snižuje rozdíly v napětí způsobené vnitřním odporem jednotlivých článků (IR drop) — čím nižší proud, tím míň se rozjezd napětí uměle zveličuje.
- Sledovat napětí **nejvyššího** článku vůči OV warning prahu v n-BMS (měkký práh, ne tvrdý disconnect) — pokud se blíží, snížit proud dál nebo pozastavit nabíjení.
- Řídicí kritérium: **napětí nejvyššího článku**, ne SOC ani celkové napětí packu (viz [soc-calibration.md](soc-calibration.md)).
- Teprve když je pack vyrovnaný a dosáhne charged voltage s nízkým tail proudem **bez** toho, aby jeden článek narazil na OV práh, je to bezpečný moment pro "full charge sync". Ověřit v n-BMS, že se sync skutečně zaznamenal.

## 3. Kalibrace dolního konce

- Reálnou zátěží vybíjet pack, sledovat spread znovu — spodní část LFP křivky je taky dost plochá a pak prudce spadne, takže nevybalancovaný pack narazí nejnižším článkem na cutoff dřív.
- Zastavit těsně nad nastaveným discharge cutoffem.
- Pokud n-BMS podporuje explicitní "empty sync", provést ho v tomto bodě.

## 4. Dlouhodobě

- Nedělat top-charge jen jednou za půl roku — **kratší pravidelné cykly** udrží balancer v provozu průběžně a zabrání opakování stejného driftu.
- Nahradit tenhle manuální postup trvalou automatizací — viz [automation/node-red-control-logic.md](../automation/node-red-control-logic.md).
