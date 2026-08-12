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
- **Enerkey** — aktivní balancer. **Dvě samostatné jednotky, každá pro jeden 16S string** ("Horní" a "Dolní" — potvrzuje topologii výše: 2× nezávislý 16S string, žádné křížové propojení balancerů mezi stringy). Jak mechanismus vyrovnávání skutečně funguje uvnitř (sekvenční přenos mezi aktuálně nejvyšším/nejnižším článkem, globální brána podle RunVol/StopVol) — viz samostatný dokument [enerkey-balancer-mechanism.md](enerkey-balancer-mechanism.md).

  **Klíčové zjištění (12.8.2026): obě jednotky měly vypnutý hlavní přepínač "Equalizing"** — bez ohledu na RunVol/StopVol/Max EquCur balancery **vůbec neběžely, nikdy**. Tohle je pravděpodobně skutečná hlavní příčina 270 mV rozjezdu, fundamentálnější než asymetrie nastavení popsaná níže — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md#aktualizace-12822026-equalize-switch-byl-vypnutý--pravděpodobná-skutečná-hlavní-příčina).

  **Stav před nápravou** (nastavení beze změny, ale switch OFF na obou):

  | Parametr | Horní | Dolní |
  |---|---|---|
  | Qty(S) | 16 | 16 |
  | RunVol (V) — aktivační napětí | 3,480 | 3,350 |
  | StopVol (V) — vypínací napětí | 3,400 | 3,180 |
  | Startup DifVol (V) — min. rozdíl pro start | 0,010 | 0,005 |
  | Max EquCur (A) — max. vyrovnávací proud | 0,5 | 4,0 |
  | Soc (Ah) | 200 | 200 |

  Soc(Ah)=200 na obou jednotkách odpovídá ~200 Ah na string, dohromady ~400 Ah — konzistentní s odhadem celkové kapacity packu výše. Asymetrie nastavení (Horní 8× pomalejší, aktivuje později) zůstává platné zjištění — jen bylo irelevantní, dokud byl přepínač vypnutý.

  **Aktuální stav — aplikováno (12.8.2026)**: obě jednotky sjednoceny na hodnoty z původní Dolní jednotky, Equalize **zapnuto na obou**:

  | Parametr | Horní i Dolní (sjednoceno) |
  |---|---|
  | RunVol (V) | **3,350** |
  | StopVol (V) | **3,180** |
  | Startup DifVol (V) | **0,005** |
  | Max EquCur (A) | **4,0** |
  | Equalizing | **ON (obě jednotky)** |

  Živé odečty krátce po zapnutí: Horní `State: EquRun`, `EquCur 4,011 A`, `DifVol 0,031 V` (31 mV); Dolní `State: System ready`, `EquCur 0,000 A` (pravděpodobně jen duty-cycling mezi dávkami, ne porucha — DifVol 0,018 V je už malé), `DifVol 0,018 V` (18 mV). Napříč oběma stringy: max 3,364 V / min 3,331 V → **pack-wide spread ~33 mV**, prudký pokles z historických 270 mV. Viz trend v [checklist.md](../diagnostics/checklist.md).

### Komunitně doporučené hodnoty (zdroje)

Z veřejných diskuzí o NEEY/Enerkey aktivních balancerech pro LFP (stejná rodina firmwaru, stejná pojmenování polí):

- **RunVol/EqualizationVol (aktivační napětí)**: komunitně doporučovaný rozsah **3,41–3,44 V**, s doporučením snížit, pokud 3,44 V nedává dobré vyrovnání ([DIY Solar Forum — Neey 4th Gen 4A Active Balancer Settings](https://diysolarforum.com/threads/neey-4th-gen-4a-active-balancer-settings.62013/)).
- Konkrétní zdokumentovaný příklad nastavení: **RunVol 3,450 V / StopVol 3,440 V** ([DIY Solar Forum — How to calibrate NEEY/ENERKEY active balancer voltage?](https://diysolarforum.com/threads/how-to-calibrate-neey-enerkey-active-balancer-voltage.97277/)), jiný uživatel uvádí start 3,425 V / stop 3,400 V.
- Stejné vlákno upozorňuje: pokud nabíjecí systém cílí cca 3,50 V/článek v absorpci u 16S packu, může být nutné zvednout **BMS high voltage disconnect na 3,60–3,65 V**, jinak BMS odřízne dřív, než nabíjení doběhne — relevantní přímo pro [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) a pro ověření OV threshold v checklistu.

### Doporučené nastavení — status: aplikováno (s drobnou odchylkou)

Původní návrh byl RunVol 3,400 V / StopVol 3,300 V. Uživatel místo toho sjednotil obě jednotky na hodnoty **z původní Dolní jednotky** (RunVol 3,350 V / StopVol 3,180 V) — viz tabulka "Aktuální stav" výše. To je v pořádku, dokonce lepší vůči invariantu z [fronius/README.md](../fronius/README.md#důležitý-invariant-balancer-musí-pracovat-i-při-běžném-provozu-ne-jen-při-kalibraci) (`RunVol < V_buffer_ceiling`) — nižší RunVol znamená ještě víc rezervy.

⚠️ Pořád platí: **`V_hard` (tvrdý OV disconnect v n-BMS) není ověřený** — viz [checklist](../diagnostics/checklist.md). Číslo 3,350 V je bezpečně nízko oproti odhadovanému rozsahu, ale odhad zůstává odhadem, dokud se nezjistí přímo z n-BMS.

## Řízení / automatizace

- Node-RED běžící (dříve) s vlastní logikou omezující nabíjení — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) pro historii a důvod, proč byla tato konkrétní automatizace problematická.
- ESS **Minimum SOC = 20 %** (potvrzeno uživatelem, vyloučeno jako příčina jevu popsaného v incidentu — viz tamtéž).
- ESS mód **"Keep batteries charged"** — pozorováno aktivní během incidentu 12.8.2026, aktivně tlačí pack k udržování 100 % SOC. Jde přímo proti plánované strategii "buffer pod stropem" ([fronius/README.md](../fronius/README.md)) — měl by se používat jen záměrně během řízených kalibračních cyklů, ne jako trvalý stav. Po incidentu přepnuto na **Optimized without BatteryLife**.
