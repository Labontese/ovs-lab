# Labb 03 — sFlow

**Mål:** få ut trafikstatistik ur switchen utan att kopiera all trafik, och
förstå skillnaden mot NetFlow och mot portspegling.

---

## Tre sätt att se trafik

| Metod | Vad du får | Kostnad |
|---|---|---|
| **Portspegling** | Varje byte, exakt | Dubblerar trafiken på sensorlänken |
| **sFlow** | Vart N:te paket, klippt | Nästan ingen |
| **NetFlow / IPFIX** | Sammanfattning per flöde | Låg, men switchen måste hålla tillstånd |

Spegling är rätt när man behöver innehållet — signaturer, nyttolast, en IDS.
sFlow är rätt när man behöver veta *vem pratar med vem, hur mycket*.

## Slå på sFlow

```bash
ovs-vsctl -- --id=@s create sflow \
    agent=lo \
    target=\"127.0.0.1:6343\" \
    header=128 \
    sampling=2 \
    polling=5 \
  -- set bridge ovsbr-lab sflow=@s
```

| Parameter | Betydelse |
|---|---|
| `agent` | Interface vars IP används som avsändaridentitet |
| `target` | Insamlarens adress och port (6343 är standard) |
| `header` | Hur många byte av varje samplat paket som skickas |
| `sampling` | Vart N:te paket samplas |
| `polling` | Hur ofta räknarstatistik skickas, i sekunder |

`sampling=2` betyder vartannat paket. Absurt högt, men bra i labb där man vill
se något direkt. I produktion är 1:1000 till 1:4096 normalt — på en 10 GbE-länk
skulle 1:2 dränka insamlaren.

## Bevisa att det skickas

Utan insamlare kan man ändå se datagrammen lämna maskinen:

```bash
# Terminal 1
tcpdump -i lo -nn udp port 6343

# Terminal 2
ip netns exec ns-lab-a ping -c20 -i0.2 -s800 10.99.0.20
```

```
IP 127.0.0.1.47570 > 127.0.0.1.6343: sFlowv5, IPv4 agent 127.0.0.1,
   agent-id 0, length 1324
```

`-s800` ger större paket, vilket gör samplingen tydligare.

## Läsa innehållet

`tcpdump` visar bara att datagram kommer. För att se *vad* de innehåller behövs
en avkodare:

```bash
apt install sflowtool
sflowtool -p 6343
```

Då får man ut käll- och destinationsadresser, portar, protokoll och
paketstorlekar per sampel.

## Vägen vidare: in i Grafana

Du har redan VictoriaMetrics och Grafana på `monitoring` (10.10.0.52). sFlow
kan inte skickas dit direkt — VictoriaMetrics förstår Prometheus-format, inte
sFlow. Det behövs ett mellanled som avkodar och exponerar mätvärden.

Alternativ:

- **`sflow-exporter`** eller **pmacct** — avkodar sFlow, exponerar
  Prometheus-mätvärden. Enklast att koppla ihop med det du har.
- **Alloy** — du kör den redan på kveld för loggar. Den har en
  `otelcol.receiver`-familj men inte sFlow direkt.
- **ntopng** — komplett trafikanalys med eget gränssnitt. Mer verktyg än du
  behöver för ett labb, men mycket tydligt visuellt.

Det är ett naturligt nästa steg när sandlådan kopplas till riktig trafik.

## Stäng av

```bash
ovs-vsctl clear bridge ovsbr-lab sflow
```

## Det här i verkligheten

sFlow finns i praktiskt taget all datacenterutrustning — inklusive din Juniper
EX4200. Det är så man svarar på frågor som "vad åt upp uplinken i tisdags
kväll" utan att spela in terabyte trafik.

Två saker att vara medveten om:

**Sampling är statistik, inte sanning.** Vid 1:4096 syns stora flöden tydligt,
men ett litet flöde kan missas helt. För säkerhetsanalys av enskilda
förbindelser räcker det inte — då behövs spegling.

**Agent-adressen spelar roll.** Insamlaren identifierar switchen på den. Sätter
man `agent=lo` på flera maskiner ser de likadana ut i insamlaren.
