# Hur allt hänger ihop

En förklaring från grunden av vad sandlådan faktiskt gör, varför den ser ut som
den gör, och hur det kopplar till riktig nätverksutrustning och till ISCX26.

---

## 1. Vad en switch egentligen gör

En switch har **en enda uppgift**: ta emot en ram på en port och skicka den
vidare på rätt port. För att kunna det bygger den en tabell.

När en ram kommer in tittar switchen på **avsändarens MAC-adress** och antecknar
"den adressen nås via port 3". Det kallas *MAC-inlärning*. När den sedan ska
skicka något till den adressen slår den upp i tabellen.

Vet den inte var mottagaren finns gör den det enda rimliga: skickar ut ramen på
**alla** portar utom den den kom in på. Det kallas *flooding*. Svaret avslöjar
var mottagaren sitter, och nästa gång behöver den inte gissa.

Det är hela switchen. Allt annat — VLAN, spegling, QoS — är lager ovanpå.

---

## 2. En switch i mjukvara

Din Proxmox är en switch. `vmbr0` och `vmbr1` är Linux-bryggor: mjukvaruswitchar
som gör exakt det som beskrivs ovan, fast i kärnan istället för i kisel.

```
  VM 220 ──┐
  VM 208 ──┼── vmbr1 ──── eno1np0 ──── Juniper EX4200 ──── resten av nätet
  VM 209 ──┘   (brygga)   (10 GbE)
```

Linux-bryggan är bra på sitt jobb. Den lär sig MAC-adresser, hanterar VLAN när
man sätter `bridge-vlan-aware yes`, och är enkel att förstå.

**Open vSwitch är också en mjukvaruswitch** — men byggd på en annan idé.

---

## 3. Skillnaden: flödestabellen

Linux-bryggan har sin logik *inbyggd*. Den gör MAC-inlärning för att det är så
den är skriven. Du kan konfigurera den, men inte ändra hur den tänker.

OVS har istället en **flödestabell** — en lista med regler som säger "matchar
paketet det här, gör då det här". Switchbeteendet är bara en regel bland andra.

Kör du `ovs-ofctl dump-flows ovsbr-lab` på en nyskapad brygga ser du:

```
 cookie=0x0, duration=56.893s, table=0, n_packets=51, n_bytes=4274,
 priority=0 actions=NORMAL
```

En enda regel. `priority=0` betyder lägsta prioritet, `actions=NORMAL` betyder
"bete dig som en vanlig switch". Det är alltså Linux-bryggans hela beteende,
uttryckt som *en rad i en tabell*.

Och eftersom det är en tabell kan du lägga till egna rader med högre prioritet:

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,icmp,actions=drop"
```

Nu finns två regler. Ett ICMP-paket matchar båda, men prioritet 100 slår
prioritet 0, så det slängs. All annan trafik matchar bara `NORMAL` och
switchas som vanligt.

**Det är hela skillnaden.** Linux-bryggan är en switch. OVS är en maskin som
kan *fås att bete sig* som en switch — eller som något helt annat.

---

## 4. Varför sandlådan inte behöver några VM:ar

För att testa en switch behövs något att koppla in. Normalt startar man VM:ar.
Sandlådan gör något billigare.

En **network namespace** är en isolerad nätverksstack i kärnan: egna interface,
egen routingtabell, egen brandvägg. Processer som körs i en namespace ser bara
den. Det är samma mekanism Docker använder för containernätverk.

Sandlådan skapar tre *interna portar* på bryggan och flyttar in var och en i sin
egen namespace:

```
              ovsbr-lab
        ┌─────────┼─────────┐
      lab-a     lab-b    lab-ids
        │         │         │
    ns-lab-a  ns-lab-b  ns-lab-ids
   10.99.0.10 10.99.0.20  (ingen IP)
```

`ip netns exec ns-lab-a ping 10.99.0.20` kör alltså ping *som om* den satt på
en egen maskin kopplad till switchen. Trafiken går på riktigt genom OVS.

Vinsten: tre "maskiner" som startar på en halv sekund, använder nästan inget
minne, och som inte kan nå 10.10.0.0/24 eftersom bryggan saknar fysisk port.

---

## 5. Ett pakets resa genom sandlådan

När `lab-a` pingar `lab-b`:

1. **ARP först.** lab-a vet inte lab-b:s MAC-adress. Den skickar en
   broadcast-fråga: "vem har 10.99.0.20?"
2. OVS får ramen på porten `lab-a`. Den antecknar lab-a:s MAC. Mottagaren är
   broadcast, så regeln `NORMAL` säger: skicka på alla andra portar.
3. Ramen når både `lab-b` och `lab-ids`.
4. **lab-b svarar.** Nu lär sig OVS var lab-b finns.
5. **ICMP echo request** går från lab-a. Den här gången vet OVS var lab-b
   sitter och skickar bara dit — inte till lab-ids.
6. lab-b svarar med echo reply.

Steg 5 är viktigt: **sensorn ser ingenting** när switchen väl lärt sig
adresserna. Det är precis vad testet visade — noll paket på lab-ids innan
speglingen slogs på.

Det är också varför portspegling behövs alls. En switch *skyddar* trafik från
att synas på andra portar. Ska en IDS se den måste man explicit be om det.

---

## 6. De fyra teknikerna, och vad de heter i verkligheten

### Portspegling

```bash
ovs-vsctl -- set bridge ovsbr-lab mirrors=@m \
  -- --id=@ids get port lab-ids \
  -- --id=@m create mirror name=spegla-allt select-all=true output-port=@ids
```

Switchen skickar en **kopia** av varje ram till sensorporten. Originalet går sin
väg opåverkat.

I riktig utrustning heter det här **SPAN** (Cisco) eller **port mirroring**
(de flesta andra). Din Juniper EX4200 kan det — `analyzer`-konfiguration. Det är
så man matar en Suricata, Zeek eller Wazuh med trafik utan att sätta den i
vägen för den.

Skillnaden mot en inline-IDS är viktig: en spegel kan inte blockera något, bara
observera. Den kan inte heller orsaka avbrott om sensorn kraschar. Det är
därför spegling är standardsättet att börja.

### OpenFlow

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,icmp,actions=drop"
```

Att skriva forwarding-regler för hand. I produktion gör man sällan det — då
sitter en **SDN-controller** (Faucet, ONOS, OpenDaylight) och skriver reglerna
programmatiskt utifrån en policy.

Men att göra det för hand är det enda sättet att förstå vad controllern gör.
`n_packets`-räknaren på varje regel visar exakt hur många paket som träffat
den, vilket gör felsökning ovanligt konkret.

### sFlow

```bash
ovs-vsctl -- --id=@s create sflow agent=lo target=\"127.0.0.1:6343\" \
  header=128 sampling=2 polling=5 -- set bridge ovsbr-lab sflow=@s
```

**Sampling.** Switchen tar vart N:te paket, klipper ut de första `header` byten,
och skickar till en insamlare. `sampling=2` betyder vartannat paket — absurt
högt, men bra i labb. I produktion är 1:1000 eller 1:4096 normalt.

Poängen är att man får statistisk trafikbild utan att kopiera allt. Skillnaden
mot **NetFlow/IPFIX** är att de bygger på *flöden* — switchen håller reda på
konversationer och rapporterar sammanfattningar. sFlow samplar paket. Båda finns
i OVS.

### VLAN

```bash
ovs-vsctl set port lab-a tag=10
ovs-vsctl set port lab-b tag=20
```

Samma sak som `tag=` i din `qm`-konfiguration och samma sak som access-portar på
Junipern. Två portar med olika tagg **kan inte nå varandra** även om de sitter
på samma switch och samma IP-nät. Testet visade det: samma adressrymd, ping
nekad, tills båda fick samma tagg.

Det är fysiskt samma koppar eller fiber — separationen finns bara i switchens
huvud. Det är därför VLAN-hopping är en attackklass, och varför en felkonfad
trunk är allvarlig.

---

## 7. Hur det kopplar till ditt riktiga labb

Sandlådan är en miniatyr av det du redan kör:

| Sandlådan | Ditt labb |
|---|---|
| `ovsbr-lab` | `vmbr1` på Proxmox |
| `lab-a`, `lab-b` | VM 208, VM 220, kveld … |
| `tag=10` / `tag=20` | VLAN 10–90 på vmbr1 |
| `lab-ids` | en Suricata- eller Wazuh-VM |
| Ingen fysisk port | `eno1np0`, 10 GbE till Junipern |

Skillnaden är att sandlådan inte har någon uppgång. Gör du fel där händer
ingenting utanför bryggan. Gör du samma fel på `vmbr1` tappar hypervisorn nätet
och allt du äger står — inklusive kveld och Holm Digital.

Det är hela anledningen till att sandlådan finns.

---

## 8. Hur det kopplar till ISCX26

Utbildningsplanen (MYH 2025/4008) listar bland färdigheterna:

- **"Analysera och åtgärda systemintrång enligt protokoll"** — portspegling till
  en IDS är förutsättningen. Utan spegel ser sensorn ingenting.
- **"Konfigurera och administrera servrar och nätverk"** — VLAN-labben är exakt
  det, fast där man kan se felet direkt istället för att gissa.
- **"Informationssäkerhet och övergripande IT-säkerhetsåtgärder"** — sFlow in i
  Grafana ger trafikbild, vilket är grunden för att upptäcka avvikelser.

Och bland kunskaperna: *"Nätverk och relaterade teknologier som brandväggar,
routrar och switchar"*. Den här sandlådan är switchdelen, i en form där man kan
ta sönder saker.

---

## 9. En sak som ofta blandas ihop

**Hetzners "vSwitch" är inte Open vSwitch.**

Hetzner vSwitch är deras egen produkt: ett privat VLAN mellan dina dedikerade
servrar, konfigurerat i Robot, levererat som 802.1Q-taggad trafik på serverns
befintliga uplink. Du lägger upp ett VLAN-ID i deras gränssnitt och konfigurerar
ett taggat subinterface i servern.

Open vSwitch är mjukvaran som kör *inuti* en maskin. Den kan mycket väl användas
för att terminera en Hetzner vSwitch-VLAN, men det är två olika saker med
olyckligt lika namn.

---

## 10. Vad sandlådan *inte* visar

Ärlighet om gränserna:

- **Ingen fysisk trafik.** Allt går i kärnan. Du ser inte kabelfel, duplexfel,
  MTU-problem mot Junipern eller vad en trasig SFP gör.
- **Ingen prestanda att mäta.** Interna portar går i minnet och säger inget om
  vad 10 GbE klarar.
- **Ingen spanning tree.** Sandlådan har ingen loop och ingen redundans, så
  STP/RSTP-beteende syns inte.
- **Ingen controller.** OpenFlow-labben skriver regler för hand. En riktig
  SDN-uppsättning har en controller som gör det utifrån policy.

För de bitarna behövs fysiska portar — `eno2np1` står tom med ledig SFP+-bur,
och du har en andra EX4200 som inte är i drift.
