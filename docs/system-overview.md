# Přehled systému

## Výroba a měniče

- **6× Victron MultiPlus-II 48/3000/35-32**, ACOut2 switchable
- **Fronius Symo 17,5 kW** — AC-coupled FVE (fotovoltaika napojená na AC stranu, ne DC-coupled)
- GX zařízení: **Cerbo GX** (Venus OS), s dostupným Node-RED addonem (Venus OS Large)

## Baterie

- Homemade pack, **32 článků** zapojených jako **16S2P** (16 sériových skupin, každá ze 2 paralelních článků — paralelní dvojice se vzájemně vyrovnávají přes společný spoj, takže relevantní pro balancing je 16 sériových bodů, ne 32 jednotlivých článků)
- Chemie: **LFP**
- Kapacita: **~400 Ah**, ~15 kWh využitelné kapacity (konzervativně, kvůli historickému omezení popsanému v [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md))

## BMS a balancing

- **n-BMS** — komunikuje po CAN-bus přímo do Venus OS jako *managed battery* (Victron battery service). SOC, CCL (charge current limit) a DCL (discharge current limit) hlásí BMS, Victron/DVCC je jen konzumuje a řídí se jimi — SOC tedy **nepočítá Victron sám** (na rozdíl od systémů se SmartShunt/BMV, kde SOC počítá coulomb counting ve shuntu).
- **Enerkey** — aktivní balancer (přesouvá náboj mezi sousedními články/skupinami, ne pasivní bleed přes rezistor). Má napěťový aktivační práh, pod kterým nepracuje (odhad ~3,40–3,45 V/článek pro LFP — nutno ověřit v datasheetu, viz [checklist](../diagnostics/checklist.md)).

## Řízení / automatizace

- Node-RED běžící (dříve) s vlastní logikou omezující nabíjení — viz [incident-dvcc-shutdown.md](incident-dvcc-shutdown.md) pro historii a důvod, proč byla tato konkrétní automatizace problematická.
- ESS **Minimum SOC = 20 %** (potvrzeno uživatelem, vyloučeno jako příčina jevu popsaného v incidentu — viz tamtéž).
