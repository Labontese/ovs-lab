#!/usr/bin/env bash
# =============================================================================
# teardown-sandbox.sh — river sandlådan fullständigt.
#
# Tar bort bryggan, portarna och namespaces. Rör ingenting annat.
# Efteråt är maskinen i exakt samma läge som innan setup-sandbox.sh kördes,
# bortsett från att paketet openvswitch-switch fortfarande är installerat.
# =============================================================================
set -uo pipefail

BR="ovsbr-lab"
PORTS=(lab-a lab-b lab-ids)

C_G=$'\033[38;5;107m'; C_R=$'\033[0;31m'; C_D=$'\033[2m'; C_0=$'\033[0m'
ok()   { echo -e "  ${C_G}✔${C_0}  $*"; }
info() { echo -e "  ${C_D}→${C_0}  $*"; }
die()  { echo -e "  ${C_R}✘${C_0}  $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Kör som root."

# --- Skyddsräcke -------------------------------------------------------------
case "$BR" in
  vmbr0|vmbr1) die "Vägrar röra produktionsbryggan $BR." ;;
esac

echo
echo "  River Open vSwitch-sandlådan"
echo "  ────────────────────────────"

# Speglingar först — de refererar portarna
if ovs-vsctl br-exists "$BR" 2>/dev/null; then
  for m in $(ovs-vsctl --columns=_uuid --bare list mirror 2>/dev/null); do
    ovs-vsctl -- --id=@m get mirror "$m" -- remove bridge "$BR" mirrors @m 2>/dev/null || true
  done
  ovs-vsctl clear bridge "$BR" mirrors 2>/dev/null || true
  ok "speglingar borttagna"

  # sFlow-konfiguration
  ovs-vsctl -- clear bridge "$BR" sflow 2>/dev/null || true
  ok "sflow rensad"
fi

# Namespaces (portarna följer med när namespacen tas bort)
for p in "${PORTS[@]}"; do
  ns="ns-$p"
  if ip netns list | grep -qw "$ns"; then
    ip netns delete "$ns" && ok "$ns borttagen"
  fi
done

# Bryggan sist
if ovs-vsctl br-exists "$BR" 2>/dev/null; then
  ovs-vsctl del-br "$BR" && ok "bryggan $BR borttagen"
else
  info "bryggan fanns inte"
fi

echo
echo "  Kvar i systemet:"
echo "    OVS-bryggor:  $(ovs-vsctl list-br 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || echo inga)"
echo "    Linux-bryggor: $(ls /sys/class/net/ | grep '^vmbr' | tr '\n' ' ')"
echo
echo "  Produktionsbryggorna är orörda."
echo
