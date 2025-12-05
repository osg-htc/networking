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

  # prefer physical NICs under /sys/class/net/<iface>/device (PCI devices)
  local _path iface
  for _path in /sys/class/net/*; do
    iface=$(basename "$_path")
    # filter common virtual interface prefixes
    if [[ "$iface" =~ ^(lo|docker|cni|veth|br-|virbr|vmnet|vnet|ovs-) ]]; then
      continue
    fi
    # physical devices appear under /sys/class/net/<iface>/device
    if [[ -d "/sys/class/net/$iface/device" ]]; then
      echo "$iface"
      continue
    fi
    # fall back: include interfaces with carrier/link detected (up or carrier)
    if ip -o link show "$iface" 2>/dev/null | grep -q 'state UP'; then
      echo "$iface"
      continue
    fi
    if command -v ethtool >/dev/null 2>&1; then
      if ethtool "$iface" 2>/dev/null | grep -q 'Link detected: yes'; then
        echo "$iface"
      fi
    fi
  done | sort -u
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

get_max_link_speed() {
  # returns max link speed in Mbps across candidate interfaces
  local max=0
  for iface in $(get_ifaces); do
    if command -v ethtool >/dev/null 2>&1; then
      local s
      s=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | tr -d '[:space:]') || continue
      # s often like '100Gb/s' or '1000Mb/s' or 'Unknown!'
      if [[ "$s" =~ ^([0-9]+)(G|M)b/s$ ]]; then
        local val=${BASH_REMATCH[1]}
        local unit=${BASH_REMATCH[2]}
        if [[ "$unit" == "G" ]]; then
          val=$((val * 1000))
        fi
        if (( val > max )); then max=$val; fi
      fi
    fi
  done
  echo "$max"
}

get_iface_speed() {
  local iface="$1"
  if ! command -v ethtool >/dev/null 2>&1; then
    echo 0
    return
  fi
  local s
  s=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | tr -d '[:space:]' || true)
  if [[ "$s" =~ ^([0-9]+)(G|M)b/s$ ]]; then
    local val=${BASH_REMATCH[1]}
    local unit=${BASH_REMATCH[2]}
    if [[ "$unit" == "G" ]]; then
      echo $((val * 1000))
    else
      echo "$val"
    fi
  else
    echo 0
  fi
}

apply_sysctl() {
  local outfile="/etc/sysctl.d/90-fasterdata.conf"
  require_root
  log_info "Writing $outfile"
  # Scale recommended values based on max NIC speed
  local max_speed_mbps
  max_speed_mbps=$(get_max_link_speed)
  log_info "Detected max link speed (Mbps): ${max_speed_mbps:-0}"

  # Choose scaled recommendations
  local rmem_max=536870912
  local wmem_max=536870912
  local default_backlog=250000
  if (( max_speed_mbps >= 100000 )); then
    # 100Gbps or higher: be more generous
    rmem_max=1073741824
    wmem_max=1073741824
    default_backlog=500000
  elif (( max_speed_mbps >= 40000 )); then
    rmem_max=536870912
    wmem_max=536870912
    default_backlog=350000
  fi

  cat > "$outfile" <<EOF
# Fasterdata-inspired tuning (https://fasterdata.es.net/)
# Applied by fasterdata-tuning.sh
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.core.rmem_default = 134217728
net.core.wmem_default = 134217728
net.core.netdev_max_backlog = ${default_backlog}
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
  printf "\nInterface: %s\n" "$iface"
  ip -brief address show "$iface"

  # Queue length
  local txqlen
  txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "?")
  echo "  txqueuelen: $txqlen (rec: >= 10000)"

  # speed
  if command -v ethtool >/dev/null 2>&1; then
    local s
    s=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | tr -d '[:space:]' || true)
    if [[ -n "$s" ]]; then
      echo "  Speed: $s"
    fi
  fi

  # ethtool settings
  if command -v ethtool >/dev/null 2>&1; then
    local offload
    offload=$(ethtool -k "$iface" 2>/dev/null | grep -E 'gro:|gso:|tso:|rx-checksumming:|tx-checksumming:|lro:') || true
    echo "  Offloads (current):"
    # indent offload lines
    if [[ -n "$offload" ]]; then
      # indent offload lines (avoid external sed usage if empty)
      if [[ -n "$offload" ]]; then
        while IFS= read -r line; do
          printf "    %s\n" "$line"
        done <<<"$offload"
      fi
    fi

    local rings
    rings=$(ethtool -g "$iface" 2>/dev/null | sed 's/^/    /') || true
    if [[ -n "$rings" ]]; then
      echo "  Rings:"
      echo "$rings"
    fi
    # driver details
    local drv
    drv=$(ethtool -i "$iface" 2>/dev/null | awk -F': ' '/driver/ {print $2}') || true
    if [[ -n "$drv" ]]; then
      echo "  driver: $drv"
    fi
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
    cur=$(cat "/sys/class/net/$iface/tx_queue_len")
    # scale queue by link speed
    local if_speed
    if_speed=$(get_iface_speed "$iface")
    local desired_txqlen=10000
    if (( if_speed >= 100000 )); then
      desired_txqlen=20000
    elif (( if_speed >= 40000 )); then
      desired_txqlen=15000
    fi
    if [[ "$cur" -lt "$desired_txqlen" ]]; then
      ip link set dev "$iface" txqueuelen "$desired_txqlen"
    fi
  fi

  if command -v ethtool >/dev/null 2>&1; then
    # Rings: set to max where available
    local max_rx max_tx
    max_rx=$(ethtool -g "$iface" 2>/dev/null | awk '/RX:/ {rx=$2} /RX max:/ {rxmax=$3} END {if(rxmax>0) print rxmax}' || true)
    max_tx=$(ethtool -g "$iface" 2>/dev/null | awk '/TX:/ {tx=$2} /TX max:/ {txmax=$3} END {if(txmax>0) print txmax}' || true)
    if [[ -n "$max_rx" ]]; then
      ethtool -G "$iface" rx "$max_rx" >/dev/null 2>&1 || true
    fi
    if [[ -n "$max_tx" ]]; then
      ethtool -G "$iface" tx "$max_tx" >/dev/null 2>&1 || true
    fi

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

apply_cpu_governor() {
  if [[ ! -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    log_warn "Cannot set CPU governor: cpufreq not supported on this host"
    return
  fi
  if command -v cpupower >/dev/null 2>&1; then
    log_info "Setting CPU governor to 'performance' using cpupower"
    cpupower frequency-set -g performance || log_warn "cpupower failed"
  else
    log_info "Setting CPU governors to 'performance' via sysfs"
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo performance >"$gov" 2>/dev/null || true
    done
  fi
}

check_cpu_governor() {
  if [[ ! -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    log_warn "cpufreq not available or governor support missing; skipping governor check"
    return
  fi
  local governors
  governors=$(for cf in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do cat "$cf" 2>/dev/null || true; done | sort -u)
  echo "CPU governors: $governors"
  if [[ "$governors" != "performance" ]]; then
    log_warn "Non 'performance' CPU governor detected: $governors (rec: performance)"
  fi
}

check_iommu() {
  # Check kernel cmdline for IOMMU options
  local cmdline
  cmdline=$(cat /proc/cmdline 2>/dev/null || true)
  if echo "$cmdline" | grep -q -E 'intel_iommu=on|amd_iommu=on|iommu=pt|iommu=on'; then
    echo "IOMMU enabled via kernel command-line: $cmdline" | sed 's/^/  /'
  else
    log_warn "IOMMU not enabled in kernel command-line (rec: intel_iommu=on or amd_iommu=on for SR-IOV/perf tuning)"
  fi
}

check_drivers() {
  for iface in $(get_ifaces); do
    if command -v ethtool >/dev/null 2>&1; then
      local drv
      drv=$(ethtool -i "$iface" 2>/dev/null | awk -F': ' '/driver/ {print $2}') || true
      echo "Interface $iface uses driver: ${drv:-unknown}"
    fi
  done
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
    apply_cpu_governor
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

  # Extra host checks
  if [[ "$MODE" == "audit" ]]; then
    check_cpu_governor
    check_iommu
    check_drivers
  fi

  if [[ "$MODE" == "apply" ]]; then
    log_info "Apply complete. Consider rebooting or rerunning audit to confirm settings."
  else
    log_info "Audit complete. Entries marked with '*' differ from recommended values."
  fi
}

main "$@"
