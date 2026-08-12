# SOC kalibrace — jak to funguje a proč selhala

## Kdo počítá SOC

Existují dva zásadně odlišné případy, které je nutné rozlišit:

- **Baterie s vlastním BMS po CAN-bus** (náš případ — n-BMS) — SOC **nepočítá Victron**, ale hlásí ho přímo BMS baterie po sběrnici. Cerbo/Venus OS ho jen zobrazuje a používá pro řízení (DVCC).
- **Baterie bez komunikace**, monitorovaná přes **BMV-712 / SmartShunt** — SOC počítá Victron sám coulomb countingem (sčítání Ah dovnitř/ven), synchronizovaným na "plno" podle nastavených parametrů (Battery capacity, Charged voltage, Tail current, Peukert exponent, Charge efficiency factor).

## Pojem "tail current"

**Tail current** (nabíjecí proud na konci absorpční fáze) je proud, který do baterie ještě teče, když je napětí už na cílové (absorpční) hodnotě a proud postupně klesá k nule — "ocásek" nabíjecí křivky.

Nabíječ/BMS potřebuje kritérium, kdy prohlásit "baterie je plná" a synchronizovat SOC na 100 %. Typicky: *"když proud klesne pod X % z kapacity při udrženém absorpčním napětí, je baterie plná."*

- Práh nastavený **moc vysoko** → sync na 100 % proběhne předčasně, i když baterie fyzicky ještě nebyla plná.
- Práh nastavený **moc nízko** → podmínka se nikdy nesplní, SOC se nikdy nesyncne a postupně driftuje.

U nevybalancovaného packu je tenhle koncept navíc nespolehlivý sám o sobě, viz níže.

## Proč nejde kalibrovat nevybalancovaný pack

Kritérium "plné baterie" (ať už tail current, nebo BMS interní sync) se typicky vyhodnocuje na **celkovém proudu/napětí packu**, ne na jednotlivých článcích. Pokud je pack nevybalancovaný (viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md), rozjezd 270 mV):

- Nejvyšší článek může narazit na OV protection **dřív**, než je pack jako celek skutečně plný.
- Nejnižší článek může narazit na discharge cutoff **dřív**, než je pack jako celek skutečně prázdný.
- SOC "100 %" a "0 %" pak neodpovídají reálné využitelné kapacitě — chyba je v obou směrech současně, protože oba konce určuje nejvíc vychýlený článek, ne průměr.

**Důsledek:** kalibrace SOC dává smysl až po rebalancování packu na rozumnou úroveň rozjezdu (řádově jednotky až nízké desítky mV), ne dřív. Postup viz [rebalancing-procedure.md](rebalancing-procedure.md).

## Co to znamená prakticky

- **Nespoléhat na SOC % jako řídicí kritérium** při jakékoliv budoucí kalibraci nebo automatizaci — SOC je přesně ta veličina, která je nepřesná. Řídicí veličinou musí být **napětí jednotlivých článků** (konkrétně max. a min. napětí v packu), ne SOC ani průměrné napětí.
- Viz [automation/node-red-control-logic.md](../automation/node-red-control-logic.md) pro konkrétní návrh, jak tohle řídit automaticky.
