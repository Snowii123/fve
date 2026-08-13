# Incident: DVCC shutdown po pokusu o kalibraci SOC

## Chronologie

1. **Dlouhodobý stav před incidentem** — Node-RED automatizace bránila nabití baterie nad **96 % SOC**, jako ochrana podkapacitního packu. Automatizace běžela v tomto režimu cca **půl roku**.
2. **Důsledek** — SOC kalibrace za tu dobu zdriftovala: baterie ukazovala **77 %**, ale reálně už nešla dál **vybít** (skutečný stav packu neodpovídal zobrazenému SOC — reálná využitelná kapacita byla nižší, než 77 % naznačovalo).
3. Uživatel automatizaci **vypnul** a nechal baterii ručně dobít na **100 %**.
4. Baterie při tom **chvíli přestala brát proud**; po chvíli se nabíjení znovu rozjelo.
5. Celý Victron systém (Multiplusy) se **sám přehodil z režimu On do Off**. Ve VRM/alertech nebylo vidět nic, co by to přímo vysvětlovalo.
6. Nová informace zjištěná následně — při provozu čistě na baterii (bez dobíjení) se pack vybije **jen do 47 % SOC**, než systém začne brát proud ze sítě.
   - ESS **Minimum SOC = 20 %** — ověřeno uživatelem, **vyloučeno jako příčina** (nevysvětluje odpojení už při 47 %).
   - **Aktuální hypotéza (neověřeno, plánuje se retest):** jev je nejspíš způsobený samostatnou **noční nabíjecí automatizací**, která baterii pravidelně dobíjí zpět na 50 % — tedy pack v praxi nikdy nedostane šanci klesnout níž, protože ho automatizace v noci "podchytí" dřív, ne že by 47 % byl skutečný fyzický limit. Až se tahle automatizace vypne/upraví, plánuje se znovu zkusit, jak nízko lze pack reálně vybít.
   - **Částečný retest (13.8.2026):** přes noc vybíjení na běžnou zátěž (bez vynucování), přechod na síť **vůbec nenastal**. Nejníž packy klesly na **3,20 V / 3,26 V** (jednotlivé stringy) při SOC ~58 % dle VRM — hluboko v plochém plató LFP křivky, žádný náznak rizika. Ráno bylo dobíjení ručně obnoveno (Fronius), takže test nedošel ke skutečnému dnu — otázka "kde je reálná nula" zůstává otevřená, ale **dolní konec se jeví jako výrazně méně naléhavý problém než horní** (žádný OV-like incident, žádný nucený přechod na síť, komfortní napětí). Priorita zůstává na kalibraci/bezpečnosti horního konce.

## Hypotéza příčiny (neověřeno přímým měřením — viz [checklist](../diagnostics/checklist.md))

**DVCC fail-safe kvůli extrémní nerovnováze článků.**

- Uživatel potvrdil rozjezd napětí mezi články (cell voltage spread) až **270 mV** — u LFP je horní část nabíjecí křivky strmá, takže i menší nerovnováha v Ah se u vrcholu projeví jako velký rozdíl v napětí.
- Při dobíjení na 100 % pravděpodobně **nejvyšší článek narazil na OV (overvoltage) protection threshold v n-BMS dřív** než zbytek packu.
- n-BMS na to zareagoval odesláním **CCL = 0 a DCL = 0** současně (nulový povolený nabíjecí i vybíjecí proud).
- Venus OS / DVCC to vyhodnotilo jako **korektní ochrannou reakci na povel BMS** (ne jako chybu) a shodilo celý systém do OFF — proto nic v klasických alertech.

**Proč se pack takhle rozjel: Enerkey balancer pravděpodobně nikdy nepracoval.**

- Enerkey (aktivní balancer, samostatná jednotka pro každý ze 2 stringů — viz [system-overview.md](system-overview.md)) má ověřené aktivační napětí **3,480 V** na "Horním" stringu a **3,350 V** na "Dolním" stringu — výrazná asymetrie.
- Dokud automatizace držela pack pod 96 % SOC, pack se pravděpodobně **nikdy nedostal do napěťového okna**, kde balancer vůbec začíná pracovat — obzvlášť na Horním stringu, kde je aktivační práh 3,48 V nastavený hodně blízko vrcholu nabíjecí křivky.
- Výsledek: **6 měsíců balancer prakticky nedělal nic** a rozjezd 270 mV se tiše nabaloval, aniž by to bylo někde vidět (SOC ukazoval zdánlivě rozumná čísla).
- **Doplňující hypotéza**: i po skončení 96% capu má Horní string balancer nastavený s max. vyrovnávacím proudem jen **0,5 A** (8× méně než Dolní s 4 A) a aktivuje se později — takže i kdyby pracoval, vyrovnává rozjezd mnohem pomaleji. Pokud incident vznikl na Horním stringu, je tohle pravděpodobně dodatečný přispívající faktor, ne jen historie s 96% capem.

## Aktualizace (12.8.2026): Equalize switch byl vypnutý — pravděpodobná skutečná hlavní příčina

Při kontrole appky se zjistilo, že **Equalize switch nebyl zapnutý na žádné z jednotek**. Bez ohledu na nastavené RunVol/StopVol/Max EquCur balancery **vůbec neběžely, po celou dobu**. To je fundamentálnější vysvětlení 270 mV rozjezdu než asymetrie nastavení popsaná výše (ta zůstává platná jako reálné zjištění, ale byla irelevantní, dokud byl hlavní přepínač vypnutý — ani jedna jednotka nikdy neběžela).

**Sled událostí při nápravě:**

1. Systém byl v mezičase v ESS režimu **"Keep batteries charged"** (limit 2 A), SOC ukazoval 100 %. Nabíjecí proud i s Froniem fyzicky odpojeným na jističi kolísal 3–4,5 A, občas až 19 A — potvrzuje, že problém s nedodržováním limitu **není specifický jen pro AC-coupled PV** (viz aktualizovaná hypotéza ve [fronius/README.md](../fronius/README.md)).
2. Po prvním zapnutí Equalize switche došlo **znovu k pádu Victronu do OFF**. Pravděpodobně shoda okolností — pack na SOC 100 %, nikdy nevyrovnávaný, pokračující nabíjení přes "Keep batteries charged" ho pravděpodobně dotlačilo přes hranici — ne přímý důsledek balanceru samotného. Nebylo kontrolovaně odlišeno (test "balancer bez nabíjení" se neprováděl).
3. Náprava: ESS přepnuto na **Optimized without BatteryLife** → pack se začal vybíjet (bezpečný směr, pryč od hrany). Obě jednotky sjednoceny na **RunVol 3,350 V / StopVol 3,180 V / Startup DifVol 0,005 V / Max EquCur 4,0 A** (hodnoty převzaté z původní Dolní jednotky). Equalize znovu zapnuto na obou, tentokrát při klesajícím napětí.
4. Výsledek — pack-wide spread rychle klesá: **270 mV** (incident) → **82 mV** (SOC 100 %, obě extrémy v jednom stringu, balancer ještě vypnutý) → **~33 mV** (aktuální stav, oba balancery aktivní — Horní DifVol 31 mV ve stavu `EquRun` s 4,011 A, Dolní DifVol 18 mV). Viz tabulka měření v [checklistu](../diagnostics/checklist.md).

## Návaznost na jev "vybíjení jen do 47 %"

Pokud "sync na 100 %" proběhl v okamžiku, kdy jeden článek už byl na hraně OV a zbytek packu ne, je tenhle sync nepřesný — SOC pak neodpovídá realitě **oběma směry**, nejen nahoru. 47 % je pravděpodobně bod, kde **nejslabší (nejnižší) článek** narazil na svůj discharge cutoff v n-BMS, zatímco zbytek packu měl ještě rezervu — SOC ale reportuje odhad za celý pack, ne stav nejhoršího článku.

➡️ Důsledek pro řešení: **nejde primárně o "kalibraci nuly" izolovaně** — dokud je pack takhle nevybalancovaný, je jakákoliv kalibrace SOC nespolehlivá, protože horní i dolní mez určuje nejvíc vychýlený článek, ne průměr packu. Nejdřív rebalance, pak kalibrace — viz [rebalancing-procedure.md](rebalancing-procedure.md).
