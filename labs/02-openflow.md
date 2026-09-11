# Labb 02 — OpenFlow

**Mål:** skriva forwarding-regler för hand och se dem träffa, för att förstå vad
en SDN-controller faktiskt gör.

---

## Flödestabellen

Titta på en nyskapad brygga:

```bash
ovs-ofctl dump-flows ovsbr-lab
```

```
 cookie=0x0, duration=56.893s, table=0, n_packets=51, n_bytes=4274,
 priority=0 actions=NORMAL
```

**En enda regel.** `priority=0` är lägsta prioritet, `actions=NORMAL` betyder
"gör det en vanlig switch gör" — MAC-inlärning, uppslag, flooding vid okänd
mottagare.

Hela switchbeteendet är alltså en rad i en tabell. Det är den insikt som gör
OpenFlow begripligt: det finns inget magiskt switchlager, bara regler.

## Lägga till en regel

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,icmp,actions=drop"
```

Nu finns två regler. Ett ICMP-paket matchar båda — men 100 > 0, så den
högre prioriteten vinner och paketet slängs.

```bash
ip netns exec ns-lab-a ping -c2 10.99.0.20
```

Tystnad. Kolla tabellen:

```bash
ovs-ofctl dump-flows ovsbr-lab
```

```
 n_packets=2, n_bytes=196, priority=100,icmp actions=drop
 n_packets=53, n_bytes=4470, priority=0 actions=NORMAL
```

`n_packets=2` på drop-regeln. Paketen räknades och slängdes.

**Räknaren per regel är det som gör OpenFlow användbart vid felsökning.** Du ser
exakt vilken regel som träffar, inte bara att något inte fungerar.

## Ta bort regeln

```bash
ovs-ofctl del-flows ovsbr-lab "icmp"
ip netns exec ns-lab-a ping -c2 10.99.0.20
```

Fungerar igen.

## Regler värda att prova

**Släng bara i en riktning** — matcha på ingångsport:

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,in_port=lab-a,icmp,actions=drop"
```

lab-a kan inte pinga ut, men lab-b kan pinga in. Asymmetri som är väldigt svår
att åstadkomma med en vanlig brygga.

**Styr om trafik** istället för att slänga:

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,tcp,tp_dst=80,actions=output:lab-ids"
```

All HTTP-trafik går till sensorn i stället för mottagaren. Det är grunden i en
transparent proxy.

**Skriv om paket i farten:**

```bash
ovs-ofctl add-flow ovsbr-lab \
  "priority=100,ip,nw_dst=10.99.0.20,actions=mod_nw_dst:10.99.0.30,NORMAL"
```

Destinationsadressen byts innan vidarebefordran. Det är DNAT, utan brandvägg.

**Matcha på MAC i stället för IP:**

```bash
ovs-ofctl add-flow ovsbr-lab "priority=100,dl_src=aa:bb:cc:dd:ee:ff,actions=drop"
```

Portsäkerhet i sin enklaste form.

## Se hur ett paket skulle behandlas

Utan att skicka det:

```bash
ovs-appctl ofproto/trace ovsbr-lab in_port=lab-a,icmp,nw_src=10.99.0.10,nw_dst=10.99.0.20
```

Verktyget går igenom tabellerna och visar vilken regel som träffar och vad som
händer. Ovärderligt när man har många regler och något inte beter sig som tänkt.

## Rensa allt

```bash
ovs-ofctl del-flows ovsbr-lab
ovs-ofctl add-flow ovsbr-lab "priority=0,actions=NORMAL"
```

Andra raden är viktig: tar du bort *alla* regler finns inget som säger åt
bryggan att switcha, och all trafik dör. Det är ett bra fel att göra en gång i
sandlådan och aldrig i produktion.

## Det här i verkligheten

I drift skriver man sällan flöden för hand. En **SDN-controller** — Faucet, ONOS,
OpenDaylight — håller en policy och programmerar switcharna utifrån den. Man
beskriver *vad* som ska gälla; controllern räknar ut reglerna.

Men controllern gör exakt det du nyss gjorde manuellt. Har man skrivit reglerna
själv en gång blir det betydligt lättare att felsöka när controllern gör något
oväntat.

Det är också så molnnätverk fungerar under ytan. AWS security groups och Azure
NSG:er är i grunden flödesregler som programmeras in i virtuella switchar av ett
kontrollplan — samma idé, industriell skala.
