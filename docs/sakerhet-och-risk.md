# Säkerhet och risk

Vad som faktiskt är farligt, vad som inte är det, och vad man ska låta bli.

---

## Varför sandlådan är riskfri

**Ingen fysisk port.** `ovsbr-lab` har inga uplinks. Trafik kan inte lämna
bryggan oavsett hur fel man konfigurerar. Namespaces har egen routingtabell utan
default gateway.

**`/etc/network/interfaces` rörs aldrig.** Det är den enskilt viktigaste
designbeslutet. Debians nätverksuppstart läser den filen vid boot — ett
syntaxfel där och maskinen kommer upp utan nät. OVS lagrar i stället sin
konfiguration i `/etc/openvswitch/conf.db` och återskapar bryggan själv via
`openvswitch-switch.service`, helt utanför `ifupdown`.

Konsekvensen: även en helt sönderkonfigurerad `ovsbr-lab` hindrar inte Proxmox
från att komma upp med `vmbr0` och `vmbr1` som vanligt.

**Skyddsräcke i skripten.** Både `setup-sandbox.sh` och `teardown-sandbox.sh`
vägrar köra om målbryggan heter `vmbr0` eller `vmbr1`.

## Vad installationen faktiskt ändrade

```
apt install openvswitch-switch
```

Det startar `ovs-vswitchd` och `ovsdb-server`. Paketet **rör inte** befintliga
Linux-bryggor — verifierat före och efter: `vmbr0` och `vmbr1` oförändrade,
nätet uppe, tio VM:ar opåverkade, noll OVS-bryggor tills en skapades manuellt.

Proxmox web-UI får stöd för OVS-bryggor efter installationen, men skapar inga.

## Det här ska du inte göra

**Konvertera `vmbr0` eller `vmbr1` till OVS.** Det kräver ändringar i
`/etc/network/interfaces` och en omstart av nätverket på en hypervisor som kör
allt du äger — Holm Digital, kveld.se, skolans maskiner, Windows-mallarna. Går
det fel står allt tills du är fysiskt vid maskinen i Habo.

Vill du ändå testa OVS med riktig trafik: `eno2np1` står med tom SFP+-bur. En
kabel dit ger en fysiskt separat väg utan att röra de två fungerande bryggorna.

**Ta bort alla flöden utan att lägga tillbaka NORMAL.**

```bash
ovs-ofctl del-flows ovsbr-lab      # nu switchar bryggan ingenting alls
```

I sandlådan är det ofarligt och pedagogiskt. På en brygga med VM:ar är det ett
totalt avbrott.

**Spegla en snabb länk till en långsam port.** Speglar du 10 GbE till 1 GbE
tappas paket tyst. IDS:en ser 80 % av trafiken och ingen märker att resten
saknas — vilket är värre än ingen IDS, eftersom man tror sig ha täckning.

## Vad som överlever omstart

| | |
|---|---|
| Bryggan `ovsbr-lab` | **Ja** — OVS återskapar ur sin databas |
| Portarna `lab-a`, `lab-b`, `lab-ids` | **Ja** — de är OVS-portar |
| Namespaces `ns-*` | **Nej** — de är flyktiga |
| IP-adresser i namespaces | **Nej** |
| OpenFlow-regler | **Nej** — de lever i vswitchd:s minne |
| Speglingar och sFlow | **Ja** — de ligger i OVS-databasen |

Efter en omstart av Proxmox finns alltså bryggan kvar men är tom på namespaces.
Kör `setup-sandbox.sh` igen — det är idempotent och lägger bara till det som
saknas.

Att OpenFlow-regler **inte** överlever är värt att veta. En regel som ser ut att
fungera perfekt försvinner vid omstart. I produktion löser man det med en
controller som programmerar om vid uppkoppling, eller med ett skript i
systemd.

## Rensa bort allt

```bash
./teardown-sandbox.sh
apt remove --purge openvswitch-switch     # om du vill ta bort paketet också
```

Efter teardown är maskinen i samma läge som innan. Produktionsbryggorna har
aldrig varit inblandade.

## En ärlig notering om övervakningen

Sandlådan syns inte i Grafana. `node-exporter` på Proxmox rapporterar interface
och systemd-enheter, men OVS-bryggan och dess namespaces ingår inte i
standardmätvärdena.

Vill du ha den i övervakningen behövs antingen `ovs-exporter` eller en
textfil-collector som kör `ovs-vsctl` och skriver mätvärden. Det är ett rimligt
nästa steg, men ingenting som finns i dag — och det ska inte förväxlas med att
sandlådan skulle vara bevakad.
