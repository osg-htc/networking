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
#   - Apply mode updates /etc/sysctl.conf with recommended parameters and applies live settings.
#   - ethtool changes are immediate but not persisted across reboots; consider
#     running this script from a boot-time unit if persistence is required.

set -euo pipefail
# Ignore SIGPIPE to avoid non-zero exits when output is piped/truncated
trap '' PIPE

LOGFILE=${LOGFILE:-/tmp/fasterdata-tuning-$(date -u +%Y%m%dT%H%M%SZ).log}
SYSCTL_MISMATCHES=0
MISSING_TOOLS=()
IF_ISSUES=()
DRIVER_UPDATES=()
TARGET_TYPE="measurement"
MAX_LINK_SPEED=0
SCALED_RMEM_MAX=536870912
SCALED_WMEM_MAX=536870912
SCALED_BACKLOG=250000
RUNNING_KERNEL=""
LATEST_KERNEL=""
USE_COLOR=0

# Color codes for terminal output
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_RED='\033[0;31m'
readonly C_RESET='\033[0m'

MODE="audit"
IFACES=""
APPLY_IOMMU=0
APPLY_SMT=""
PERSIST_SMT=0
AUTO_YES=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: fasterdata-tuning.sh [--mode audit|apply] [--ifaces "eth0,eth1"] [--target measurement|dtn] [--color] [--verbose]

Modes:
  audit   (default) Show current values vs. Fasterdata recommendations
  apply             Apply recommended values (requires root)

Options:
  --ifaces LIST     Comma-separated interfaces to check/tune. Default: all up, non-loopback
  --target TYPE     Host type: measurement (default) or dtn (data transfer node)
  --color           Use color codes (green=ok, yellow=warning, red=critical)
  --apply-iommu     (apply only) Edit GRUB to enable IOMMU (intel/amd flags + iommu=pt)
  --apply-smt STATE Apply runtime SMT change (on|off). Requires --mode apply
  --persist-smt     (apply only) Also persist SMT choice via GRUB changes (adds/removes 'nosmt')
  --yes             Skip interactive confirmations (use with caution)
  --dry-run         Preview the exact GRUB/sysfs changes without applying them (safe)
  --verbose         More detail in audit output
  -h, --help        Show this help
EOF
}

init_log() {
  if [[ -z "$LOGFILE" ]]; then
    log_warn "LOGFILE is empty; detailed logging disabled"
    return
  fi
  if : >"$LOGFILE" 2>/dev/null; then
    log_info "Detailed log: $LOGFILE"
  else
    log_warn "Cannot write log file $LOGFILE; disabling detailed log"
    LOGFILE=""
  fi
}

log() { echo "$*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_info() { echo "[INFO] $*"; }

colorize() {
  local level="$1" text="$2"
  [[ $USE_COLOR -eq 0 ]] && { echo "$text"; return; }
  case "$level" in
    green) echo -e "${C_GREEN}${text}${C_RESET}";;
    yellow) echo -e "${C_YELLOW}${text}${C_RESET}";;
    red) echo -e "${C_RED}${text}${C_RESET}";;
    *) echo "$text";;
  esac
}

log_detail() {
  [[ -z "$LOGFILE" ]] && return
  printf "%s\n" "$*" >>"$LOGFILE" 2>/dev/null || true
}

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
  # Collect candidate interfaces, preferring physical PCI devices, even if link is down
  local candidates=()
  for _path in /sys/class/net/*; do
    iface=$(basename "$_path")
    # filter common virtual interface prefixes
    if [[ "$iface" =~ ^(lo|docker|cni|veth|br-|virbr|vmnet|vnet|ovs-) ]]; then
      continue
    fi
    if [[ -d "/sys/class/net/$iface/device" ]]; then
      candidates+=("$iface")
      continue
    fi
    # fall back: include interfaces with carrier/link detected (up or carrier)
    if ip -o link show "$iface" 2>/dev/null | grep -q 'state UP'; then
      candidates+=("$iface")
      continue
    fi
    if command -v ethtool >/dev/null 2>&1; then
      if ethtool "$iface" 2>/dev/null | grep -q 'Link detected: yes'; then
        candidates+=("$iface")
      fi
    fi
  done

  # De-duplicate and print
  if [[ ${#candidates[@]} -gt 0 ]]; then
    printf "%s\n" "${candidates[@]}" | sort -u
  fi
}

desired_txqlen_for_speed() {
  local speed_mbps="$1"
  local base=10000
  [[ "$TARGET_TYPE" == "dtn" ]] && base=12000
  if (( speed_mbps >= 100000 )); then
    [[ "$TARGET_TYPE" == "dtn" ]] && base=25000 || base=20000
  elif (( speed_mbps >= 40000 )); then
    [[ "$TARGET_TYPE" == "dtn" ]] && base=18000 || base=15000
  fi
  echo "$base"
}

print_sysctl_diff() {
  local key wanted current status
  log_detail "Sysctl audit (current vs recommended)"
  printf "\nSysctl audit (current vs recommended)\n"
  printf "%-35s %-35s %-35s\n" "Key" "Current" "Recommended"
  printf '%0.105s\n' "-------------------------------------------------------------------------------------------------"
  for key in "${!SYSCTL_RECS[@]}"; do
    wanted=${SYSCTL_RECS[$key]}
    current=$(sysctl -n "$key" 2>/dev/null || echo "(unset)")
    status=""
    # Normalize whitespace (tabs and multiple spaces) into single spaces for comparison
    # using awk's field re-assignment which converts all whitespace to single spaces
    local current_normalized=$(echo "$current" | awk '{$1=$1; print}')
    local wanted_normalized=$(echo "$wanted" | awk '{$1=$1; print}')
    if [[ "$current_normalized" != "$wanted_normalized" ]]; then
      status="*"
      ((SYSCTL_MISMATCHES+=1))
      log_detail "SYSCTL mismatch: $key current='$current' recommended='$wanted'"
    else
      log_detail "SYSCTL ok: $key=$current"
    fi
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

set_speed_scaled_recs() {
  MAX_LINK_SPEED=$(get_max_link_speed)
  SCALED_RMEM_MAX=536870912
  SCALED_WMEM_MAX=536870912
  SCALED_BACKLOG=250000
  if (( MAX_LINK_SPEED >= 100000 )); then
    SCALED_RMEM_MAX=1073741824
    SCALED_WMEM_MAX=1073741824
    SCALED_BACKLOG=500000
  elif (( MAX_LINK_SPEED >= 40000 )); then
    SCALED_RMEM_MAX=536870912
    SCALED_WMEM_MAX=536870912
    SCALED_BACKLOG=350000
  fi
  if [[ "$TARGET_TYPE" == "dtn" ]]; then
    if (( MAX_LINK_SPEED >= 100000 )); then
      SCALED_BACKLOG=600000
    elif (( MAX_LINK_SPEED >= 40000 )); then
      SCALED_BACKLOG=400000
    fi
  fi
  SYSCTL_RECS[net.core.rmem_max]=$SCALED_RMEM_MAX
  SYSCTL_RECS[net.core.wmem_max]=$SCALED_WMEM_MAX
  SYSCTL_RECS[net.core.netdev_max_backlog]=$SCALED_BACKLOG
}

cache_kernel_versions() {
  RUNNING_KERNEL=$(uname -r 2>/dev/null || true)
  LATEST_KERNEL=""
  if command -v dnf >/dev/null 2>&1; then
    LATEST_KERNEL=$(dnf -q list --showduplicates kernel 2>/dev/null | grep kernel.x86_64 | awk '{print $2}' | sort -V | tail -1)
  fi
}

apply_sysctl() {
  local sysctl_file="/etc/sysctl.conf"
  if [[ $DRY_RUN -ne 1 ]]; then
    require_root
  fi
  log_info "Updating $sysctl_file with fasterdata tuning parameters"
  # backup existing file
  if [[ -f "$sysctl_file" ]]; then
    local timestamp
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    cp -a "$sysctl_file" "${sysctl_file}.${timestamp}.bak" 2>/dev/null || true
    log_info "Backed up existing $sysctl_file to ${sysctl_file}.${timestamp}.bak"
  fi
  log_info "Detected max link speed (Mbps): ${MAX_LINK_SPEED:-0}"

  # Update or add each sysctl parameter in /etc/sysctl.conf
  local updates=(
    "net.core.rmem_max=${SCALED_RMEM_MAX}"
    "net.core.wmem_max=${SCALED_WMEM_MAX}"
    "net.core.rmem_default=134217728"
    "net.core.wmem_default=134217728"
    "net.core.netdev_max_backlog=${SCALED_BACKLOG}"
    "net.core.default_qdisc=fq"
    "net.ipv4.tcp_rmem=4096 87380 536870912"
    "net.ipv4.tcp_wmem=4096 65536 536870912"
    "net.ipv4.tcp_congestion_control=bbr"
    "net.ipv4.tcp_mtu_probing=1"
    "net.ipv4.tcp_window_scaling=1"
    "net.ipv4.tcp_timestamps=1"
    "net.ipv4.tcp_sack=1"
    "net.ipv4.tcp_low_latency=0"
  )
  
  for update in "${updates[@]}"; do
    local key="${update%%=*}"
    local value="${update#*=}"
    local escaped_key="${key//./\\.}"
    if grep -q "^${escaped_key}=" "$sysctl_file" 2>/dev/null; then
      sed -i "s|^${escaped_key}=.*|${update}|" "$sysctl_file"
    else
      echo "$update" >> "$sysctl_file"
    fi
  done
  
  if ! has_bbr; then
    log_warn "bbr not available; falling back to cubic at runtime (file still sets bbr)"
  fi
  log_info "Applying sysctl settings"
  sysctl -p "$sysctl_file" >/dev/null 2>&1 || sysctl --system >/dev/null
  # If bbr missing, set congestion control to cubic live to avoid failure
  if ! has_bbr; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null
  fi
}

iface_audit() {
  local iface="$1"
  local state txqlen if_speed desired_txqlen qdisc driver
  state=$(ip -o link show "$iface" 2>/dev/null | awk '{print $9}')
  txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "?")
  if_speed=$(get_iface_speed "$iface")
  desired_txqlen=$(desired_txqlen_for_speed "$if_speed")

  local speed_str="${if_speed}Mb/s"
  if command -v ethtool >/dev/null 2>&1; then
    local raw_speed
    raw_speed=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}' | tr -d '[:space:]' || true)
    [[ -n "$raw_speed" ]] && speed_str="$raw_speed"
  fi

  qdisc=$(tc qdisc show dev "$iface" 2>/dev/null | head -n1 | awk '{print $2,$3,$4}')
  driver="unknown"
  if command -v ethtool >/dev/null 2>&1; then
    driver=$(ethtool -i "$iface" 2>/dev/null | awk -F': ' '/driver/ {print $2}') || true
  fi

  local offload_devs offload_issue="ok"
  if command -v ethtool >/dev/null 2>&1; then
    offload_devs=$(ethtool -k "$iface" 2>/dev/null | grep -E 'gro:|gso:|tso:|rx-checksumming:|tx-checksumming:|lro:' || true)
    if [[ "$offload_devs" =~ lro:[[:space:]]*on ]]; then
      offload_issue="lro on"
    fi
    if ! echo "$offload_devs" | grep -q 'rx-checksumming:.*on'; then
      offload_issue="rx csum off"
    fi
    if ! echo "$offload_devs" | grep -q 'tx-checksumming:.*on'; then
      offload_issue="tx csum off"
    fi
  else
    offload_issue="missing ethtool"
    MISSING_TOOLS+=("ethtool (dnf install ethtool)")
  fi

  local rings_cur rings_max rings_note=""
  if command -v ethtool >/dev/null 2>&1; then
    rings_cur=$(ethtool -g "$iface" 2>/dev/null | awk '/RX:/ {rx=$2} /TX:/ {tx=$2} END {print rx"/"tx}') || true
    rings_max=$(ethtool -g "$iface" 2>/dev/null | awk '/RX max:/ {rx=$3} /TX max:/ {tx=$3} END {print rx"/"tx}') || true
    if [[ -n "$rings_cur" && -n "$rings_max" && "$rings_max" =~ ^[0-9]+/[0-9]+$ && "$rings_cur" != "$rings_max" ]]; then
      rings_note="rings $rings_cur (max $rings_max)"
    fi
  fi

  local short_line="$(printf "%-12s state=%-7s speed=%-9s txqlen=%-6s(rec>=%-5s) qdisc=%-6s driver=%s" "$iface" "${state:-?}" "$speed_str" "$txqlen" "$desired_txqlen" "${qdisc:-?}" "$driver")"
  printf "\n%s" "$short_line"
  local offload_str="offload=${offload_issue}"
  [[ -n "$rings_note" ]] && offload_str+=" $rings_note"
  printf " %s\n" "$offload_str"

  # Track issues for summary
  local issues=()
  if [[ "$txqlen" != "?" && "$txqlen" -lt "$desired_txqlen" ]]; then
    issues+=("txqlen $txqlen<${desired_txqlen}")
  fi
  # Extract just the first word of qdisc (e.g., "fq" from "fq 8005: root")
  local qdisc_type="${qdisc%% *}"
  if [[ "${qdisc_type:-}" != "fq" ]]; then
    issues+=("qdisc=${qdisc:-unknown}")
  fi
  if [[ "$offload_issue" != "ok" ]]; then
    issues+=("$offload_issue")
  fi
  if [[ -n "$rings_note" ]]; then
    issues+=("$rings_note")
  fi
  if (( ${#issues[@]} > 0 )); then
    IF_ISSUES+=("$iface: ${issues[*]}")
  fi

  # Detailed log: capture full interface state
  log_detail "==== Interface $iface ===="
  log_detail "State: ${state:-unknown} Speed: $speed_str Driver: $driver"
  log_detail "txqueuelen: $txqlen (rec >= $desired_txqlen)"
  if command -v ip >/dev/null 2>&1; then
    log_detail "$(ip -brief address show "$iface" 2>/dev/null)"
  fi
  if command -v ethtool >/dev/null 2>&1; then
    log_detail "-- ethtool -k $iface --"
    log_detail "$(ethtool -k "$iface" 2>/dev/null)"
    log_detail "-- ethtool -g $iface --"
    log_detail "$(ethtool -g "$iface" 2>/dev/null)"
    log_detail "-- ethtool -i $iface --"
    log_detail "$(ethtool -i "$iface" 2>/dev/null)"
  fi
  log_detail "-- tc qdisc show dev $iface --"
  log_detail "$(tc qdisc show dev "$iface" 2>/dev/null)"
}

iface_apply() {
  local iface="$1"
  log_info "Tuning interface $iface"

  # txqueuelen
  if [[ -f /sys/class/net/$iface/tx_queue_len ]]; then
    local cur
    cur=$(cat "/sys/class/net/$iface/tx_queue_len")
    # scale queue by link speed and target type
    local if_speed
    if_speed=$(get_iface_speed "$iface")
    local desired_txqlen
    desired_txqlen=$(desired_txqlen_for_speed "$if_speed")
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

create_ethtool_persist_service() {
  # Generates systemd service to persist ethtool settings across reboots
  local svcfile="/etc/systemd/system/ethtool-persist.service"
  local dry_run=${1:-0}
  if [[ $DRY_RUN -ne 1 ]]; then
    require_root
  fi
  
  log_info "Generating $svcfile to persist ethtool settings"
  
  # Build list of ExecStart commands from applied ethtool changes
  local exec_cmds=()
  local iface
  for iface in $(get_ifaces); do
    if ! command -v ethtool >/dev/null 2>&1; then
      continue
    fi
    
    # Capture desired ring settings
    local max_rx max_tx
    max_rx=$(ethtool -g "$iface" 2>/dev/null | awk '/RX max:/ {print $3}' || true)
    max_tx=$(ethtool -g "$iface" 2>/dev/null | awk '/TX max:/ {print $3}' || true)
    if [[ -n "$max_rx" && -n "$max_tx" ]]; then
      exec_cmds+=("ExecStart=/sbin/ethtool -G $iface rx $max_rx tx $max_tx")
    fi
    
    # Capture offload settings (all on except LRO off)
    exec_cmds+=("ExecStart=/sbin/ethtool -K $iface gro on gso on tso on rx on tx on lro off")
    
    # Capture txqueuelen
    local txqlen
    txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null)
    if [[ -n "$txqlen" && "$txqlen" != "?" ]]; then
      exec_cmds+=("ExecStart=/sbin/ip link set dev $iface txqueuelen $txqlen")
    fi
  done
  
  # Show what would be written (always to log; to stdout if requested)
  {
    echo "[Unit]"
    echo "Description=Persist ethtool settings (Fasterdata)"
    echo "After=network.target"
    echo "Wants=network.target"
    echo ""
    echo "[Service]"
    echo "Type=oneshot"
    for cmd in "${exec_cmds[@]}"; do
      echo "$cmd"
    done
    echo "RemainAfterExit=yes"
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } | tee >(cat >>"$LOGFILE" 2>/dev/null)
  
  # Only write file if dry_run is 0
  if [[ $dry_run -eq 0 ]]; then
    {
      echo "[Unit]"
      echo "Description=Persist ethtool settings (Fasterdata)"
      echo "After=network.target"
      echo "Wants=network.target"
      echo ""
      echo "[Service]"
      echo "Type=oneshot"
      for cmd in "${exec_cmds[@]}"; do
        echo "$cmd"
      done
      echo "RemainAfterExit=yes"
      echo ""
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } > "$svcfile"
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable ethtool-persist.service
    log_info "Enabled ethtool-persist.service; to verify, run: systemctl status ethtool-persist"
  fi
}

ensure_tuned_profile() {
  if ! command -v tuned-adm >/dev/null 2>&1; then
    log_warn "tuned-adm not installed; skipping tuned profile"
    MISSING_TOOLS+=("tuned-adm (dnf install tuned)")
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
  if ! command -v cpupower >/dev/null 2>&1; then
    MISSING_TOOLS+=("cpupower (dnf install kernel-tools)")
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
  local cmdline cpu_vendor iommu_cmd
  cmdline=$(cat /proc/cmdline 2>/dev/null || true)
  
  # Detect CPU vendor (Intel vs AMD) per Fasterdata recommendations
  if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="Intel"
    iommu_cmd="intel_iommu=on iommu=pt"
  elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="AMD"
    iommu_cmd="amd_iommu=on iommu=pt"
  else
    cpu_vendor="unknown"
    iommu_cmd="iommu=pt (with intel_iommu=on or amd_iommu=on)"
  fi
  
  if echo "$cmdline" | grep -q -E 'intel_iommu=on|amd_iommu=on|iommu=pt|iommu=on'; then
    echo "IOMMU enabled via kernel command-line: $cmdline" | sed 's/^/  /'
  else
    log_warn "IOMMU not enabled in kernel command-line (CPU: $cpu_vendor, rec: $iommu_cmd for SR-IOV/perf tuning)"
    echo "IOMMU setup: Edit GRUB configuration to enable IOMMU (per Fasterdata):"
    echo "  1. Edit /etc/default/grub"
    echo "  2. Add to GRUB_CMDLINE_LINUX: $iommu_cmd"
    echo "  3. Example: GRUB_CMDLINE_LINUX=\"root=... $iommu_cmd ...\""
    echo "  4. Regenerate GRUB: grub2-mkconfig -o /boot/grub2/grub.cfg"
    echo "  5. Reboot the system for changes to take effect"
    echo "  6. Verify with: cat /proc/cmdline (should show iommu=pt)"
  fi
}

apply_iommu() {
  # Apply GRUB edits to enable IOMMU (intel/amd + iommu=pt) if requested. Safe, interactive by default.
  if [[ "$MODE" != "apply" ]]; then
    log_warn "--apply-iommu ignored unless --mode apply"
    return
  fi
  require_root
  local cmdline
  cmdline=$(cat /proc/cmdline 2>/dev/null || true)
  local cpu_vendor iommu_cmd
  if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="Intel"
    iommu_cmd="intel_iommu=on iommu=pt"
  elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="AMD"
    iommu_cmd="amd_iommu=on iommu=pt"
  else
    cpu_vendor="unknown"
    iommu_cmd="iommu=pt"
  fi
  if echo "$cmdline" | grep -q -E 'iommu=pt|intel_iommu=on|amd_iommu=on'; then
    log_info "IOMMU appears to be enabled: $cmdline"
    return
  fi
  log_warn "IOMMU not in kernel cmdline (CPU: $cpu_vendor). Will add: $iommu_cmd"
  local backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo
    echo "=== IOMMU change PREVIEW ==="
    echo "Current kernel cmdline: $cmdline"
    echo "Would ensure GRUB_CMDLINE_LINUX contains: $iommu_cmd"
    echo "The script would backup /etc/default/grub to $backup and run grub2-mkconfig -o /boot/grub2/grub.cfg (or update-grub)"
    return
  fi
  if [[ $AUTO_YES -ne 1 ]]; then
    read -r -p "Update /etc/default/grub and regenerate GRUB to add '$iommu_cmd'? [y/N] " resp
    if [[ ! "$resp" =~ ^[Yy]$ ]]; then
      log_info "Skipping GRUB edit for IOMMU"
      return
    fi
  fi
  # Backup grub config
  local backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry-run: would copy /etc/default/grub -> $backup"
  else
    cp -a /etc/default/grub "$backup"
    log_info "Backed up /etc/default/grub to $backup"
  fi
  # Read existing value and ensure we append without duplicates
  local existing
  existing=$(awk -F= '/^GRUB_CMDLINE_LINUX=/ { match($0,/=("|")(.*)\1/,m); print m[2]; exit }' /etc/default/grub || true)
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -z "$existing" ]]; then
      echo "Dry-run: would set GRUB_CMDLINE_LINUX=\"$iommu_cmd\""
    else
      if echo "$existing" | grep -qF "$iommu_cmd"; then
        echo "Dry-run: GRUB already contains required IOMMU flags"
      else
        local newval="$existing $iommu_cmd"
        echo "Dry-run: would update GRUB_CMDLINE_LINUX to: $newval"
      fi
    fi
  else
    if [[ -z "$existing" ]]; then
      echo "GRUB_CMDLINE_LINUX=\"$iommu_cmd\"" >> /etc/default/grub
    else
      if echo "$existing" | grep -qF "$iommu_cmd"; then
        log_info "GRUB already contains required IOMMU flags"
      else
        # Append flags
        local newval="$existing $iommu_cmd"
        # Replace the line
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
      fi
    fi
  fi
  # Regenerate grub
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry-run: would run grub2-mkconfig -o /boot/grub2/grub.cfg or update-grub"
    return
  fi
  if command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
  elif command -v update-grub >/dev/null 2>&1; then
    update-grub || true
  else
    log_warn "No grub2-mkconfig or update-grub found; edit /etc/default/grub manually"
    return
  fi
  log_info "GRUB config updated; please reboot to apply IOMMU settings"
}

apply_smt() {
  # Apply SMT changes at runtime and optionally persist via GRUB (adds/removes 'nosmt')
  if [[ "$MODE" != "apply" ]]; then
    log_warn "--apply-smt ignored unless --mode apply"
    return
  fi
  require_root
  if [[ ! -r /sys/devices/system/cpu/smt/control ]]; then
    log_warn "SMT control not available on this system"
    return
  fi
  local cur=$(cat /sys/devices/system/cpu/smt/control)
  if [[ "$APPLY_SMT" != "on" && "$APPLY_SMT" != "off" ]]; then
    log_warn "Invalid or missing --apply-smt STATE (expected 'on' or 'off')"
    return
  fi
  if [[ "$cur" == "$APPLY_SMT" ]]; then
    log_info "SMT already set to $cur"
  else
    log_warn "Changing SMT from $cur to $APPLY_SMT"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo
      echo "=== SMT change PREVIEW ==="
      echo "Current SMT: $cur"
      echo "Would run: echo $APPLY_SMT | sudo tee /sys/devices/system/cpu/smt/control"
      echo "Dry-run: SMT will not be changed. Use --mode apply without --dry-run to apply."
      return
    fi
    if [[ $AUTO_YES -ne 1 ]]; then
      read -r -p "Apply SMT change now (writes to /sys/devices/system/cpu/smt/control)? [y/N] " resp
      if [[ ! "$resp" =~ ^[Yy]$ ]]; then
        log_info "SMT change cancelled"
        return
      fi
    fi
    echo "$APPLY_SMT" | tee /sys/devices/system/cpu/smt/control >/dev/null
    log_info "SMT set to $APPLY_SMT"
  fi
  # If persist requested, update grub kernel cmdline
  if [[ $PERSIST_SMT -eq 1 ]]; then
    local grubnosmt
    if [[ "$APPLY_SMT" == "off" ]]; then
      grubnosmt="nosmt"
    else
      grubnosmt=""
    fi
    # Edit GRUB similar to apply_iommu (backup/append/remove nosmt)
    local backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Dry-run: would copy /etc/default/grub -> $backup"
    else
      cp -a /etc/default/grub "$backup"
      log_info "Backed up /etc/default/grub to $backup"
    fi
    local existing
    existing=$(awk -F= '/^GRUB_CMDLINE_LINUX=/ { match($0,/=("|")(.*)\1/,m); print m[2]; exit }' /etc/default/grub || true)
    if [[ $DRY_RUN -eq 1 ]]; then
      if [[ -z "$existing" ]]; then
        if [[ -n "$grubnosmt" ]]; then
          echo "Dry-run: would set GRUB_CMDLINE_LINUX=\"$grubnosmt\""
        else
          echo "Dry-run: would not change GRUB_CMDLINE_LINUX (no nosmt present)"
        fi
      else
        if [[ -n "$grubnosmt" ]]; then
          if echo "$existing" | grep -qF "$grubnosmt"; then
            echo "Dry-run: GRUB already contains $grubnosmt"
          else
            local newval="$existing $grubnosmt"
            echo "Dry-run: would update GRUB_CMDLINE_LINUX to: $newval"
          fi
        else
          # Remove nosmt bit if present (preview)
          local newval=$(echo "$existing" | sed 's/\bnosmt\b//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
          echo "Dry-run: would update GRUB_CMDLINE_LINUX to: $newval"
        fi
      fi
    else
      if [[ -z "$existing" ]]; then
        if [[ -n "$grubnosmt" ]]; then
          echo "GRUB_CMDLINE_LINUX=\"$grubnosmt\"" >> /etc/default/grub
        fi
      else
        if [[ -n "$grubnosmt" ]]; then
          if echo "$existing" | grep -qF "$grubnosmt"; then
            log_info "GRUB already contains $grubnosmt"
          else
            local newval="$existing $grubnosmt"
            sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
          fi
        else
          # Remove nosmt bit if present
          local newval=$(echo "$existing" | sed 's/\bnosmt\b//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
          sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
        fi
      fi
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Dry-run: would run grub2-mkconfig -o /boot/grub2/grub.cfg or update-grub"
      return
    fi
    if command -v grub2-mkconfig >/dev/null 2>&1; then
      grub2-mkconfig -o /boot/grub2/grub.cfg
    elif command -v update-grub >/dev/null 2>&1; then
      update-grub || true
    else
      log_warn "No grub2-mkconfig or update-grub found; edit /etc/default/grub manually"
      return
    fi
    log_info "GRUB updated to persist SMT change; reboot to apply"
  fi
}

print_host_info() {
  local os_release kernel_ver mem_info_str fqdn smt_status cpu_info cpu_vendor
  os_release=$(awk -F'=' '/^PRETTY_NAME/ {print $2}' /etc/os-release 2>/dev/null | tr -d '"')
  kernel_ver=$(uname -r)
  fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
  local mem_total_kb
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
  if [[ -n "$mem_total_kb" ]]; then
    local mem_gb=$((mem_total_kb / 1024 / 1024))
    mem_info_str="${mem_gb} GiB"
  else
    mem_info_str="unknown"
  fi
  
  # Get CPU info
  local cpu_count cpu_model cpu_mhz
  cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "unknown")
  if grep -q '^vendor_id.*GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="Intel"
  elif grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
    cpu_vendor="AMD"
  else
    cpu_vendor="unknown"
  fi
  cpu_model=$(awk -F':' '/^model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | xargs)
  # Extract CPU clock speed from /proc/cpuinfo (try cpu MHz first, fallback to max freq)
  cpu_mhz=$(awk -F':' '/^cpu MHz/ {print int($2); exit}' /proc/cpuinfo 2>/dev/null)
  if [[ -z "$cpu_mhz" ]] || [[ "$cpu_mhz" -eq 0 ]]; then
    # Try /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq (in kHz)
    local max_freq_khz
    max_freq_khz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
    if [[ -n "$max_freq_khz" ]]; then
      cpu_mhz=$((max_freq_khz / 1000))
    fi
  fi
  local cpu_speed_str=""
  if [[ -n "$cpu_mhz" ]] && [[ "$cpu_mhz" -gt 0 ]]; then
    # Convert MHz to GHz using bash arithmetic
    local cpu_ghz_int=$((cpu_mhz / 1000))
    local cpu_ghz_frac=$(((cpu_mhz % 1000 + 50) / 100))  # Round to 1 decimal place
    cpu_speed_str=" @ ${cpu_ghz_int}.${cpu_ghz_frac} GHz"
  fi
  if [[ -n "$cpu_model" ]]; then
    cpu_info="$cpu_count cores, $cpu_vendor: $cpu_model$cpu_speed_str"
  else
    cpu_info="$cpu_count cores, $cpu_vendor$cpu_speed_str"
  fi
  
  # Check SMT status
  if [[ -r /sys/devices/system/cpu/smt/control ]]; then
    smt_status=$(cat /sys/devices/system/cpu/smt/control)
    if [[ "$smt_status" == "on" ]]; then
      smt_status="$(colorize green "on")"
    else
      smt_status="$(colorize yellow "$smt_status")"
    fi
  else
    smt_status="not available"
  fi
  
  echo "Host Info:"
  echo "  FQDN: $fqdn"
  echo "  OS: ${os_release:-unknown}"
  echo "  Kernel: $kernel_ver"
  echo "  Memory: $mem_info_str"
  echo "  CPUs: $cpu_info"
  echo "  SMT: $smt_status"
}

check_smt() {
  if [[ ! -r /sys/devices/system/cpu/smt/control ]]; then
    log_detail "SMT control not available on this system"
    return
  fi
  local smt_status
  smt_status=$(cat /sys/devices/system/cpu/smt/control)
  log_detail "SMT status: $smt_status"
  
  if [[ "$smt_status" != "on" ]]; then
    log_warn "SMT is currently $smt_status (recommendation: on for measurement hosts; off for low-latency/isolated workloads)"
    echo "SMT control: to enable, run: echo on | sudo tee /sys/devices/system/cpu/smt/control"
    echo "SMT control: to disable, run: echo off | sudo tee /sys/devices/system/cpu/smt/control"
  fi
}

driver_vendor_hint() {
  case "$1" in
    mlx5_core|mlx4_en|mlx4_core) echo "Mellanox/NVIDIA";;
    bnxt_en|tg3|bnx2x|bnx2) echo "Broadcom";;
    ixgbe|i40e|ice|e1000e|igb) echo "Intel";;
    *) echo "Other";;
  esac
}

check_drivers() {
  if ! command -v ethtool >/dev/null 2>&1; then
    log_warn "ethtool not installed; skipping driver version checks"
    MISSING_TOOLS+=("ethtool (dnf install ethtool)")
    return
  fi

  local -A vendor_hint_seen=()
  local kernel_hint_added=0
  echo "Driver info:"
  for iface in $(get_ifaces); do
    local info
    info=$(ethtool -i "$iface" 2>/dev/null)
    local drv version fw bus
    drv=$(awk -F': ' '/driver:/ {print $2}' <<<"$info")
    version=$(awk -F': ' '/version:/ {print $2}' <<<"$info")
    fw=$(awk -F': ' '/firmware-version:/ {print $2}' <<<"$info")
    bus=$(awk -F': ' '/bus-info:/ {print $2}' <<<"$info")
    local vendor
    vendor=$(driver_vendor_hint "$drv")
    local modpath pkg pkgver
    modpath=$(modinfo -n "$drv" 2>/dev/null || true)
    pkg=$(rpm -q --whatprovides "$modpath" 2>/dev/null | head -n1 || true)

    log_detail "Driver $iface: driver=$drv version=${version:-unknown} firmware=${fw:-unknown} vendor=${vendor:-unknown} pkg=${pkg:-unknown} bus=${bus:-unknown}"
    echo "  $iface: driver=$drv version=${version:-unknown} firmware=${fw:-unknown} vendor=${vendor:-unknown} pkg=${pkg:-unknown}"

    local kernel_hint=""
    if [[ -n "$LATEST_KERNEL" && -n "$RUNNING_KERNEL" ]]; then
      local latest_base="${LATEST_KERNEL%.x86_64}"
      local running_base="${RUNNING_KERNEL%.x86_64}"
      if [[ "$latest_base" != "$running_base" ]]; then
        kernel_hint="Kernel update available: dnf update kernel && reboot (current: $RUNNING_KERNEL, latest: $LATEST_KERNEL)."
      fi
    fi

    local vendor_hint=""
    case "$vendor" in
      "Mellanox/NVIDIA") vendor_hint="For ConnectX/mlx5, keep kernel+linux-firmware current or use NVIDIA OFED if required (see https://network.nvidia.com/products/ethernet-drivers/).";;
      "Broadcom") vendor_hint="Broadcom NICs track the distro kernel; keep kernel+linux-firmware current and use vendor firmware tools (e.g., bnxtnvm) when available.";;
      "Intel") vendor_hint="Intel NICs track the distro kernel; update kernel+linux-firmware for latest drivers/firmware blobs.";;
      *) vendor_hint="Keep kernel+linux-firmware current for latest in-kernel drivers.";;
    esac

    if [[ -n "$kernel_hint" && $kernel_hint_added -eq 0 ]]; then
      DRIVER_UPDATES+=("$kernel_hint")
      kernel_hint_added=1
    fi
    if [[ -n "$vendor_hint" && -z "${vendor_hint_seen[$vendor]+x}" ]]; then
      DRIVER_UPDATES+=("$vendor_hint")
      vendor_hint_seen[$vendor]=1
    fi
  done
}

print_summary() {
  printf "\nSummary:\n"
  echo "- Target type: $TARGET_TYPE"
  echo "- Sysctl mismatches: $SYSCTL_MISMATCHES"
  if (( ${#IF_ISSUES[@]} > 0 )); then
    echo "- Interfaces needing attention (${#IF_ISSUES[@]}):"
    for item in "${IF_ISSUES[@]}"; do
      echo "  * $item"
    done
  else
    echo "- Interfaces needing attention: none"
  fi

  if (( ${#DRIVER_UPDATES[@]} > 0 )); then
    local -A seen_drv=()
    local unique_drv=()
    for t in "${DRIVER_UPDATES[@]}"; do
      if [[ -z "${seen_drv[$t]+x}" ]]; then
        seen_drv[$t]=1
        unique_drv+=("$t")
      fi
    done
    echo "- Driver/version actions:"
    for t in "${unique_drv[@]}"; do
      echo "  * $t"
    done
  else
    echo "- Driver/version actions: none"
  fi

  if (( ${#MISSING_TOOLS[@]} > 0 )); then
    # de-duplicate
    local -A seen=()
    local unique=()
    for t in "${MISSING_TOOLS[@]}"; do
      if [[ -z "${seen[$t]+x}" ]]; then
        seen[$t]=1
        unique+=("$t")
      fi
    done
    echo "- Install these tools for best results:"
    for t in "${unique[@]}"; do
      echo "  * $t"
    done
  else
    echo "- Required tools: present"
  fi

  if [[ -n "$LOGFILE" ]]; then
    echo "- Detailed log: $LOGFILE"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) MODE="$2"; shift 2;;
      --ifaces) IFACES="$2"; shift 2;;
      --target) TARGET_TYPE="$2"; shift 2;;
      --color) USE_COLOR=1; shift;;
      --apply-iommu) APPLY_IOMMU=1; shift;;
      --apply-smt) APPLY_SMT="$2"; shift 2;;
      --persist-smt) PERSIST_SMT=1; shift;;
      --yes) AUTO_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; usage; exit 1;;
    esac
  done

  if [[ "$TARGET_TYPE" != "measurement" && "$TARGET_TYPE" != "dtn" ]]; then
    echo "ERROR: --target must be measurement or dtn" >&2
    exit 1
  fi

  init_log
  set_speed_scaled_recs
  cache_kernel_versions

  if [[ "$MODE" != "audit" && "$MODE" != "apply" ]]; then
    echo "ERROR: --mode must be audit or apply" >&2; exit 1
  fi
  [[ "$MODE" == "apply" ]] && require_root

  # Validate apply flags
  if [[ -n "$APPLY_SMT" ]]; then
    if [[ "$APPLY_SMT" != "on" && "$APPLY_SMT" != "off" ]]; then
      echo "ERROR: --apply-smt requires 'on' or 'off'" >&2
      exit 1
    fi
  fi
  if [[ $PERSIST_SMT -eq 1 && -z "$APPLY_SMT" ]]; then
    echo "ERROR: --persist-smt requires --apply-smt to be set" >&2
    exit 1
  fi

  if [[ "$MODE" == "audit" ]]; then
    print_host_info
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
    check_smt
    check_drivers
  fi

  if [[ "$MODE" == "apply" ]]; then
    create_ethtool_persist_service
    # Apply optional additional host changes requested via flags
    if [[ $APPLY_IOMMU -eq 1 ]]; then
      apply_iommu
    fi
    if [[ -n "$APPLY_SMT" ]]; then
      apply_smt
    fi
    log_info "Apply complete. Consider rebooting or rerunning audit to confirm settings."
  else
    log_info "Audit complete. Entries marked with '*' differ from recommended values."
  fi

  print_summary
}

main "$@"
