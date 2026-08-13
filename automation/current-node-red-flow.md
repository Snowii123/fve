# Rozbor aktuálně běžící Node-RED automatizace

**Status: analýza exportovaného flow (JSON), poskytnutého uživatelem k rozboru — zatím neověřeno přímo na Cerbu.**

Tenhle dokument popisuje, co dělá Node-RED flow, který v současnosti běží (resp. běžel) na systému. Je to velmi pravděpodobně ta „Node-RED automatizace", která podle [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) bránila nabití nad 96 % SOC — ale ve skutečnosti dělá výrazně víc než jen tenhle jeden strop, a 96% cap je v ní už zobecněný na nastavitelnou hodnotu (viz Logic 1 níže), ne natvrdo zadrátovaný.

## Jak identifikace vznikla

Flow adresuje Victron služby stylem `node-red-contrib-victron` (`service/instance-číslo`, např. `com.victronenergy.battery/512`, `com.victronenergy.pvinverter/20`, `com.victronenergy.vebus/276`), ne syrovým D-Bus jménem service (`com.victronenergy.battery.socketcan_can1` apod. z [dbus-paths.md](../diagnostics/dbus-paths.md)) — obojí může být tentýž fyzický systém, jen adresovaný dvěma různými cestami. Typy zařízení (MultiPlus-II 48/3000/35-32, Fronius Symo 17.5, jediná battery service pro celý pack) odpovídají [system-overview.md](../docs/system-overview.md). Silná shoda, ale bez přímého porovnání instance-čísel na živém systému to není stoprocentní jistota — k ověření viz [checklist](../diagnostics/checklist.md).

## Architektura

Pět nezávislých „logik" každá rozhoduje o své dílčí věci a zapisuje závěr do flow-proměnné (`flow.logicN.*`). Dvě centrální smyčky běžící každou sekundu čtou tyhle proměnné (agregují prioritou, kde je jich víc) a **teprve ony** zapisují do Victronu — a jen při změně hodnoty oproti aktuálnímu stavu, s rate-limitem přes `delay` uzel. Rozhodovací logika je tak čistě oddělená od zápisu do hardwaru, což je dobrý návrh — omezuje to zbytečné/časté přepínání DVCC a VEBUS módu.

### Logic 1 — DVCC limit nabíjecího proudu podle SOC

Toto je pravděpodobně přímý nástupce „96% cap" automatizace z incidentu — mechanismus je stejný (blokace nabíjení nad nastavený strop SOC), jen strop je teď nastavitelný přes UI slider (`Max SOC`), ne pevný.

- Nad `Max SOC` (+1 %) zapíše `MaxChargeCurrent = 0` (blokace nabíjení).
- Pod `Max SOC` zapíše `MaxChargeCurrent = -1` (bez limitu).
- Obsahuje hysterezi „přebytek FV vs. spotřeba": do stavu „přebytek" (podmínka pro blokaci přesně na hranici `Max SOC`) přejde po 10 s trvalého přebytku, návrat trvá 2 minuty souvislé převahy spotřeby nad FV — asymetrický debounce proti zbytečnému cvakání.
- **Důležité pro návaznost na [node-red-control-logic.md](node-red-control-logic.md): tahle logika vůbec nesleduje `MaxCellVoltage` ani cell spread** — řídí se čistě podle SOC packu. To přesně odpovídá diagnóze v [incident-dvcc-shutdown.md](../docs/incident-dvcc-shutdown.md) — automatizace držela SOC pod stropem šest měsíců, ale nic nehlídalo, jestli se pack skutečně balancuje, takže rozjezd 270 mV se nabaloval nepozorovaně.

### Logic 2 — prodej přebytku do sítě

Nad nastavené SOC (`par1`) začne exportovat do sítě (`AcPowerSetPoint`, limitovaný `MaxFeedInPower`), pod nižším prahem (`par2`) export vypne a obnoví stav on/off-grid, který platil před spuštěním.

### Logic 3 / Logic 4 — bezpečnostní přepnutí on-grid podle SOC

Logic 3 vynutí grid při příliš nízkém SOC (ochrana proti hlubokému vybití v off-gridu), Logic 4 při příliš vysokém SOC. Obě mají společný „hlavní vypínač" (`vstup.logic34.auto`) i vlastní individuální přepínače.

### Logic 5 — ukončení ESS „Keep batteries charged" módu

Hlídá stav `Settings/CGwacs/BatteryLife/State`; když je aktivní hodnota 9 („Keep batteries charged"), vynutí grid, dokud SOC nedosáhne prahu — **který ale znovupoužívá parametr Logic 1** (`vstup.logic1.par1`), ne vlastní. Netriviální skrytá vazba mezi logikami, viz níže.

### Perzistence a dashboard

Nastavení (zapnuto/vypnuto + parametry) pro každou logiku se ukládá/načítá z textových souborů na disku (`/data/home/nodered/.node-red/logicN_*.txt`) přes tlačítko v UI. Funkčně to jede, ale je hodně duplicitní (skoro identická sada uzlů 5×).

Dále je ve flow tabulka s logem událostí (timestamp, SOC, mód, ESS status, DVCC limit) a průměrované grafy (SOC, Grid, Rele, Logic1/2) — slušná viditelnost do historie, i když bez alertingu, který [node-red-control-logic.md](node-red-control-logic.md) požaduje jako bezpečnostní podmínku pro novou automatizaci.

## Zjištěné problémy

1. **Chyba v Logic 2**: podmínka pro „neomezený export" je `if (max_grid <= 0)`, ale podle popisu uzlu `MaxFeedInPower` znamená `0` = export limitovaný na 0 W (žádný), `-1` = neomezeno. Aktuální kód při `MaxFeedInPower = 0` použije záložních 20 kW místo 0 — tedy „vypnutý export" se v praxi nevynutí. Mělo by být `< 0`.
2. **Mrtvý uzel**: čtení `/Relay/1/State` nemá napojený žádný výstup — nepoužívá se, pravděpodobně pozůstatek starší verze.
3. **Matoucí pojmenování**: proměnná `data.relay2.status`/„relay_status" ve skutečnosti nese stav VEBUS `/Mode` (2/3/4), ne relé — ztěžuje to čtení logiky 2/3/4.
4. **Skrytá vazba Logic 1 ↔ Logic 5**: Logic 5 používá `vstup.logic1.par1` (Max SOC z Logic 1) jako svůj vlastní práh, nikde to není okomentované — úprava Max SOC v Logic 1 nevědomky ovlivní i Logic 5.
5. **Přesná rovnost `soc == max_soc`** v jedné z větví Logic 1 — pokud SOC „přeskočí" přesně tuhle hodnotu, blokace nastane až o 1 % později (funkčně neškodné, jen méně robustní než rozsahová podmínka).
6. **Chybí ošetření chybných/chybějících hodnot** při načtení parametrů ze souboru — poškozený/chybějící soubor → `NaN` → tichá deaktivace ochranné podmínky (např. Logic 3/4 přestanou reagovat, aniž by to bylo vidět).

## Doporučená vylepšení

- Oprava bodu 1 (Logic 2, `<= 0` → `< 0`) — jediná položka s reálným bezpečnostním/konfiguračním dopadem.
- Přejmenovat `data.relay2.*` na něco jako `data.vebus.mode` a `data.vebus.on_grid`.
- Dát Logic 5 vlastní parametr místo sdílení `vstup.logic1.par1`, nebo to aspoň okomentovat v kódu.
- Perzistenci (soubory) nahradit Node-RED file-based context storage (`flow.set(key, val, "file")`) — odpadne ruční file I/O a string↔bool/number konverze, méně duplicitních uzlů.
- Přidat sanity-check `min < max` u párů prahů (Logic 2 par1/par2, Logic 3/4 par1) a `isNaN` fallback při načtení ze souboru.

## Vztah k plánované automatizaci

[node-red-control-logic.md](node-red-control-logic.md) navrhuje tenhle SOC-only přístup (aspoň co se týče horní meze/DVCC) nahradit řízením podle `MaxCellVoltage`/spreadu — tenhle dokument potvrzuje, že současný stav skutečně nemá žádnou vazbu na napětí článků, takže návrh cílí na reálnou mezeru, ne na hypotetickou.
