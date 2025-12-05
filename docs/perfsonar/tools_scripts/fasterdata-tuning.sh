#!/usr/bin/env bash
# fasterdata-tuning.sh
# --------------------
# Audit and optionally apply host/network tuning recommended by ESnet Fasterdata
# for high-throughput hosts (EL9 focus). Defaults to audit-only.
#
# Sources: https://fasterdata.es.net/host-tuning/ , /network-tuning/ , /DTN/
#
# Modes:
#   --mode audit   (default)  -> read current settings, show differences
#   --mode apply               -> apply recommended values (requires root)
#
# Scope:
#   - Sysctl networking parameters (buffers, congestion control, qdisc)
#   - Tuned profile suggestion (network-throughput)
#   - Per-interface checks: GRO/TSO/GSO/checksums, LRO off, ring buffers to max,
#     txqueuelen, qdisc fq
#
# Notes:
#   - Uses conservative recommendations suitable for perfSONAR/DTN-style hosts on EL9.
#   - Apply mode writes /etc/sysctl.d/90-fasterdata.conf and applies live settings.
#   - ethtool changes are immediate but not persisted across reboots; consider
#     running this script from a boot-time unit if persistence is required.

set -euo pipefail

MODE="audit"
IFACES=""

usage() {
  cat <<'EOF'
Usage: fasterdata-tuning.sh [--mode audit|apply] [--ifaces "eth0,eth1"] [--verbose]

Modes:
  audit   (default) Show current values vs. Fasterdata recommendations
  apply             Apply recommended values (requires root)

Options:
  --ifaces LIST     Comma-separated interfaces to check/tune. Default: all up, non-loopback
  --verbose         More detail in audit output
  -h, --help        Show this help
EOF
}

log() { echo "$*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_info() { echo "[INFO] $*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: --mode apply requires root" >&2
    exit 1
  fi
}

# Recommended sysctl values (Fasterdata-inspired, EL9 context)
declare -A SYSCTL_RECS=(
  [net.core.rmem_max]=536870912
  [net.core.wmem_max]=536870912
  [net.core.rmem_default]=134217728
  [net.core.wmem_default]=134217728
  [net.core.netdev_max_backlog]=250000
  [net.core.default_qdisc]=fq
  [net.ipv4.tcp_rmem]="4096 87380 536870912"
  [net.ipv4.tcp_wmem]="4096 65536 536870912"
  [net.ipv4.tcp_congestion_control]=bbr
  [net.ipv4.tcp_mtu_probing]=1
  [net.ipv4.tcp_window_scaling]=1
  [net.ipv4.tcp_timestamps]=1
  [net.ipv4.tcp_sack]=1
  [net.ipv4.tcp_low_latency]=0
)

has_bbr() {
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr
}

get_ifaces() {
  if [[ -n "$IFACES" ]]; then
    echo "$IFACES" | tr ',' ' '
    return
  fi
  ip -o link show up | awk -F': ' '{print $2}' | grep -vE '^(lo|docker|cni|veth|br-)' || true
}

print_sysctl_diff() {
  local key wanted current status
  printf "\nSysctl audit (current vs recommended)\n"
  printf "%-35s %-35s %-35s\n" "Key" "Current" "Recommended"
  printf '%0.105s\n' "-------------------------------------------------------------------------------------------------"
  for key in "${!SYSCTL_RECS[@]}"; do
    wanted=${SYSCTL_RECS[$key]}
    current=$(sysctl -n "$key" 2>/dev/null || echo "(unset)")
    status=""
    [[ "$current" == "$wanted" ]] || status="*"
    printf "%-35s %-35s %-35s %s\n" "$key" "$current" "$wanted" "$status"
  done
}

apply_sysctl() {
  local outfile="/etc/sysctl.d/90-fasterdata.conf"
  require_root
  log_info "Writing $outfile"
  cat > "$outfile" <<'EOF'
# Fasterdata-inspired tuning (https://fasterdata.es.net/)
# Applied by fasterdata-tuning.sh
net.core.rmem_max = 536870912
net.core.wmem_max = 536870912
net.core.rmem_default = 134217728
net.core.wmem_default = 134217728
net.core.netdev_max_backlog = 250000
net.core.default_qdisc = fq
net.ipv4.tcp_rmem = 4096 87380 536870912
net.ipv4.tcp_wmem = 4096 65536 536870912
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_low_latency = 0
EOF
  if ! has_bbr; then
    log_warn "bbr not available; falling back to cubic at runtime (file still sets bbr)"
  fi
  log_info "Applying sysctl settings"
  sysctl --system >/dev/null
  # If bbr missing, set congestion control to cubic live to avoid failure
  if ! has_bbr; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
  fi
}

iface_audit() {
  local iface="$1"
  echo "\nInterface: $iface"
  ip -brief address show "$iface"

  # Queue length
  local txqlen
  txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "?")
  echo "  txqueuelen: $txqlen (rec: >= 10000)"

  # ethtool settings
  if command -v ethtool >/dev/null 2>&1; then
    local offload
    offload=$(ethtool -k "$iface" 2>/dev/null | grep -E 'gro:|gso:|tso:|rx-checksumming:|tx-checksumming:|lro:') || true
    echo "  Offloads (current):"
    echo "$offload" | sed 's/^/    /'

    local rings
    rings=$(ethtool -g "$iface" 2>/dev/null | sed 's/^/    /') || true
    [[ -n "$rings" ]] && echo "  Rings:" && echo "$rings"
  else
    echo "  ethtool not installed; skipping offload/ring audit"
  fi

  # qdisc
  local qdisc
  qdisc=$(tc qdisc show dev "$iface" 2>/dev/null | head -n1 | awk '{print $2,$3,$4}')
  echo "  qdisc: ${qdisc:-unknown} (rec: fq)"
}

iface_apply() {
  local iface="$1"
  log_info "Tuning interface $iface"

  # txqueuelen
  if [[ -f /sys/class/net/$iface/tx_queue_len ]]; then
    local cur
    cur=$(cat /sys/class/net/$iface/tx_queue_len)
    if [[ "$cur" -lt 10000 ]]; then
      ip link set dev "$iface" txqueuelen 10000
    fi
  fi

  if command -v ethtool >/dev/null 2>&1; then
    # Rings: set to max where available
    local max_rx max_tx
    max_rx=$(ethtool -g "$iface" 2>/dev/null | awk '/RX:/ {rx=$2} /RX max:/ {rxmax=$3} END {if(rxmax>0) print rxmax}' || true)
    max_tx=$(ethtool -g "$iface" 2>/dev/null | awk '/TX:/ {tx=$2} /TX max:/ {txmax=$3} END {if(txmax>0) print txmax}' || true)
    [[ -n "$max_rx" ]] && ethtool -G "$iface" rx "$max_rx" >/dev/null 2>&1 || true
    [[ -n "$max_tx" ]] && ethtool -G "$iface" tx "$max_tx" >/dev/null 2>&1 || true

    # Offloads: enable GRO/GSO/TSO, checksums; disable LRO
    ethtool -K "$iface" gro on gso on tso on rx on tx on >/dev/null 2>&1 || true
    ethtool -K "$iface" lro off >/dev/null 2>&1 || true
  fi

  # qdisc fq
  tc qdisc replace dev "$iface" root fq >/dev/null 2>&1 || true
}

ensure_tuned_profile() {
  if ! command -v tuned-adm >/dev/null 2>&1; then
    log_warn "tuned-adm not installed; skipping tuned profile"
    return
  fi
  local active
  active=$(tuned-adm active 2>/dev/null | awk '{print $3}' || true)
  if [[ "$MODE" == "audit" ]]; then
    echo "tuned-adm active: ${active:-unknown} (rec: network-throughput)"
  else
    if [[ "$active" != "network-throughput" ]]; then
      log_info "Setting tuned profile to network-throughput"
      tuned-adm profile network-throughput || log_warn "Failed to set tuned profile"
    fi
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) MODE="$2"; shift 2;;
      --ifaces) IFACES="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; usage; exit 1;;
    esac
  done

  if [[ "$MODE" != "audit" && "$MODE" != "apply" ]]; then
    echo "ERROR: --mode must be audit or apply" >&2; exit 1
  fi
  [[ "$MODE" == "apply" ]] && require_root

  if [[ "$MODE" == "audit" ]]; then
    print_sysctl_diff
  else
    if ! has_bbr; then
      log_warn "bbr not available; will set cubic live but leave bbr in config"
    fi
    apply_sysctl
  fi

  ensure_tuned_profile

  local ifs
  ifs=$(get_ifaces)
  for iface in $ifs; do
    if [[ "$MODE" == "audit" ]]; then
      iface_audit "$iface"
    else
      iface_apply "$iface"
    fi
  done

  if [[ "$MODE" == "apply" ]]; then
    log_info "Apply complete. Consider rebooting or rerunning audit to confirm settings."
  else
    log_info "Audit complete. Entries marked with '*' differ from recommended values."
  fi
}

main "$@"
