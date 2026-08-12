# Fronius / battery power mismatch

**Status: problém je popsaný a kvantifikovaný z oficiálních zdrojů, návrh řešení je nastřelený (viz níže), ale nic z toho zatím není implementované/ověřené na systému.** Řeší se záměrně odděleně od kalibrace SOC/rebalance baterie (viz [`../docs`](../docs)) — jsou to provázané, ale odlišné problémy s odlišným řešením.

## Oprava předchozí verze

Předchozí verze tohoto dokumentu tvrdila, že "battery pack bezpečně zvládá jen ~12,5 kW". To byla chyba — **12,5 kWp je aktuálně instalovaný výkon FV panelů** na Froniovi (který má inverter dimenzovaný na 17,5 kW, ale zatím není osazený na plný výkon), ne nějaká vlastnost battery packu. Kolik battery pack reálně bezpečně zvládá, je jiná otázka — zodpovězená níže pomocí dohledaných zdrojů.

## Kvantifikace mismatche (ze zdrojů)

### Podle oficiální Victron sizing guidance

Victron oficiálně doporučuje pro **lithiové baterie cca 4,8 kWh kapacity na 1,5 kWp instalovaného PV výkonu** ([Factor 1.0 rule, victronenergy.com](https://www.victronenergy.com/live/ac_coupling:start)) — tedy **~3,2 kWh baterie na 1 kWp PV**.

| | Instalováno dnes (12,5 kWp) | Plný výkon Fronia (17,5 kWp) |
|---|---|---|
| Doporučená kapacita baterie (Victron) | ~40 kWh | ~56 kWh |
| Náš pack (~400 Ah, ~20,5 kWh nominálně, ~15 kWh využitelně — viz [system-overview.md](../docs/system-overview.md)) | **~50 % doporučení** | **~37 % doporučení** |

Tedy i při současném (nedoplněném) osazení panelů je battery pack zhruba **poloviční** oproti tomu, co Victron sám doporučuje pro lithiové baterie u AC-coupled systému. Pokud by se Fronius v budoucnu doplnil na plný výkon 17,5 kWp, byl by pack na necelé třetině doporučení.

### Křížová kontrola přes C-rate

Nezávisle od výše: běžné pravidlo palce pro nabíjecí proud lithiových baterií je **C2 (0,5C)** — u DC-coupled MPPT to udává přímo Victron ([tamtéž](https://www.victronenergy.com/live/ac_coupling:start)), stejná hodnota (0,5C kontinuální) je i běžné konzervativní doporučení výrobců velkoformátových LFP článků pro zachování životnosti (např. [EVE MB31 datasheet](https://www.18650batterystore.com/products/eve-mb31-grade-a-cells-3-2v-lifepo4-314ah-battery) testuje cyklickou životnost právě na 0,5C).

Pro náš ~400 Ah pack: **0,5C = 200 A** → při 16S LFP (nominál ~51,2 V, absorpce až ~58,4 V) to je zhruba **~10,2–11,7 kW** kontinuálního nabíjecího/vybíjecího výkonu.

➡️ To je **méně, než kolik dnes umí dodat i jen aktuálně instalovaných 12,5 kWp panelů** za jasného počasí — natožpak špička při skokové změně ozáření. Pack je tedy strukturálně poddimenzovaný vůči tomu, co na něj Fronius (i v současném, nedoplněném stavu) může poslat, nejde jen o vyladění regulační smyčky.

**Pozn.:** 0,5C je generický konzervativní odhad z veřejně dostupných zdrojů, ne datasheet konkrétních článků použitých v tomto packu — pokud je známý přesný model článků, stojí za to dohledat jejich vlastní doporučenou C-rate a čísla zpřesnit.

### Fronius vs. Multiplusy (Factor 1.0) — pro srovnání, tohle není problém

Podle oficiálního Victron pravidla "Factor 1.0" nesmí AC-coupled PV výkon překročit VA výkon střídače/nabíječe. 6× MultiPlus-II 48/3000/35-32 = 6 × 3000 VA = **18 kVA** kombinovaně. Fronius 17,5 kW proti tomu **vyhovuje** (s malou rezervou), takže tahle konkrétní vazba není zdrojem problému — problém je specificky battery pack vs. PV výkon, ne Fronius vs. Multiplusy.

## Proč nastavený limit 2 A občas neplatí — možné vysvětlení z Victron komunity

Dohledané [komunitní vlákno](https://communityarchive.victronenergy.com/questions/229281/ess-and-dvcc-ignore-the-settings.html) popisuje zdokumentované omezení: **DVCC charge current limit se neaplikuje na DC-coupled MPPT, když je v ESS zapnuté "Allow DC MPPT to export"** — systém prioritizuje maximální export/využití solárního výkonu před dodržením nastaveného limitu.

U nás je Fronius **AC-coupled**, ne DC MPPT, takže tahle konkrétní výjimka pravděpodobně přímo neplatí — ale stojí za to **zkontrolovat ESS nastavení, jestli tam není analogická volba** (něco jako "feed-in excess"/"maximize export"), která by mohla mít podobný efekt i pro AC-coupled zdroj. V každém případě to potvrzuje obecný vzorec: DVCC limity mají u Victronu víc výjimek/edge-casů, než by se čekalo — v kombinaci se strukturálním mismatchem výše je fronta příčin pravděpodobně: (1) pack je objektivně poddimenzovaný, (2) frequency-shift regulační smyčka má setrvačnost, (3) možná ještě nějaká ESS volba prioritizující export nad limitem.

## Návrh řešení: buffer řízený napětím článků, ne SOC

Uživatelský návrh: nechat v battery packu trvalý buffer/rezervu, kterou pravidelně (příležitostně) rekalibrujeme, a **řídit velikost bufferu podle napětí článků, ne podle SOC** (jak se to dělalo dosud přes 96% cap).

**Je to dobrý nápad — ano, jednoznačně lepší než SOC.** Důvody:

1. **SOC je nespolehlivý** (viz [soc-calibration.md](../docs/soc-calibration.md)) — to je přesně to, co celý incident způsobilo. Stavět bezpečnostní buffer na nespolehlivé veličině je křehké už z principu.
2. **Napětí článku je přesně ta veličina, na kterou reaguje i samotná OV ochrana v n-BMS** — buffer řízený napětím tedy "mluví stejným jazykem" jako ochrana, kterou se snaží předejít. Žádný převod přes nejistý SOC výpočet.
3. **Napětí pod zátěží už v sobě zahrnuje IR drop ze skokového proudu** — to je vlastně žádoucí vlastnost: při proudové špičce napětí na svorkách přirozeně vyskočí výš, než odpovídá skutečnému SOC, takže buffer řízený napětím se **automaticky víc "stáhne" právě v okamžiku, kdy je to nejvíc potřeba** (při špičce), zatímco SOC-based buffer o probíhající špičce vůbec neví.

**Na co si dát pozor:**
- Musí to být **MaxCellVoltage napříč oběma stringy** (32 článků), ne průměr ani napětí packu — jinak se opakuje přesně ta chyba, co způsobila původní incident (jeden vychýlený článek se schová v průměru).
- **Rychlost reakce**: vzhledem ke strukturálnímu mismatchu výše (panely fyzicky můžou poslat víc výkonu, než pack snese, i bez závady) nemusí být softwarová smyčka (Node-RED v cyklu 30-60 s, nebo i DVCC frequency-shift) dost rychlá na nejrychlejší přechody (hrana mraku může proběhnout v řádu sekund). Buffer proto musí mít **fyzickou rezervu dostatečnou i bez spoléhání na to, že software zareaguje včas** — ne jen "reaktivní brzdu", ale statickou mez s marží. Tuhle marži je potřeba nastavit podle reálně naměřeného chování špičky (viz diagnostika níže), ne odhadem.

### Konkrétní návrh implementace

1. **Definovat `V_buffer_ceiling`** (per-cell, na obou stringech) — trvalý provozní strop na `MaxCellVoltage`, nastavený s marží pod OV warning threshold v n-BMS (zatím neznámý, viz [checklist](../diagnostics/checklist.md)). Marže musí pokrýt reálně naměřenou napěťovou výchylku během špičky (bod 2 níže), ne jen odhad.
2. **Diagnostika před nastavením konkrétního čísla**: zachytit přes Node-RED/dbus-spy `MaxCellVoltage` v okamžiku, kdy nastane proudová špička (2 A → ~30 A) — kolik mV skutečně vyskočí a jak rychle se vrátí zpět. Bez týhle naměřené hodnoty je `V_buffer_ceiling` jen odhad.
3. **Znovupoužít architekturu z [automation/node-red-control-logic.md](../automation/node-red-control-logic.md)** — stejný princip (brzdění podle `MaxCellVoltage`) navržený pro rebalanci lze rozšířit na trvalý provozní režim: jakmile se `MaxCellVoltage` přiblíží `V_buffer_ceiling`, omezit/pozastavit nabíjení bez ohledu na SOC. Rozdíl oproti rebalanční fázi: tohle běží **trvale**, ne jen během řízené kalibrace, takže potřebuje být odladěné na běžný provoz, ne jen na pomalé řízené nabíjení.
4. **Zvážit lokální reakci přímo v n-BMS** (pokud to podporuje) — smyčka Node-RED → DVCC → Fronius má nevyhnutelně dopravní zpoždění (round-trip přes GX). Pokud n-BMS umí měkké průběžné omezování proudu (ne jen binární CCL=0 při dosažení hard limitu), reaguje lokálně rychleji než cokoliv přes síť. Ověřit jako součást stejné položky v checklistu o OV warning threshold.
5. **Periodická kalibrace zůstává** — přesně jak navrhujete: buffer omezuje běžný denní provoz, ale pravidelně (podle uvážení, např. jednou za pár týdnů/měsíců) se buffer záměrně uvolní a provede se řízený plný cyklus podle [rebalancing-procedure.md](../docs/rebalancing-procedure.md), aby se udržela kalibrace a balancer měl šanci dotáhnout zbytkovou nerovnováhu na obou stringech. Mimo tyhle kalibrační okna zůstává SOC čistě informativní, nikdy není řídicí veličinou — ani pro rebalanci, ani teď pro buffer.

**Kompromis, se kterým je potřeba počítat**: konzervativně nastavený `V_buffer_ceiling` znamená trvale nevyužitou část kapacity packu (bezpečnost na úkor kapacity každý den). Vzhledem ke strukturálnímu mismatchu výše je to pravděpodobně správný kompromis, dokud se neřeší mismatch samotný (větší pack, nebo tvrdší omezení PV strany).

## Proč se řeší odděleně od kalibrace baterie

| | Battery kalibrace (aktivní práce) | Fronius mismatch (odloženo) |
|---|---|---|
| Co se opravuje | Nastavení balancerů, SOC sync, rebalance packu | Skoková PV výkonová špička na DC straně |
| Kde | Enerkey appka, n-BMS, ruční postup | DVCC/frequency-shift regulace, případně vlastní curtailment |
| Vlastník řešení | Software/nastavení na úrovni balanceru a BMS | Řízení výkonové špičky, pravděpodobně přes Node-RED |
| Stav | Řeší se teď — viz [`../docs`](../docs) | Popsáno a nastřeleno, implementace až po dokončení battery kalibrace |

## Otevřené otázky / k ověření

- [ ] Zachytit `MaxCellVoltage` (obou stringů) v okamžiku reálné proudové špičky (2 A → ~30 A) — jak vysoko vyskočí a jak rychle relaxuje. Klíčové pro nastavení `V_buffer_ceiling`.
- [ ] Logovat výkon Fronia (PV output) společně s nabíjecím proudem a nastaveným limitem — potvrdit, že špičky časově korelují se skokovými změnami PV výkonu.
- [ ] Zkontrolovat ESS nastavení, jestli neobsahuje analogii k "Allow DC MPPT to export" pro AC-coupled zdroj (feed-in excess / maximize export).
- [ ] Ověřit, jestli n-BMS podporuje měkké průběžné omezování proudu (rychlejší lokální reakce) místo jen binárního CCL cutoff.
- [ ] Pokud je známý přesný model použitých LFP článků, dohledat jejich vlastní doporučenou C-rate a zpřesnit odhad ~10-12 kW výše.
- [ ] Dlouhodobě zvážit rozšíření battery packu jako strukturální řešení mismatche (mimo scope softwarové opravy).

## Návaznost

Jakmile bude battery kalibrace ([`../docs/rebalancing-procedure.md`](../docs/rebalancing-procedure.md)) dokončená a pack vybalancovaný, dává smysl implementovat návrh výše — ideálně jako rozšíření stejné Node-RED automatizace, co vzniká pro battery stranu ([`../automation/node-red-control-logic.md`](../automation/node-red-control-logic.md)).

## Zdroje

- [AC-coupling and the Factor 1.0 rule — Victron Energy](https://www.victronenergy.com/live/ac_coupling:start)
- [ESS and DVCC ignoring max charge current setting — Victron Community](https://communityarchive.victronenergy.com/questions/229281/ess-and-dvcc-ignore-the-settings.html)
- [EVE MB31 314Ah LiFePO4 datasheet — 18650batterystore.com](https://www.18650batterystore.com/products/eve-mb31-grade-a-cells-3-2v-lifepo4-314ah-battery)
