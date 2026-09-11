# ovs-lab — Open vSwitch-sandlåda på Proxmox

En isolerad Open vSwitch-miljö för att lära sig portspegling, OpenFlow, sFlow
och VLAN utan att kunna ta ner något.

Byggd 2026-09-11 på hemlabbets Proxmox (Dell R730xd, `10.10.0.3`).

---

## Vad det är

Tre "maskiner" kopplade till en OVS-brygga som **inte har någon fysisk port**.
Varje maskin är en network namespace med en intern OVS-port — inga VM:ar behöver
startas, och ingen trafik kan lämna bryggan.

```
              ovsbr-lab   (OVS-brygga, ingen uppgång)
        ┌─────────┼─────────┐
      lab-a     lab-b    lab-ids
        │         │         │
    ns-lab-a  ns-lab-b  ns-lab-ids
   10.99.0.10 10.99.0.20   sensor
```

## Varför den ser ut så

Proxmox kör allt: Holm Digitals produktion, kveld.se, skolans labbmaskiner,
Windows-mallarna. Ett fel i `/etc/network/interfaces` och hypervisorn kommer upp
utan nät — då står allt tills någon är fysiskt vid maskinen.

Därför:

- **`/etc/network/interfaces` rörs aldrig.** Bryggan skapas med `ovs-vsctl` och
  lagras i OVS egen databas (`/etc/openvswitch/conf.db`), som återskapar den
  efter omstart utan att Debians nätverksuppstart är inblandad.
- **Ingen fysisk port.** Bryggan kan inte nå 10.10.0.0/24 ens vid grov
  felkonfiguration.
- **Skyddsräcke i skripten.** Både setup och teardown vägrar köra mot `vmbr0`
  eller `vmbr1`.

`vmbr0` och `vmbr1` är alltså orörda och fortsätter vara vanliga Linux-bryggor.

## Kom igång

```bash
scp -r ovs-lab root@10.10.0.3:/root/
ssh root@10.10.0.3
cd /root/ovs-lab
./setup-sandbox.sh
```

Riv allt igen:

```bash
./teardown-sandbox.sh
```

Efter teardown är maskinen i exakt samma läge som innan, bortsett från att
paketet `openvswitch-switch` finns kvar installerat.

## Labbarna

Alla fyra är körda och verifierade på riktig hårdvara, inte bara nedskrivna.

| Labb | Vad du lär dig |
|---|---|
| [01 — Portspegling](labs/01-portspegling.md) | Varför en IDS inte ser något utan spegel, och hur man ger den trafik |
| [02 — OpenFlow](labs/02-openflow.md) | Att skriva forwarding-regler för hand och se dem träffa |
| [03 — sFlow](labs/03-sflow.md) | Trafikstatistik genom sampling, och skillnaden mot NetFlow |
| [04 — VLAN](labs/04-vlan.md) | Isolering på samma switch och samma IP-nät |

## Läs det här först

**[docs/hur-det-hanger-ihop.md](docs/hur-det-hanger-ihop.md)** — förklarar vad en
switch faktiskt gör, varför OVS skiljer sig från Linux-bryggan, hur ett paket
färdas genom sandlådan, och hur varje teknik motsvarar något i riktig utrustning
och i ISCX26:s kursmål.

**[docs/sakerhet-och-risk.md](docs/sakerhet-och-risk.md)** — vad som faktiskt är
riskabelt, vad som inte är det, och vad man ska låta bli.

## Miljön

| | |
|---|---|
| Värd | Proxmox VE 9.2.18, Dell R730xd |
| OVS | 3.5.0 (`openvswitch-switch`, Debian-paket) |
| Nätkort | Mellanox ConnectX-4 Lx, dubbelport — `eno2np1` ledig med tom SFP+-bur |
| Produktionsbryggor | `vmbr0` 10.10.0.2 (1 GbE), `vmbr1` 10.10.0.3 (10 GbE) |

## Vad som inte ingår

Sandlådan har inga fysiska portar, så den visar varken kabelfel, MTU-problem,
verklig prestanda eller spanning tree. För det behövs `eno2np1` och en kabel —
eller den andra EX4200:an som står oanvänd.
