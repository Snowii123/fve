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

## Řízení / automatizace

- Node-RED běžící (dříve) s vlastní logikou omezující nabíjení — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) pro historii a důvod, proč byla tato konkrétní automatizace problematická.
- ESS **Minimum SOC = 20 %** (potvrzeno uživatelem, vyloučeno jako příčina jevu popsaného v incidentu — viz tamtéž).
