# Labb 01 — Portspegling

**Mål:** förstå varför en IDS inte ser någon trafik, och hur man ger den trafik
utan att sätta den i vägen.

**Kursmål:** *"Analysera och åtgärda systemintrång enligt protokoll"*

---

## Bakgrunden

En switch är byggd för att trafik **inte** ska synas på andra portar än
mottagarens. Det är hela vitsen med en switch jämfört med en hubb.

Det betyder att en IDS som kopplas in på en ledig port ser i praktiken
ingenting — bara broadcast och sin egen trafik. Vill man att den ska se något
måste switchen aktivt be:as om en kopia.

## Steg 1 — bevisa problemet

Starta en lyssnare på sensorporten och generera trafik mellan de andra två:

```bash
# Terminal 1
ip netns exec ns-lab-ids tcpdump -i lab-ids -nn icmp

# Terminal 2
ip netns exec ns-lab-a ping -c4 10.99.0.20
```

**Förväntat resultat: noll paket.** Sensorn sitter på samma switch, samma
IP-nät, och ser ändå ingenting.

Det första ARP-anropet syns möjligen, eftersom broadcast går till alla portar.
Men så fort switchen lärt sig var lab-b sitter skickas ICMP bara dit.

## Steg 2 — slå på speglingen

```bash
ovs-vsctl -- set bridge ovsbr-lab mirrors=@m \
  -- --id=@ids get port lab-ids \
  -- --id=@m create mirror name=spegla-allt \
       select-all=true output-port=@ids
```

Raden läser: *skapa en spegel som väljer all trafik och skickar den till porten
lab-ids, och koppla den till bryggan.*

`@m` och `@ids` är tillfälliga referenser inom kommandot — OVS behöver kunna
peka på objekt som skapas i samma anrop.

## Steg 3 — samma test igen

```bash
ip netns exec ns-lab-ids tcpdump -i lab-ids -nn icmp
ip netns exec ns-lab-a ping -c4 10.99.0.20
```

Nu syns allt:

```
IP 10.99.0.10 > 10.99.0.20: ICMP echo request, id 7424, seq 1, length 64
IP 10.99.0.20 > 10.99.0.10: ICMP echo reply,   id 7424, seq 1, length 64
```

Både fråga och svar — speglingen tar trafik i båda riktningarna.

## Steg 4 — titta på räknaren

```bash
ovs-vsctl --columns=name,statistics list mirror
```

```
name       : spegla-allt
statistics : {tx_bytes=854, tx_packets=9}
```

Räknaren är användbar i felsökning: får sensorn ingenting men räknaren tickar,
sitter problemet i sensorn. Tickar den inte alls är speglingen fel uppsatt.

## Varianter värda att prova

**Spegla bara ett VLAN** istället för allt:

```bash
ovs-vsctl -- set bridge ovsbr-lab mirrors=@m \
  -- --id=@ids get port lab-ids \
  -- --id=@m create mirror name=spegla-vlan70 \
       select-vlan=70 output-port=@ids
```

**Spegla bara en port, bara i en riktning:**

```bash
ovs-vsctl -- set bridge ovsbr-lab mirrors=@m \
  -- --id=@a get port lab-a \
  -- --id=@ids get port lab-ids \
  -- --id=@m create mirror name=bara-fran-a \
       select-src-port=@a output-port=@ids
```

`select-src-port` och `select-dst-port` styr riktningen. På en hårt belastad
länk är det skillnaden mellan en sensor som hinner med och en som tappar paket.

## Städa upp

```bash
ovs-vsctl clear bridge ovsbr-lab mirrors
```

## Det här i verkligheten

Tekniken heter **SPAN** hos Cisco och **port mirroring** eller **analyzer** hos
de flesta andra, inklusive din Juniper EX4200. Konfigurationen ser annorlunda ut
men principen är identisk.

Två saker är värda att bära med sig:

**En spegel kan inte blockera.** Den observerar. Ska trafik stoppas måste
sensorn sitta *inline*, vilket innebär att den blir en felkälla — kraschar den
står länken. Därför börjar man nästan alltid med spegling.

**Speglingen kostar bandbredd.** Speglar du en 10 GbE-länk till en 1 GbE-port
tappas paket tyst. På fysiska switchar är det en klassisk fälla: IDS:en ser 80 %
av trafiken och ingen märker att den missar resten.
