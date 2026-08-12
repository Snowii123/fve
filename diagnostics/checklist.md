# Diagnostický checklist — otevřené položky

Diagnóza v [`docs/incident-dvcc-shutdown.md`](../docs/incident-dvcc-shutdown.md) je z velké části **hypotéza odvozená z popisu chování**, ne přímo ověřená měřením. Tyhle body je potřeba potvrdit na systému:

- [ ] Aktuální cell voltage spread (přes dbus-spy nebo Node-RED) — je pořád ~270 mV?
- [ ] Discharge cutoff napětí na článek nastavené v n-BMS vs. skutečné napětí nejnižšího článku v okamžiku, kdy SOC ukazuje ~47 %
- [ ] CCL/DCL log v n-BMS v okamžiku pádu do OFF (potvrdí/vyvrátí hypotézu DVCC fail-safe)
- [ ] n-BMS OV warning threshold vs. hard disconnect threshold (má n-BMS měkčí varovný stupeň před tvrdým odpojením?)
- [ ] Enerkey — aktivační práh napětí a vyrovnávací proud (z datasheetu; ovlivňuje, jak dlouho bude rebalance trvat)
- [ ] Poslední úspěšný "full charge sync" v n-BMS — kdy proběhl a za jakých podmínek (byl pack v tu chvíli vybalancovaný?)
- [x] ESS Minimum SOC = 20 % — potvrzeno uživatelem, **není příčinou** jevu "vybíjení jen do 47 %"
- [ ] Přesné D-Bus cesty pro čtení cell voltages a zápis MaxChargeCurrent (viz [dbus-paths.md](dbus-paths.md)) — ověřit přes dbus-spy
