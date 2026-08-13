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

## Řídicí logika (state machine) — revidováno

Smyčka běží **~1 s** během nabíjení blízko vrcholu (ne 30-60 s jako v dřívější verzi):

```
# Vrstva 1 (nejrychlejší, reaktivní): vlastní alarmy BMS
if Alarms.ChargeBlocked or Alarms.HighCellVoltage or Alarms.CellImbalance:
    MaxChargeCurrent = 0   # okamžitě, nečekat na vlastní výpočet
    ALERT (log + notifikace)
    # pokračovat dál až alarmy zmizí A MaxCellVoltage klesne pod V_bal - margin

# Vrstva 2 (preventivní): napětí a rozjezd, viz tabulka ve fronius/README.md
elif MaxCellVoltage < V_bal:
    normální nabíjecí proud (běžný ESS/DVCC režim)

elif spread > spread_trigger:
    MaxChargeCurrent = 10   # ověřená bezpečná hodnota, viz níže
    # rozjezd je nezávislý spouštěč na zpomalení, i když napětí samo o sobě OK

elif V_bal <= MaxCellVoltage < V_ceiling - margin:
    MaxChargeCurrent = 10   # ověřená bezpečná hodnota

elif MaxCellVoltage >= V_ceiling - margin:
    MaxChargeCurrent = 0
    # počkat na relaxaci; ALERT pokud trvá > X minut bez zlepšení
```

**Proč 10 A**: empiricky ověřeno 13.8.2026 (viz [fronius/README.md](../fronius/README.md#výsledek-10-a-zafungovalo-1382026-1506-utc) — 2mV stabilita, žádné alarmy po dobu 6+ minut, zopakováno i po přepnutí na "Keep batteries charged"). Navíc se shoduje s tím, co **Seplos BMS sám používá jako vestavěný fallback** minimálně v 5 různých ochranných funkcích (cell/pack high voltage warning, charging high temp warning, active/passive current limiting) — viz [dbus-paths.md](../diagnostics/dbus-paths.md#co-konkrétně-umí-batterymonitor-přečten-oficiální-manuál-1382026). Přesná hodnota `margin` pod `V_ceiling` zatím neurčena — návrh vyžaduje delší pozorování než jedno odpoledne.

Řídicí proměnná pro nouzové brzdění = `Alarms/*` (nejrychlejší). Řídicí proměnná pro preventivní zpomalení = `MaxCellVoltage` a `spread`.

## Kam zapisovat

Přes Node-RED (dbus-listener/dbus-out node nebo MQTT do Venus broker) zapisovat do DVCC nastavení max. nabíjecího proudu — přesná cesta (typicky pod `com.victronenergy.settings/Settings/SystemSetup/...` nebo ESS `CGwacs/...`) je nutné ověřit přes dbus-spy. Zapisovat **jen při změně stavu**, ne v každém cyklu.

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
