# Jak skutečně funguje Enerkey/NEEY balancer

Zjištěno v samostatné výzkumné konverzaci (Claude Desktop), zde shrnuto a provázáno se zbytkem repozitáře. Zdroje: oficiální manuál NEEY-electronic (NEEY-24S4EB, sdílená technologie s Enerkey) a diskuze na DIY Solar Forum o Neey/EnerKey/GeeWe balancerech.

## Mechanismus přenosu energie

- Balancer v jednu chvíli identifikuje **aktuálně nejvyšší a nejnižší článek v rámci jednoho 16S stringu** (jedna fyzická jednotka = jeden string — žádné křížení mezi Horní a Dolní, viz [system-overview.md](system-overview.md)).
- Nejvyšší článek se vybíjí do balanceru (uloží energii), tu pak balancer použije k dobití nejnižšího článku.
- Tohle je **sekvenční/párové** chování — balancer "honí" aktuálně nejhorší pár (max−min), **ne že by pracoval simultánně na všech článcích najednou**. Ostatní články s mírným (ne extrémním) rozptylem zůstávají nedotčené, dokud se nevyřeší ten nejhorší pár.

## Řídicí logika: dva odlišné mechanismy

1. **Trigger/Startup DifVol (delta-voltage)** — globální podmínka podle max−min rozdílu v celém stringu. Balancer začne pracovat, jakmile max delta překročí tuhle hodnotu, a zastaví se, jakmile klesne pod ni. Tohle je jediný parametr popsaný ve starším/oficiálním manuálu.
2. **RunVol/StopVol** (novější appka/firmware, nemusí být ve všech verzích) — dodatečná globální brána podle **průměrného/paketového napětí** (ne jednotlivého článku). I když je delta nad prahem, balancer nezačne pracovat, dokud není celkové napětí v okně RunVol–StopVol; když napětí vypadne z okna, práce se zastaví **jako celek, pro všechny články najednou**.

## Klíčová nevýhoda designu

- Pokud jeden článek "kazí průměr" nebo je extrémní hodnotou v delta výpočtu a zároveň leží mimo pracovní okno (RunVol–StopVol), **balancer se může zastavit pro celý string**, ne že by ten jeden problémový článek jen vynechal a pokračoval na ostatních.
- Protože se vždy honí jen aktuální nejhorší pár, u stringu s jedním výrazně vychýleným článkem se ostatní články s mírným rozptylem prakticky nedotknou, dokud se ten extrém nevyřeší.
- **Praktický důsledek pro nás**: RunVol/StopVol musí odpovídat reálnému provoznímu rozsahu našich článků (viz sjednocené nastavení 3,350 V / 3,180 V v [system-overview.md](system-overview.md)) — jinak riskujeme, že se balancer bude zbytečně vypínat mimo dobu, kdy je vyrovnávání nejvíc potřeba (typicky vrchol nabíjecí křivky, kde se rozdíly nejvíc projeví).

## Nejistoty / caveaty

- Chování se může lišit podle konkrétní verze HW/FW appky — komunitní zprávy hlásí nekonzistence (např. u jednoho uživatele nastavení delta-voltage prahu vůbec nezastavilo balancování, ani při rozdílu 0 mV).
- Oficiální (starší) manuál RunVol/StopVol vůbec nezmiňuje — jsou pravděpodobně přidané až v novější appce, což by vysvětlovalo tu nekonzistenci mezi uživateli.

## Relevance pro naše pozorování

- Možné (nepotvrzené) vysvětlení pro pozorování z 12.8.2026: Horní jednotka aktivně běžela (`EquRun`, 4,011 A), zatímco Dolní byla v klidu (`System ready`, 0,000 A) i přes DifVol 18 mV nad jejím Startup DifVol prahem 5 mV — mohlo jít o duty-cycling (dohnala už svůj nejhorší pár, čeká na další), nebo o verzí-specifickou nuanci RunVol/StopVol brány. Beze změny zůstává neprokázané, jen doplněný kontext — viz [checklist.md](../diagnostics/checklist.md).
- **Posiluje důvod pro navrženou externí Node-RED kontrolu** ([automation/node-red-control-logic.md](../automation/node-red-control-logic.md)), řízenou podle `MaxCellVoltage` napříč všemi články: pokud Enerkey přestane pracovat kvůli jednomu vychýlenému článku mimo okno, externí kontrola nabíjecího proudu podle skutečného max napětí zůstává funkční nezávisle na tom, jestli interní balancer zrovna běží.
