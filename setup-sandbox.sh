#!/usr/bin/env bash
# =============================================================================
# setup-sandbox.sh — bygger en isolerad Open vSwitch-sandlåda på Proxmox.
#
# Topologi:
#
#     ovsbr-lab  (OVS-brygga, INGEN fysisk port — rör aldrig nätet)
#        │           │            │
#      lab-a       lab-b       lab-ids
#        │           │            │
#   ns:lab-a    ns:lab-b     ns:lab-ids
#   10.99.0.10  10.99.0.20   (ingen IP, promiskuöst läge)
#
# Varje port ligger i sin egen network namespace. Det ger tre "maskiner" som
# kan prata med varandra utan att en enda VM behöver startas — och utan att
# en enda paket kan läcka ut på 10.10.0.0/24.
#
# SÄKERHET: skriptet rör INTE /etc/network/interfaces. OVS lagrar sin egen
# konfiguration i /etc/openvswitch/conf.db och återskapar bryggan efter
# omstart på egen hand. Ett fel här kan därför inte göra hypervisorn
# oåtkomlig, vilket är hela poängen med upplägget.
# =============================================================================
set -uo pipefail

BR="ovsbr-lab"
PORTS=(lab-a lab-b lab-ids)
NET="10.99.0"

C_G=$'\033[38;5;107m'; C_Y=$'\033[1;33m'; C_R=$'\033[0;31m'; C_D=$'\033[2m'; C_0=$'\033[0m'
ok()   { echo -e "  ${C_G}✔${C_0}  $*"; }
info() { echo -e "  ${C_D}→${C_0}  $*"; }
warn() { echo -e "  ${C_Y}⚠${C_0}  $*"; }
die()  { echo -e "  ${C_R}✘${C_0}  $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Kör som root."
command -v ovs-vsctl >/dev/null || die "openvswitch-switch saknas. apt install openvswitch-switch"

# --- Skyddsräcke: vägra röra produktionsbryggorna ----------------------------
for prod in vmbr0 vmbr1; do
  if [[ "$BR" == "$prod" ]]; then
    die "Vägrar. $BR är en produktionsbrygga."
  fi
done

echo
echo "  Open vSwitch-sandlåda"
echo "  ─────────────────────"

# --- 1. Bryggan --------------------------------------------------------------
if ovs-vsctl br-exists "$BR" 2>/dev/null; then
  info "$BR finns redan"
else
  ovs-vsctl add-br "$BR" || die "kunde inte skapa bryggan"
  ok "bryggan $BR skapad"
fi
ip link set "$BR" up

# --- 2. Portar + namespaces --------------------------------------------------
i=0
for p in "${PORTS[@]}"; do
  i=$((i+1))
  ns="ns-$p"

  if ! ovs-vsctl list-ports "$BR" | grep -qx "$p"; then
    ovs-vsctl add-port "$BR" "$p" -- set interface "$p" type=internal \
      || die "kunde inte lägga till porten $p"
  fi

  ip netns list | grep -qw "$ns" || ip netns add "$ns"

  # Flytta porten in i sin namespace om den inte redan är där
  if ip link show "$p" &>/dev/null; then
    ip link set "$p" netns "$ns" || die "kunde inte flytta $p till $ns"
  fi

  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip link set "$p" up

  if [[ "$p" == "lab-ids" ]]; then
    # Sensorporten får ingen adress — den ska bara lyssna.
    ip netns exec "$ns" ip link set "$p" promisc on
    ok "$p  ${C_D}(sensor, ingen IP, promiskuöst)${C_0}"
  else
    addr="${NET}.$((i*10))/24"
    ip netns exec "$ns" ip addr flush dev "$p" 2>/dev/null
    ip netns exec "$ns" ip addr add "$addr" dev "$p"
    ok "$p  ${addr%/*}"
  fi
done

# --- 3. Verifiera att de hittar varandra -------------------------------------
echo
info "kontrollerar förbindelsen ..."
if ip netns exec ns-lab-a ping -c2 -W2 "${NET}.20" >/dev/null 2>&1; then
  ok "lab-a når lab-b"
else
  warn "lab-a når INTE lab-b — kontrollera med:"
  echo "       ip netns exec ns-lab-a ping ${NET}.20"
fi

# --- 4. Sammanfattning -------------------------------------------------------
echo
echo "  Bryggan"
ovs-vsctl show | sed 's/^/    /'
echo
echo "  Namespaces"
for p in "${PORTS[@]}"; do
  printf "    %-24s %s\n" "ns-$p" \
    "$(ip netns exec "ns-$p" ip -br addr show "$p" 2>/dev/null | awk '{print $3}')"
done
echo
echo "  Nästa steg:  labs/01-portspegling.md"
echo "  Riv allt:    ./teardown-sandbox.sh"
echo
