# Návrh: trvalá automatizace řízení nabíjecího proudu podle napětí článků

Cíl: nahradit manuální/jednorázový postup z [rebalancing-procedure.md](../docs/rebalancing-procedure.md) trvalou closed-loop automatizací běžící přímo na Cerbu, řízenou podle **napětí článků**, ne podle SOC (viz [soc-calibration.md](../docs/soc-calibration.md) pro zdůvodnění).

**Proč tahle externí kontrola nemá nahrazovat samotný Enerkey balancer, ale doplňovat ho**: podle [enerkey-balancer-mechanism.md](../docs/enerkey-balancer-mechanism.md) může Enerkey přestat pracovat pro celý string, pokud jeden článek leží mimo jeho RunVol–StopVol okno — externí kontrola nabíjecího proudu podle skutečného `MaxCellVoltage` napříč všemi články zůstává funkční nezávisle na tom, jestli interní balancer zrovna běží.

**Status: návrh, zatím neimplementováno.**

## Co číst (Node-RED, D-Bus/MQTT z Venus OS)

Přesné cesty je nutné ověřit přes dbus-spy na konkrétním systému — liší se podle verze n-BMS integrace. Viz [diagnostics/dbus-paths.md](../diagnostics/dbus-paths.md).

| Veličina | Účel |
|---|---|
| `System/MaxCellVoltage` | napětí nejvyššího článku — hlavní řídicí veličina pro brzdění proudu |
| `System/MinCellVoltage` | napětí nejnižšího článku — spolu s Max určuje spread |
| `System/MaxVoltageCellId` / `MinVoltageCellId` | který konkrétní článek je extrém — sledovat v čase, jestli je to pořád ten samý |
| `Info/ChargeCurrentLimit` (CCL) | co BMS momentálně povoluje — pokud samo klesá, BMS už brzdí |
| `Soc` | jen pro logování/kontext, **ne** pro řízení |

## Řídicí logika (state machine)

Prahy:
- `V_bal` — aktivační napětí Enerkey balanceru. Doporučené sjednocené nastavení obou jednotek je **3,400 V** (viz [system-overview.md](../docs/system-overview.md#doporučené-nastavení-sjednocené-ke-zvážení)) — pokud se aplikuje, použít tuhle hodnotu; do té doby jsou obě jednotky odlišné (Horní 3,480 V, Dolní 3,350 V), takže logika by musela brát v potaz obě zvlášť podle stringu.
- `V_warn` — měkký OV warning práh v n-BMS (musí být níž než tvrdý disconnect) — zatím neověřeno, viz [checklist](../diagnostics/checklist.md).
- `spread_target` — cílový rozjezd, kdy je pack "dost vybalancovaný" (orientačně 20–30 mV)

Smyčka běží každých 30–60 s během nabíjení blízko vrcholu:

```
if MaxCellVoltage < V_bal:
    # pod pracovním oknem balanceru, žádný zásah
    normální nabíjecí proud (běžný ESS/DVCC režim)

elif V_bal <= MaxCellVoltage < V_warn - margin:
    if spread > spread_target:
        MaxChargeCurrent = trickle  # např. 2-4 A na 400 Ah pack
        # necháváme pomalu stoupat napětí, ať se i nejnižší články
        # dostanou do pracovního okna balanceru, ale pomalu
    else:
        MaxChargeCurrent = normální hodnota
        # spread zavřený -> bezpečné dojet naplno, tady je bezpečný
        # okamžik pro "full charge sync"

elif MaxCellVoltage >= V_warn - margin:
    MaxChargeCurrent = 0  # pauza
    # počkat na relaxaci napětí a/nebo že balancer stáhne rozjezd
    # pokračovat až MaxCellVoltage klesne zpět pod V_warn - margin
    # ALERT pokud stav trvá > X minut bez zlepšení spreadu
```

Řídicí proměnná pro brzdění = `MaxCellVoltage` (ten může shodit systém do OFF). Řídicí proměnná pro to, kdy zrychlit = `spread`.

## Kam zapisovat

Přes Node-RED (dbus-listener/dbus-out node nebo MQTT do Venus broker) zapisovat do DVCC nastavení max. nabíjecího proudu — přesná cesta (typicky pod `com.victronenergy.settings/Settings/SystemSetup/...` nebo ESS `CGwacs/...`) je nutné ověřit přes dbus-spy. Zapisovat **jen při změně stavu**, ne v každém cyklu.

### Pozorovaný problém: nastavený proudový limit se neprojevuje spolehlivě

V praxi bylo zjištěno, že nastavení 2 A v GX Remote Console → DVCC (přepínač i hodnota potvrzeně aktivní) přesto neodpovídá reálně měřenému proudu — občas naskočí až na ~30 A. Tohle je projev širšího problému (Fronius 17,5 kW výrazně předimenzovaný vůči ~400 Ah packu), který se řeší jako **samostatná kapitola** — viz [`fronius/README.md`](../fronius/README.md), včetně hypotézy příčiny a další diagnostiky.

➡️ Důsledek pro tuhle automatizaci: `MaxChargeCurrent` nelze považovat za garanci na ampér přesně, dokud se Fronius problém nevyřeší — je to horní mez s určitou tolerancí/zpožděním. To zvyšuje důležitost sledování `MaxCellVoltage` jako nezávislé pojistky (viz state machine výše) — i kdyby proudový limit občas přestřelil, napěťová brzda musí zafungovat spolehlivě.

## Nasazení na Cerbu

- Node-RED addon zapnutý ve Venus OS (Large image) — běží jako služba přímo na Cerbu 24/7.
- Stav (aktuální režim, poslední spread) ukládat do flow/global contextu s perzistencí, ať přežije restart.
- Logovat každý cyklus/změnu stavu: timestamp, SOC, MaxCellVoltage, MinCellVoltage, spread, CCL, aktuálně nastavený proud.

## Poučení z minulého incidentu — bezpečnostní požadavky na tuhle automatizaci

Přesně tahle situace ([incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md)) vznikla z Node-RED automatizace, která tiše běžela půl roku bez dohledu (cap na 96 %) a nikdo si nevšiml driftu, dokud to nespadlo. Aby se to neopakovalo:

- **Viditelnost** — dashboard tile se spreadem a jeho trendem, ne jen skrytá logika na pozadí.
- **Alerting** — pokud spread neklesá po rozumnou dobu (např. 2 týdny) navzdory běžící logice, poslat notifikaci (Telegram/Pushover/e-mail z Node-RED) — signál, že balancer nestíhá nebo má vadný kanál.
- Tahle automatizace by měla **nahradit** starou 96% cap logiku, ne běžet vedle ní — souběh dvou nekoordinovaných automatizací byl pravděpodobně součást původního problému.
