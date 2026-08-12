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

## Návaznost na jev "vybíjení jen do 47 %"

Pokud "sync na 100 %" proběhl v okamžiku, kdy jeden článek už byl na hraně OV a zbytek packu ne, je tenhle sync nepřesný — SOC pak neodpovídá realitě **oběma směry**, nejen nahoru. 47 % je pravděpodobně bod, kde **nejslabší (nejnižší) článek** narazil na svůj discharge cutoff v n-BMS, zatímco zbytek packu měl ještě rezervu — SOC ale reportuje odhad za celý pack, ne stav nejhoršího článku.

➡️ Důsledek pro řešení: **nejde primárně o "kalibraci nuly" izolovaně** — dokud je pack takhle nevybalancovaný, je jakákoliv kalibrace SOC nespolehlivá, protože horní i dolní mez určuje nejvíc vychýlený článek, ne průměr packu. Nejdřív rebalance, pak kalibrace — viz [rebalancing-procedure.md](rebalancing-procedure.md).
