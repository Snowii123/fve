# Návrh: trvalá automatizace řízení nabíjecího proudu podle napětí článků

Cíl: nahradit manuální/jednorázový postup z [rebalancing-procedure.md](../docs/rebalancing-procedure.md) trvalou closed-loop automatizací běžící přímo na Cerbu, řízenou podle **napětí článků a vlastních alarmů BMS**, ne podle SOC (viz [soc-calibration.md](../docs/soc-calibration.md) pro zdůvodnění).

**Proč tahle externí kontrola nemá nahrazovat samotný Enerkey balancer, ale doplňovat ho**: podle [enerkey-balancer-mechanism.md](../docs/enerkey-balancer-mechanism.md) může Enerkey přestat pracovat pro celý string, pokud jeden článek leží mimo jeho RunVol–StopVol okno — externí kontrola nabíjecího proudu podle skutečného `MaxCellVoltage` napříč všemi články zůstává funkční nezávisle na tom, jestli interní balancer zrovna běží.

**Status: návrh, zatím neimplementováno.** Aktualizováno 13.8.2026 podle celodenní diagnostické session — viz [checklist](../diagnostics/checklist.md) a [fronius/README.md](../fronius/README.md) pro zdrojová data.

## Co číst

Battery data přes **jeden dotaz na kořenovou cestu `/`** battery service (`GetValue`), ne přes desítky jednotlivých cest — ověřeno v [`poll-cerbo.sh`](../diagnostics/scripts/poll-cerbo.sh), je to jednodušší i rychlejší, a je to jediný spolehlivý způsob, jak dostat `Alarms/*` pole na tomhle konkrétním driveru (`can-bus-bms`, fyzicky Seplos — viz [dbus-paths.md](../diagnostics/dbus-paths.md)). V Node-RED to znamená jeden `dbus-listener`/Function uzel čtoucí celý slovník najednou, ne 15+ samostatných subscriptions.

| Pole (z root dumpu) | Účel |
|---|---|
| `System/MaxCellVoltage` | napětí nejvyššího článku napříč celým packem (oba stringy) — hlavní preventivní řídicí veličina |
| `System/MinCellVoltage` | napětí nejnižšího článku — spolu s Max určuje spread |
| `System/MaxVoltageCellId` | který "Pack" (string) je aktuálně nejvyšší — jen na úrovni stringu, ne konkrétního článku (viz [dbus-paths.md](../diagnostics/dbus-paths.md)) |
| `Info/MaxChargeCurrent` | CCL — co BMS momentálně sám povoluje. **Oprava**: dřívější verze tohoto dokumentu uváděla špatnou cestu `Info/ChargeCurrentLimit` |
| `Info/MaxChargeVoltage` | **57,0 V / 3,5625 V na článek** — BMS-udávaný cíl nabíjení, náš praktický strop (`V_ceiling` níže) |
| `Info/BatteryLowVoltage` | **46,4 V / 2,9 V na článek** — BMS-udávaná dolní mez |
| `Alarms/ChargeBlocked`, `Alarms/HighCellVoltage`, `Alarms/CellImbalance` | **nejrychlejší a nejspolehlivější signál** — viz níže, proč mají prioritu před vlastním přepočtem z napětí |
| `com.victronenergy.vebus.<id>/State` | 0=Off, 2=Fault — přímé zachycení pádu do OFF, bez nutnosti odvozovat to z poklesu proudu/napětí |
| `Soc` | jen pro logování/kontext, **ne** pro řízení — dnes znovu potvrzeno jako nespolehlivé (viz [fronius/README.md](../fronius/README.md#soc100--byl-falešný--pack-nebyl-skutečně-plný-1382026-1516-1518-utc)) |

## Prahy (aktualizováno 13.8.2026 — reálná, ověřená čísla, ne odhady)

| Práh | Hodnota | Status |
|---|---|---|
| `V_bal` (RunVol, obě Enerkey jednotky) | **3,350 V** | **Aplikováno a ověřeno** (12.-13.8.2026) — opakovaně dosažen rozjezd 2-3 mV. Nahrazuje dřívější neaplikovaný návrh 3,400 V. |
| `V_ceiling` (= `Info/MaxChargeVoltage`) | **3,5625 V** | **Potvrzeno přímo z BMS** 13.8.2026. Nahrazuje dřívější "neověřený V_warn". Nuance: je to BMS-udávaný cíl, ne nutně doslovný hard-trip bod, ale prakticky ekvivalentní — viz [fronius/README.md](../fronius/README.md#aktualizace-1382026-v_hard-už-není-odhad). |
| `V_floor` (= `Info/BatteryLowVoltage`) | **2,9 V** | **Potvrzeno přímo z BMS** 13.8.2026 — pro dolní konec, zatím nepoužito v state machine níže (dolní konec je zatím nižší priorita, viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md)). |
| `spread_target` | 20-30 mV | cíl "dost vybalancováno" — dnes reálně dosažitelné až na 2 mV při klidu |
| `spread_trigger` | **~100 mV** | nový, nezávislý spouštěč na zpomalení — viz "Provizorní bezpečnostní tabulka" ve [fronius/README.md](../fronius/README.md#provizorní-bezpečnostní-tabulka-k-okamžitému-ručnímu-použití) |

## Kritické zjištění: BMS má vlastní reakci s ~2s zpožděním — proto se nedá spoléhat jen na výpočet z napětí

Dnes (13.8.2026) zachyceno živě: `alarm_high_cell_voltage` naskočil, CCL ale **ještě jeden cyklus stouplo** (o dalších ~2 A), a teprve **~2 sekundy po prvním varování** BMS samo odříznul proud na 0. Během těch 2 sekund napětí vyskočilo z 3,68 V na 3,867 V. Detaily viz [fronius/README.md](../fronius/README.md#druhá-horší-událost-1415-utc-a-co-z-celého-logu-vyplývá).

**Důsledek pro návrh**:
1. **Smyčka musí běžet výrazně rychleji než dřív navrhovaných 30-60 s** — reálně blízko 1 s, jinak automatizace nestihne zareagovat dřív, než to udělá (pomalu a nedokonale) samotné BMS. `poll-cerbo.sh` běžící přes SSH dokázal cyklus ~0,7-0,9 s — nativní Node-RED flow přímo na Cerbu (bez SSH round-tripu) by měl být rychlejší.
2. **Nejrychlejší dostupný signál nejsou přepočty z `MaxCellVoltage`, ale přímo `Alarms/*` pole z BMS** — pokud BMS sám hlásí `ChargeBlocked`/`HighCellVoltage`/`CellImbalance` = 1, automatizace by na to měla reagovat okamžitě (snížit proud na bezpečnou hodnotu), ne čekat, až si to sama dopočítá z napětí. `MaxCellVoltage`-based logika zůstává jako **preventivní** vrstva (zpomalit dřív, než se k alarmu vůbec dostane), `Alarms/*` je **reaktivní** rychlá pojistka.

## Řídicí logika — spojitý (proporcionální) regulátor, ne diskrétní stupně

**Zásadní revize (13.8.2026), motivovaná živým pozorováním cyklické nestability.** Živý test (13.8.2026, 16:41-16:51 UTC — viz [fronius/README.md](../fronius/README.md#otestováno-živě-1382026-1641164451-utc--feed-in-vypnutý-jen-částečně-pomohlo)) ukázal, že i s vypnutým feed-inem a nastaveným 10A stropem ve VRM se pack chová v pravidelném cyklu: ~4 min klid (proud se drží u 10 A, rozjezd 2-3 mV) → ~3 min chaos (proud uteče na 30+ A, rozjezd stovky mV, alarmy) → opakovat. **Statické jednorázově nastavené číslo (ani binární 0/10 A přepínání) tenhle cyklus samo nezastaví** — mezi kontrolami proud zase pomalu leze nahoru, dokud znovu nenarazí na vychýlený článek.

**Cíl není jen "nezpůsobit alarm"**, ale dostat pack co nejblíž k `V_ceiling` (57 V / 3,5625 V) **a přitom zůstat vybalancovaný** — tedy nabíjení musí pokračovat skoro pořád, jen bezpečnou rychlostí, ne se úplně zastavovat pokaždé, když se něco přiblíží k prahu. Diskrétní stupně (0 A / 10 A) tohle neumí — buď jedou naplno, nebo úplně stojí. Proto nahrazeno spojitou funkcí, přepočítávanou a **zapisovanou znovu každý cyklus** (~1 s), ne jen při změně stavu:

```
margin_v = V_ceiling - MaxCellVoltage        # kolik ještě zbývá do stropu
I_allowed = I_max * clamp(margin_v / safety_band, 0, 1)   # plynulý pokles k nule s blížícím se stropem

if spread > spread_trigger:
    I_allowed = min(I_allowed, 5)             # rozjezd je druhá, nezávislá brzda

if any Alarms.* == 1:
    I_allowed = 1                             # okamžitý tvrdý zásah, nečekat na BMS vlastní odezvu (~2s lag)
    ALERT (log + notifikace)

write MaxChargeCurrent = I_allowed            # zapsat KAŽDÝ cyklus, ne jen při změně — viz "Kam zapisovat" níže
```

- `I_max` = 10 A (viz zdůvodnění níže), `safety_band` zatím neurčený (návrh, ne ověřená hodnota — orientačně ~0,1-0,15 V, potřeba doladit pozorováním).
- Proud tímhle nikdy neklesne na "tvrdou nulu" kromě skutečného alarmu — vždycky teče aspoň něco, takže pack **pořád postupuje k cíli**, jen se plynule zpomaluje/zrychluje podle toho, jak blízko je nejhorší článek.
- Na rozdíl od dnešního pozorovaného cyklu (plný proud → alarm → tvrdé 0 → zotavení → znovu plný proud, ~7min perioda) by se proud měl brzdit **dřív a plynuleji**, takže by amplituda cyklu měla být menší, ideálně by cyklus úplně zmizel.

**Proč 10 A jako `I_max`**: empiricky ověřeno 13.8.2026 (viz [fronius/README.md](../fronius/README.md#výsledek-10-a-zafungovalo-1382026-1506-utc) — 2mV stabilita, žádné alarmy po dobu 6+ minut). Shoduje se i s tím, co **Seplos BMS sám používá jako vestavěný fallback** minimálně v 5 různých ochranných funkcích — viz [dbus-paths.md](../diagnostics/dbus-paths.md#co-konkrétně-umí-batterymonitor-přečten-oficiální-manuál-1382026).

Řídicí proměnná pro nouzové brzdění = `Alarms/*` (nejrychlejší, okamžitý zásah). Řídicí proměnná pro plynulé řízení = `MaxCellVoltage` (spojitě) a `spread` (jako druhá nezávislá brzda).

## Kam zapisovat

Přes Node-RED (dbus-listener/dbus-out node nebo MQTT do Venus broker) zapisovat do DVCC nastavení max. nabíjecího proudu — přesná cesta (typicky pod `com.victronenergy.settings/Settings/SystemSetup/...` nebo ESS `CGwacs/...`) je nutné ověřit přes dbus-spy. **Zapisovat každý cyklus (~1 s), ne jen při změně** — to je zásadní rozdíl oproti dřívější verzi tohohle návrhu a přímý důsledek dnešního zjištění, že jednou nastavená hodnota se sama od sebe "rozjíždí" (proud postupně roste, i když se VRM hodnota nezměnila).

⚠️ **Dva otevřené, neověřené body, nutné vyřešit před implementací:**
1. Přesná D-Bus **zápisová** cesta pro limit proudu není potvrzená (na rozdíl od čtecí `Info/MaxChargeCurrent`, což je jen hlášení z BMS, ne řídicí vstup) — zjistit přes dbus-spy.
2. **Riziko, že i tenhle zápis bude DVCC ignorovat, dokud je zapnutý feed-in** — oficiální Victron manuál popisuje přesně tohle chování (viz níže). Živý test 13.8.2026 (feed-in vypnutý) ukázal jen částečné zlepšení, ne úplné vyřešení, takže samotné psaní do stejné DVCC hodnoty možná nebude stačit ani s automatizací. Je potřeba to ověřit přímým testem: zapsat hodnotu a sledovat, jestli se `dc_current_a` fakt drží pod ní i při zapnutém feed-inu. Pokud ne, může být nutné jako záložní krajní řešení automatizovat i dočasné vypnutí/omezení feed-inu při alarmu (v podstatě zautomatizovat to, co uživatel dnes udělal ručně, ale rychleji a cíleněji).

### Oprava: proudový limit se neprojevuje spolehlivě — není to (jen) "Fronius problém"

Dřívější verze tohoto dokumentu přisuzovala nepřesnost `MaxChargeCurrent` limitu především AC-coupled PV/Froniovi. **Opraveno 13.8.2026**: nestabilita byla živě zachycena i při naprosto stabilním výkonu Fronia (~4,1 kW, žádné mraky) — jde tedy primárně o **vlastní rampovací algoritmus BMS** (CCL roste v ~2A krocích, opakovaně až ke svému stropu 190 A) v kombinaci s nevyrovnaností packu, ne o kolísání PV jako takové. Podrobnosti a datově podložená bezpečnostní tabulka viz [fronius/README.md](../fronius/README.md).

➡️ Důsledek pro tuhle automatizaci zůstává stejný jako dřív, jen z jiného důvodu: `MaxChargeCurrent` nelze považovat za garanci na ampér přesně — je to horní mez s tolerancí. Proto je vrstva 1 (přímé sledování `Alarms/*`) důležitější než jen preventivní výpočet z napětí.

## Nasazení na Cerbu

- Node-RED addon zapnutý ve Venus OS (Large image) — běží jako služba přímo na Cerbu 24/7.
- Battery data číst přes jeden root-dump dotaz (viz výše), ne přes desítky samostatných subscriptions — jednodušší a rychlejší.
- Stav (aktuální režim, poslední spread) ukládat do flow/global contextu s perzistencí, ať přežije restart.
- Logovat každý cyklus/změnu stavu: timestamp, SOC (jen kontext), MaxCellVoltage, MinCellVoltage, spread, CCL, Alarms/*, vebus State, aktuálně nastavený proud — v podstatě totéž, co dnes loguje [`poll-cerbo.sh`](../diagnostics/scripts/poll-cerbo.sh), jen zapisované přímo na Cerbu místo přes SSH z Macu.

## Vztah k nativním funkcím BMS (nové, 13.8.2026)

Oficiální Seplos manuál (viz [dbus-paths.md](../diagnostics/dbus-paths.md)) odhalil, že BMS má **vlastní nativní funkce**, které dělají podobné věci jako tahle navrhovaná automatizace:
- **"Intermittent power supply function"** — nativní cutoff nabíjení nad nastavitelným SOC prahem (výchozí/pozorovaný 96 %) — možné (spolu)vysvětlení původního incidentu, viz [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md).
- **"Charging equalization function"** — vlastní BMS-level balancing, nezávislý na Enerkey.

Než se automatizace nasadí, stojí za to ověřit stav těchhle nativních funkcí (zapnuté? s jakými prahy?) — souběh dvou nekoordinovaných mechanismů (BMS nativní + naše nová automatizace) by mohl vytvořit podobný problém jako souběh staré Node-RED logiky s BMS popsaný níže.

## Poučení z minulého incidentu — bezpečnostní požadavky na tuhle automatizaci

Přesně tahle situace ([incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md)) vznikla z Node-RED automatizace, která tiše běžela půl roku bez dohledu (cap na 96 %) a nikdo si nevšiml driftu, dokud to nespadlo. Aby se to neopakovalo:

- **Viditelnost** — dashboard tile se spreadem a jeho trendem, ne jen skrytá logika na pozadí.
- **Alerting** — pokud spread neklesá po rozumnou dobu (např. 2 týdny) navzdory běžící logice, poslat notifikaci (Telegram/Pushover/e-mail z Node-RED) — signál, že balancer nestíhá nebo má vadný kanál.
- Tahle automatizace by měla **nahradit** starou 96% cap logiku, ne běžet vedle ní — souběh dvou nekoordinovaných automatizací byl pravděpodobně součást původního problému. Rozbor toho, co stará logika konkrétně dělá (a proč nikdy nesledovala napětí článků), viz [current-node-red-flow.md](current-node-red-flow.md).
