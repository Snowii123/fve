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
- **Enerkey** — aktivní balancer (přesouvá náboj mezi sousedními články/skupinami, ne pasivní bleed přes rezistor). Má nastavitelný aktivační práh (pole **EqualizationVol**) a stop práh (**Sleepvol**) v appce (Bluetooth, výchozí heslo `123456`). Komunitně doporučované hodnoty pro LFP jsou cca 3,41–3,44 V start / o ~0,01–0,03 V níž stop — přesná hodnota nastavená na tomto konkrétním zařízení není zatím ověřená, viz [checklist](../diagnostics/checklist.md).

## Řízení / automatizace

- Node-RED běžící (dříve) s vlastní logikou omezující nabíjení — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) pro historii a důvod, proč byla tato konkrétní automatizace problematická.
- ESS **Minimum SOC = 20 %** (potvrzeno uživatelem, vyloučeno jako příčina jevu popsaného v incidentu — viz tamtéž).
