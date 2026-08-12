# Přehled systému

## Výroba a měniče

- **6× Victron MultiPlus-II 48/3000/35-32**, ACOut2 switchable
- **Fronius Symo 17,5 kW** — AC-coupled FVE (fotovoltaika napojená na AC stranu, ne DC-coupled)
- GX zařízení: **Cerbo GX** (Venus OS), s dostupným Node-RED addonem (Venus OS Large)

## Baterie

- Homemade pack, **32 článků**, topologie: **2× nezávislý 16S string zapojený paralelně** na svorkách packu (ne 16S2P s paralelními páry v každém stupni). To znamená **32 samostatných balančních bodů** — odpovídající si články mezi oběma stringy se **navzájem nevyrovnávají automaticky**, protože nejsou nijak křížově propojené; pouze celkové napětí obou stringů je vynucené stejné přes společné svorky.
  - Praktický důsledek: nerovnováha může vznikat jak uvnitř jednoho stringu (mezi jeho 16 články), tak mezi oběma stringy jako celky (např. nesymetrické dělení proudu, pokud má jeden string vyšší vnitřní odpor nebo nižší kapacitu). Otevřená otázka, jestli Enerkey balancer vyrovnává jen v rámci jednoho stringu, nebo i mezi stringy — viz [checklist](../diagnostics/checklist.md).
- Chemie: **LFP**
- Kapacita: **~400 Ah**, ~15 kWh využitelné kapacity (konzervativně, kvůli historickému omezení popsanému v [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md))

## BMS a balancing

- **n-BMS** — komunikuje po CAN-bus přímo do Venus OS jako *managed battery* (Victron battery service). SOC, CCL (charge current limit) a DCL (discharge current limit) hlásí BMS, Victron/DVCC je jen konzumuje a řídí se jimi — SOC tedy **nepočítá Victron sám** (na rozdíl od systémů se SmartShunt/BMV, kde SOC počítá coulomb counting ve shuntu).
- **Enerkey** — aktivní balancer. **Dvě samostatné jednotky, každá pro jeden 16S string** ("Horní" a "Dolní" — potvrzuje topologii výše: 2× nezávislý 16S string, žádné křížové propojení balancerů mezi stringy). Ověřená skutečná nastavení (appka, Bluetooth, heslo `123456`):

  | Parametr | Horní | Dolní |
  |---|---|---|
  | Qty(S) | 16 | 16 |
  | RunVol (V) — aktivační napětí | **3,480** | **3,350** |
  | StopVol (V) — vypínací napětí | 3,400 | 3,180 |
  | Startup DifVol (V) — min. rozdíl pro start | 0,010 | 0,005 |
  | Stop DifVol (V) | 0,000 (needitovatelné) | 0,000 (needitovatelné) |
  | Max EquCur (A) — max. vyrovnávací proud | **0,5** | **4,0** |
  | Soc (Ah) | 200 | 200 |
  | BatType | LFP | LFP |

  Soc(Ah)=200 na obou jednotkách odpovídá ~200 Ah na string, dohromady ~400 Ah — konzistentní s odhadem celkové kapacity packu výše.

  **Významná asymetrie mezi jednotkami** — Horní aktivuje mnohem později (3,48 V vs. 3,35 V) a i po aktivaci vyrovnává 8× pomaleji (0,5 A vs. 4 A) než Dolní. To je potenciálně důležitý dílek k [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md): pokud incident vznikl na Horním stringu, dává to smysl — ten string má balancer nastavený tak, že má výrazně menší šanci stihnout vyrovnat rozjezd před tím, než článek narazí na OV, i nezávisle na historii se 96% capem.

### Komunitně doporučené hodnoty (zdroje)

Z veřejných diskuzí o NEEY/Enerkey aktivních balancerech pro LFP (stejná rodina firmwaru, stejná pojmenování polí):

- **RunVol/EqualizationVol (aktivační napětí)**: komunitně doporučovaný rozsah **3,41–3,44 V**, s doporučením snížit, pokud 3,44 V nedává dobré vyrovnání ([DIY Solar Forum — Neey 4th Gen 4A Active Balancer Settings](https://diysolarforum.com/threads/neey-4th-gen-4a-active-balancer-settings.62013/)).
- Konkrétní zdokumentovaný příklad nastavení: **RunVol 3,450 V / StopVol 3,440 V** ([DIY Solar Forum — How to calibrate NEEY/ENERKEY active balancer voltage?](https://diysolarforum.com/threads/how-to-calibrate-neey-enerkey-active-balancer-voltage.97277/)), jiný uživatel uvádí start 3,425 V / stop 3,400 V.
- Stejné vlákno upozorňuje: pokud nabíjecí systém cílí cca 3,50 V/článek v absorpci u 16S packu, může být nutné zvednout **BMS high voltage disconnect na 3,60–3,65 V**, jinak BMS odřízne dřív, než nabíjení doběhne — relevantní přímo pro [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) a pro ověření OV threshold v checklistu.

### Doporučené nastavení (sjednocené, ke zvážení)

Cíl: obě jednotky se chovají stejně, žádná není systematicky slabší. Návrh — **stejné hodnoty na obou**:

| Parametr | Doporučená hodnota | Zdůvodnění |
|---|---|---|
| RunVol (V) | **3,400** | Mírně pod komunitním rozsahem 3,41–3,44 V (viz výše) — vědomě konzervativnější kvůli historii silně nevybalancovaného packu, dává víc času na vyrovnání. Každopádně nižší než dosavadní Horní (3,480). |
| StopVol (V) | **3,300** | 100 mV hystereze pod RunVol — konzistentní okno pro obě jednotky. |
| Startup DifVol (V) | **0,005** | Hodnota z Dolní jednotky — citlivější spuštění, zachytí menší rozjezd dřív než 0,010 V na Horní. |
| Stop DifVol (V) | 0,000 | Needitovatelné na obou, není co měnit. |
| Max EquCur (A) | **4,0** | Zrychlí Horní jednotku 8×. **Než to nastavíte, ověřte, že je Horní hardwarově na 4 A skutečně dimenzovaná** — pokud je to jiná/slabší revize jednotky, nechte ji na jejím bezpečném maximu místo kopírování čísla od Dolní. |

⚠️ Tohle je odvozené doporučení, ne ověřená bezpečná hodnota — **než se to aplikuje, ideálně potvrdit OV warning threshold v n-BMS** (viz [checklist](../diagnostics/checklist.md)) a mít jistotu, že 3,400 V start má dostatečnou rezervu pod ním. Po aplikaci sledovat chování stejně jako v [rebalancing-procedure.md](rebalancing-procedure.md).

## Řízení / automatizace

- Node-RED běžící (dříve) s vlastní logikou omezující nabíjení — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) pro historii a důvod, proč byla tato konkrétní automatizace problematická.
- ESS **Minimum SOC = 20 %** (potvrzeno uživatelem, vyloučeno jako příčina jevu popsaného v incidentu — viz tamtéž).
