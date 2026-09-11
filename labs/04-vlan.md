# Labb 04 — VLAN

**Mål:** se att två portar på samma switch, i samma IP-nät, ändå inte kan nå
varandra — och förstå exakt var den separationen finns.

**Kursmål:** *"Konfigurera och administrera servrar och nätverk (Windows/Linux)"*

---

## Utgångsläget

Båda portarna är otaggade och ligger i samma broadcastdomän:

```bash
ip netns exec ns-lab-a ping -c2 10.99.0.20
```

Fungerar.

## Sätt olika VLAN

```bash
ovs-vsctl set port lab-a tag=10
ovs-vsctl set port lab-b tag=20
ovs-vsctl --columns=name,tag list port lab-a lab-b
```

```
name : lab-a    tag : 10
name : lab-b    tag : 20
```

Testa igen:

```bash
ip netns exec ns-lab-a ping -c2 10.99.0.20
```

**Nekad.** Samma switch. Samma IP-nät, 10.99.0.0/24. Samma fysiska minne i
kärnan. Ändå kommer inte paketen fram.

Det är värt att stanna vid: separationen finns **bara i switchens huvud**. Det
finns ingen brandvägg, ingen routing, inget som filtrerar. Switchen vägrar bara
flytta en ram mellan portar med olika tagg.

## Återförena

```bash
ovs-vsctl set port lab-b tag=10
ip netns exec ns-lab-a ping -c2 10.99.0.20
```

Fungerar igen. Omedelbart, utan att något startas om.

## Återställ

```bash
ovs-vsctl remove port lab-a tag 10
ovs-vsctl remove port lab-b tag 10
```

## Access kontra trunk

Det ovan är **accessportar** — porten tillhör ett VLAN och taggen sätts och tas
bort av switchen. Den anslutna maskinen vet ingenting om VLAN.

En **trunkport** bär flera VLAN samtidigt, med taggen kvar i ramen:

```bash
ovs-vsctl set port lab-a trunks=10,20,30
```

Då måste den anslutna maskinen själv hantera taggarna — precis som Proxmox gör
på `vmbr1`, där `eno1np0` är en trunk mot Junipern och varje VM får sin tagg via
`net0: virtio=...,tag=70`.

## Samma sak i ditt riktiga labb

| Sandlådan | Ditt labb |
|---|---|
| `ovs-vsctl set port lab-a tag=10` | `qm set 220 --net0 virtio,bridge=vmbr1,tag=70` |
| Otaggad port | `lan`-interfacet på pfSense |
| `trunks=10,20,30` | `eno1np0` mot Junipern, `bridge-vids 2-4094` |

Det är exakt samma mekanism. Ditt skript `new-ubuntu-vm.sh` sätter taggen via
`IFACE_VLAN`-mappningen — och det var just en **saknad tagg** som gjorde VM 208
onåbar i augusti. VM:en fungerade, sshd körde, men NIC:en satt otaggad på en
trunk och hamnade därmed i fel broadcastdomän.

Den buggen är lättare att förstå när man sett samma sak hända på två portar man
kan ta på.

## Varför det spelar roll för säkerhet

**VLAN är inte en säkerhetsgräns i sig.** Det är en konfiguration i switchen,
och konfigurationer kan vara fel.

Två klassiska problem:

**VLAN-hopping.** Om en accessport råkar bli trunk, eller om native VLAN är
felkonfigurerat, kan en angripare skicka dubbeltaggade ramar och nå VLAN den
inte ska nå. Därför sätter man native VLAN till något oanvänt och stänger av
automatisk trunkförhandling.

**Felkonfiguration.** En port i fel VLAN ger antingen ett avbrott — som VM 208
— eller tyst åtkomst till fel nät. Det senare är värre eftersom ingen märker
något.

Det är därför segmenteringen i ditt labb bör granskas: tidigare i dag visade det
sig att en labb-VM på VLAN 70 kunde nå både Proxmox API och pfSense
webbgränssnitt. VLAN:et fanns, men reglerna mellan dem släppte igenom
managementplanet.
