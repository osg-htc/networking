#!/usr/bin/env bash
# fasterdata-tuning.sh
# --------------------
# Version: 1.2.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# Audit and optionally apply host/network tuning recommended by ESnet Fasterdata
# for high-throughput hosts (EL9 focus). Defaults to audit-only.
#
# NEW in v1.2.0: Save/restore state functionality for testing configurations
#
# Sources: https://fasterdata.es.net/host-tuning/ , /network-tuning/ , /DTN/
#
# What this script does:
#   - Audits sysctl network parameters (TCP buffers, congestion control, qdisc, MTU probing)
#   - Checks tuned profile (recommends network-throughput)
#   - Per-NIC checks: GRO/TSO/GSO on, LRO off, checksums on, ring buffers at max,
#     txqueuelen scaled by link speed, qdisc fq
#   - TCP congestion control: detects available algorithms, prefers BBR, applies if requested
#   - Jumbo frames: checks MTU 9000 capability, applies if requested
#   - Reverse DNS: validates forward/reverse DNS matches for all NICs, displays all FQDNs
#   - IPv6: checks for dual-stack configuration (IPv4 + IPv6)
#   - Driver updates: checks kernel version, suggests updates for NIC drivers
#   - Speed-specific recommendations: tuning values scaled by NIC speed (10G/25G/40G/100G/200G/400G)
#
# Modes:
#   --mode audit   (default)  -> read current settings, show differences
#   --mode apply               -> apply recommended values (requires root)
#
# Apply mode actions:
#   - Writes sysctl settings to /etc/sysctl.d/90-fasterdata.conf
#   - Applies live sysctl changes
#   - Generates /etc/systemd/system/ethtool-persist.service for NIC settings persistence
#   - Optional: --apply-tcp-cc ALGORITHM  -> sets TCP congestion control
#   - Optional: --apply-jumbo              -> sets MTU 9000 on capable NICs
#   - Optional: --apply-iommu              -> adds iommu=pt to GRUB config
#   - Optional: --apply-smt on|off         -> enables/disables SMT
#   - Optional: --persist-smt              -> makes SMT setting persistent in GRUB
#   - Optional: --apply-packet-pacing       -> enables packet pacing (DTN targets only)
#   - Optional: --packet-pacing-rate RATE   -> set packet pacing rate (e.g., 2000mbps)
#
# Notes:
#   - Ethtool settings persist via systemd service created in apply mode
#   - Sysctl settings persist via /etc/sysctl.d/90-fasterdata.conf
#   - Color output is enabled by default; use --nocolor to disable
#   - JSON machine-readable output available with --json flag (audit mode only)
#   - Dry-run available with --dry-run flag
#   - Detailed logs written to /tmp/fasterdata-tuning-<timestamp>.log

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
USE_COLOR=1
APPLY_TCP_CC=""
APPLY_JUMBO=0
OUTPUT_JSON=0

usage() {
  cat <<'EOF'
Usage: fasterdata-tuning.sh [OPTIONS]

Options:
  --mode audit|apply      Mode to run (default: audit)
  --ifaces IFACE[,IFACE]  Comma-separated list of interfaces to check
  --target measurement|dtn  Target type for tuning (default: measurement)
  --apply-jumbo           Apply jumbo MTU when --mode apply
  --apply-tcp-cc ALGO     Apply TCP congestion control ALGO in --mode apply
  --apply-iommu           Apply IOMMU kernel cmdline options (requires --mode apply; vendor auto-detected)
  --apply-smt on|off      Enable or disable SMT (requires root)
  --persist-smt           Make SMT configuration persistent in GRUB (requires --apply-smt)
  --apply-packet-pacing   Enable packet pacing (DTN targets only); sets qdisc=tbf when applied
  --packet-pacing-rate RATE  Set the packet pacing rate (default: 2000mbps)
  --yes                   Skip interactive prompts and accept defaults
  --json                  Print JSON machine-readable audit (audit mode only)
  --iommu-args ARGS       Optional custom kernel cmdline args to set for IOMMU (default: vendor-specific intel|amd args)
  --color                 Enable colorized output (default)
  --nocolor               Disable colorized output
  --dry-run               Do not make changes when in apply mode; show actions only

State Management Options:
  --save-state            Save current system state to a file
  --label LABEL           Label for saved state (optional, default: timestamp)
  --restore-state FILE    Restore system state from saved file or label
  --list-states           List all saved states
  --diff-state FILE       Show differences between current and saved state
  --delete-state FILE     Delete a saved state file
  --auto-save-before      Auto-save state before applying changes (use with --mode apply)

  --help                  Show this help
EOF
}

# Speed-specific tuning recommendations from ESnet fasterdata.es.net
# Values indexed by link speed in Mbps: [rmem_max, wmem_max, tcp_rmem_max, tcp_wmem_max, netdev_max_backlog]
# For measurement hosts (perfSONAR): optimized for moderate RTT (50-100ms) paths
# For DTN hosts: optimized for data transfer efficiency
# shellcheck disable=SC2034
declare -A TUNING_10G_MEASUREMENT=(
  [rmem_max]=268435456      # 256 MB for 100ms RTT paths
  [wmem_max]=268435456      # 256 MB
  [tcp_rmem]="4096 87380 134217728"    # min default max (128 MB)
  [tcp_wmem]="4096 65536 134217728"    # min default max (128 MB)
  [netdev_max_backlog]=250000
)
# shellcheck disable=SC2034
declare -A TUNING_10G_DTN=(
  [rmem_max]=67108864       # 64 MB for general DTN use
  [wmem_max]=67108864       # 64 MB
  [tcp_rmem]="4096 87380 33554432"     # min default max (32 MB)
  [tcp_wmem]="4096 65536 33554432"     # min default max (32 MB)
  [netdev_max_backlog]=250000
)
# shellcheck disable=SC2034
declare -A TUNING_25G_MEASUREMENT=(
  [rmem_max]=402653184      # 384 MB (interpolated between 10G and 40G)
  [wmem_max]=402653184      # 384 MB
  [tcp_rmem]="4096 87380 201326592"    # min default max (192 MB)
  [tcp_wmem]="4096 65536 201326592"    # min default max (192 MB)
  [netdev_max_backlog]=300000
)
# shellcheck disable=SC2034
declare -A TUNING_25G_DTN=(
  [rmem_max]=100663296      # 96 MB (interpolated)
  [wmem_max]=100663296      # 96 MB
  [tcp_rmem]="4096 87380 50331648"     # min default max (48 MB)
  [tcp_wmem]="4096 65536 50331648"     # min default max (48 MB)
  [netdev_max_backlog]=300000
)
# shellcheck disable=SC2034
declare -A TUNING_40G_MEASUREMENT=(
  [rmem_max]=536870912      # 512 MB for 100ms RTT paths
  [wmem_max]=536870912      # 512 MB
  [tcp_rmem]="4096 87380 268435456"    # min default max (256 MB)
  [tcp_wmem]="4096 65536 268435456"    # min default max (256 MB)
  [netdev_max_backlog]=400000
)
# shellcheck disable=SC2034
declare -A TUNING_40G_DTN=(
  [rmem_max]=134217728      # 128 MB for general DTN use
  [wmem_max]=134217728      # 128 MB
  [tcp_rmem]="4096 87380 67108864"     # min default max (64 MB)
  [tcp_wmem]="4096 65536 67108864"     # min default max (64 MB)
  [netdev_max_backlog]=400000
)
# shellcheck disable=SC2034
declare -A TUNING_100G_MEASUREMENT=(
  [rmem_max]=2147483647     # 2 GB for high RTT/100G paths
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=500000
)
# shellcheck disable=SC2034
declare -A TUNING_100G_DTN=(
  [rmem_max]=2147483647     # 2 GB for 100G+ DTN
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=500000
)
# shellcheck disable=SC2034
declare -A TUNING_200G_MEASUREMENT=(
  [rmem_max]=2147483647     # 2 GB (same as 100G)
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=750000
)
# shellcheck disable=SC2034
declare -A TUNING_200G_DTN=(
  [rmem_max]=2147483647     # 2 GB
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=750000
)
# shellcheck disable=SC2034
declare -A TUNING_400G_MEASUREMENT=(
  [rmem_max]=2147483647     # 2 GB (kernel max)
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=1000000
)
# shellcheck disable=SC2034
declare -A TUNING_400G_DTN=(
  [rmem_max]=2147483647     # 2 GB
  [wmem_max]=2147483647     # 2 GB
  [tcp_rmem]="4096 131072 1073741824"  # min default max (1 GB)
  [tcp_wmem]="4096 16384 1073741824"   # min default max (1 GB)
  [netdev_max_backlog]=1000000
)


# Color codes for terminal output
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_RED='\033[0;31m'
readonly C_CYAN='\033[1;36m'
readonly C_RESET='\033[0m'

MODE="audit"
IFACES=""
APPLY_IOMMU=0
IOMMU_ARGS=""  # Optional override for kernel cmdline IOMMU flags (e.g., "intel_iommu=on iommu=pt")
APPLY_SMT=""
PERSIST_SMT=0
AUTO_YES=0
DRY_RUN=0
PACKET_PACING_RATE="2000mbps"
APPLY_PACKET_PACING=0

# Save/restore state management
SAVE_STATE=0
RESTORE_STATE=""
LIST_STATES=0
DIFF_STATE=""
DELETE_STATE=""
STATE_LABEL=""
AUTO_SAVE_BEFORE=0
STATE_DIR="/var/lib/fasterdata-tuning"
STATE_SUBDIR="$STATE_DIR/saved-states"
BACKUP_SUBDIR="$STATE_DIR/backups"
LOG_SUBDIR="$STATE_DIR/logs"

get_host_fqdns() {
  local iface ip ip_cidr fqdn
  declare -A fq_ifaces=()
  declare -A fq_sources=()
  declare -A fq_mismatch=()
  declare -A fq_ips=()
  declare -A fq_verified=()

  for iface in $(get_ifaces); do
    # Use ip -o addr and treat the 4th column as addr/prefix
    local ips
    ips=$(ip -o addr show "$iface" 2>/dev/null | awk '{print $4}')
    while IFS= read -r ip_cidr; do
      [[ -z "$ip_cidr" ]] && continue
      ip="${ip_cidr%/*}"
      # Skip link-local and loopback
      [[ "$ip" =~ ^127\.|^::1$|^fe80: ]] && continue

      fqdn=$(reverse_dns_lookup "$ip")
      if [[ -n "$fqdn" ]]; then
        # We have a reverse DNS name. Check forward DNS for a match
        if verify_dns_match "$fqdn" "$ip"; then
          # Confirmed DNS mapping
          fq_ifaces[$fqdn]="${fq_ifaces[$fqdn]:+${fq_ifaces[$fqdn]},}$iface"
          fq_sources[$fqdn]="${fq_sources[$fqdn]:+${fq_sources[$fqdn]},}dns"
          fq_ips[$fqdn]="${fq_ips[$fqdn]:+${fq_ips[$fqdn]},}$ip"
          fq_verified[$fqdn]=1
          fq_mismatch[$fqdn]=0
        else
          local hostline
          hostline=$(getent hosts "$ip" 2>/dev/null || true)
          if [[ -n "$hostline" ]] && echo "$hostline" | awk '{for (i=2;i<=NF;i++) print $i}' | grep -qw "${fqdn}"; then
            # The /etc/hosts name matches the reverse name; treat as hosts-sourced
            fq_ifaces[$fqdn]="${fq_ifaces[$fqdn]:+${fq_ifaces[$fqdn]},}$iface"
          
            fq_ips[$fqdn]="${fq_ips[$fqdn]:+${fq_ips[$fqdn]},}$ip"
            fq_verified[$fqdn]=1
            fq_mismatch[$fqdn]=0
          else
            # Genuine DNS mismatch
            fq_ifaces[$fqdn]="${fq_ifaces[$fqdn]:+${fq_ifaces[$fqdn]},}$iface"
            fq_sources[$fqdn]="${fq_sources[$fqdn]:+${fq_sources[$fqdn]},}dns"
            fq_ips[$fqdn]="${fq_ips[$fqdn]:+${fq_ips[$fqdn]},}$ip"
            fq_verified[$fqdn]=0
            fq_mismatch[$fqdn]=1
          fi
        fi
      else
        # No reverse DNS; check getent hosts for names mapping to this IP
        local hostline
        hostline=$(getent hosts "$ip" 2>/dev/null || true)
        if [[ -n "$hostline" ]]; then
          # add all names from getent (NSS), treat as hosts-sourced
          local names
          names=$(echo "$hostline" | awk '{$1=""; print $0}' | xargs)
          for name in $names; do
            [[ -z "$name" ]] && continue
            fq_ifaces[$name]="${fq_ifaces[$name]:+${fq_ifaces[$name]},}$iface"
            fq_sources[$name]="${fq_sources[$name]:+${fq_sources[$name]},}hosts"
            fq_ips[$name]="${fq_ips[$name]:+${fq_ips[$name]},}$ip"
            fq_verified[$name]=1
            fq_mismatch[$name]=0
          done
        else
          # No name available; add a placeholder with IP
          local placeholder="(no reverse DNS for ${ip})"
          fq_ifaces["$placeholder"]="${fq_ifaces["$placeholder"]:+${fq_ifaces["$placeholder"]},}$iface"
          fq_sources["$placeholder"]="none"
          fq_ips["$placeholder"]="${fq_ips["$placeholder"]:+${fq_ips["$placeholder"]},}$ip"
          fq_mismatch["$placeholder"]=0
          fq_verified["$placeholder"]=0
        fi
      fi
    done <<<"$ips"
  done

  # Also include aliases returned by hostname -A (all names) so local names are visible
  local alias_names
  alias_names=$(hostname -A 2>/dev/null || true)
  if [[ -n "$alias_names" ]]; then
    for name in $alias_names; do
      [[ -z "$name" ]] && continue
      # If not already known, just add with empty iface/source
      if [[ -z "${fq_ifaces[$name]:-}" ]]; then
        fq_ifaces[$name]=""
        fq_sources[$name]="alias"
        fq_ips[$name]=""
        fq_mismatch[$name]=0
      fi
      # Try to resolve the name to IPs and map to a local iface if possible
      local resolved_ips
      resolved_ips=$(getent hosts "$name" 2>/dev/null | awk '{print $1}' || true)
      if [[ -z "$resolved_ips" ]] && command -v dig >/dev/null 2>&1; then
        resolved_ips=$(dig +short "$name" | sed -n '1,100p' || true)
      fi
      if [[ -n "$resolved_ips" ]]; then
        for rip in $resolved_ips; do
          local mapped_iface
          mapped_iface=$(ip_to_iface "$rip" || true)
          if [[ -n "$mapped_iface" ]]; then
            # Mark as mapped to a local interface and mark source as hosts/dns appropriately
            fq_ifaces[$name]="${fq_ifaces[$name]:+${fq_ifaces[$name]},}$mapped_iface"
            # If the resolved IP came from getent, use hosts, otherwise dig -> dns
            if getent hosts "$name" >/dev/null 2>&1; then
              fq_sources[$name]="${fq_sources[$name]:+${fq_sources[$name]},}hosts"
            else
              fq_sources[$name]="${fq_sources[$name]:+${fq_sources[$name]},}dns"
            fi
            fq_ips[$name]="${fq_ips[$name]:+${fq_ips[$name]},}$rip"
            fq_verified[$name]=1
            fq_mismatch[$name]=0
          fi
        done
      fi
    done
  fi

  # Build output lines: fqdn [iface1,iface2] (source) (DNS mismatch!)
  local out=()
  local f s ifs ips mismatch srcstr
  for f in "${!fq_ifaces[@]}"; do
    ifs=${fq_ifaces[$f]:-}
    # Convert comma list into bracketed list
    if [[ -n "$ifs" ]]; then
      # Deduplicate comma-separated iface list while preserving order
      IFS=',' read -r -a __arr <<<"$ifs"
      declare -A __seen=()
      __uniq=""
      for __v in "${__arr[@]}"; do
        if [[ -z "${__seen[$__v]:-}" ]]; then
          __seen[$__v]=1
          __uniq+="${__uniq:+,}${__v}"
        fi
      done
      ifs="[${__uniq}]"
    else
      ifs=""
    fi
    mismatch=${fq_mismatch[$f]:-0}
    # If we've verified any address for this name, consider it not mismatch
    if [[ ${fq_verified[$f]:-0} -eq 1 ]]; then
      mismatch=0
    fi
    srcstr=${fq_sources[$f]:-}
    # Colorization / tags
    local tag=""
    if [[ "$mismatch" -eq 1 ]]; then
      tag="(DNS mismatch!)"
      f="$(colorize red "$f")"
    elif [[ "$srcstr" =~ hosts ]]; then
      tag="(via /etc/hosts)"
      f="$(colorize cyan "$f")"
    elif [[ "$srcstr" =~ alias ]]; then
      tag="(alias)"
      f="$(colorize cyan "$f")"
    else
      # default: dns or none
      f="$(colorize green "$f")"
    fi
    if [[ -n "$ifs" ]]; then
      out+=("$f $ifs $tag")
    else
      out+=("$f $tag")
    fi
  done

  # Print deduplicated sorted lines
  printf '%s\n' "${out[@]}" | sort -u
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

json_quote() {
  # Quote and escape a string for JSON. Prefer python3 if available for reliable JSON encoding.
  local s
  s="$1"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$s" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$s" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  else
    # Fallback minimal escaping
    printf '%s' "$s" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' | awk '{printf "\"%s\"", $0}'
  fi
}

print_json() {
  # Disable color in json mode
  local old_color="$USE_COLOR"
  USE_COLOR=0

  local hostname os kernel mem_kb mem_gb cpu_count smt ipv6 tcp_cc_current tcp_cc_available
  hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
  os=$(awk -F'=' '/^PRETTY_NAME/ {print $2}' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
  kernel=$(uname -r)
  mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem_gb=$((mem_kb / 1024 / 1024))
  cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)
  smt=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo "unknown")
  ipv6=$(check_ipv6_config)
  local ipv6_json=false
  if [[ "$ipv6" -eq 1 ]]; then ipv6_json=true; fi
  tcp_cc_current=$(get_tcp_cc_current)
  tcp_cc_available=$(get_tcp_cc_available)

  # FQDNs
  local fqdns_json="[]"
  local all_fqdns
  all_fqdns=$(get_host_fqdns)
  if [[ -n "$all_fqdns" ]]; then
    local arr=()
    while IFS= read -r line; do arr+=("$line"); done <<<"$all_fqdns"
    fqdns_json="["
    local first=1
    for name in "${arr[@]}"; do
      if (( first )); then
        first=0
      else
        fqdns_json+=",";
      fi
      fqdns_json+=$(json_quote "$name")
    done
    fqdns_json+="]"
  fi

  # Sysctl recs
  local sysctl_entries="["
  local first_entry=1
  for key in "${!SYSCTL_RECS[@]}"; do
    local wanted current
    wanted=${SYSCTL_RECS[$key]}
    current=$(sysctl -n "$key" 2>/dev/null || echo "(unset)")
    # normalize whitespace
    local current_normalized wanted_normalized
    current_normalized=$(echo "$current" | awk '{$1=$1; print}')
    wanted_normalized=$(echo "$wanted" | awk '{$1=$1; print}')
    local match=false
    if [[ "$current_normalized" == "$wanted_normalized" ]]; then match=true; fi
    if (( first_entry )); then first_entry=0; else sysctl_entries+=","; fi
    sysctl_entries+="{\"key\":$(json_quote "$key"),\"current\":$(json_quote "$current"),\"recommended\":$(json_quote "$wanted"),\"match\":$match}"
  done
  sysctl_entries+="]"

  # Interfaces
  # Read interface list into array to avoid word-splitting issues
  local ifs=()
  readarray -t ifs <<<"$(get_ifaces)"
  local if_entries="["
  local first_if=1
  for iface in "${ifs[@]}"; do
    # Gather data similar to iface_audit
    local state txqlen if_speed desired_txqlen qdisc driver offload_issue current_mtu max_mtu rings_cur rings_max
    state=$(ip -o link show "$iface" 2>/dev/null | awk '{print $9}' || echo "unknown")
    txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "?" )
    if_speed=$(get_iface_speed "$iface")
    desired_txqlen=$(desired_txqlen_for_speed "$if_speed")
    qdisc=$(tc qdisc show dev "$iface" 2>/dev/null | head -n1 | awk '{print $2,$3,$4}' || echo "unknown")
    driver=$(ethtool -i "$iface" 2>/dev/null | awk -F': ' '/driver/ {print $2}' || echo "unknown")
    offload_issue="ok"
    if command -v ethtool >/dev/null 2>&1; then
      local offload_devs
      offload_devs=$(ethtool -k "$iface" 2>/dev/null | grep -E 'gro:|gso:|tso:|rx-checksumming:|tx-checksumming:|lro:' || true)
      if [[ "$offload_devs" =~ lro:[[:space:]]*on ]]; then offload_issue="lro on"; fi
      if ! echo "$offload_devs" | grep -q 'rx-checksumming:.*on'; then offload_issue="rx csum off"; fi
      if ! echo "$offload_devs" | grep -q 'tx-checksumming:.*on'; then offload_issue="tx csum off"; fi
    else
      offload_issue="missing ethtool"
    fi
    rings_cur=$(ethtool -g "$iface" 2>/dev/null | awk '/RX:/ {rx=$2} /TX:/ {tx=$2} END {print rx"/"tx}' || true)
    rings_max=$(ethtool -g "$iface" 2>/dev/null | awk '/RX max:/ {rx=$3} /TX max:/ {tx=$3} END {print rx"/"tx}' || true)
    current_mtu=$(get_nic_mtu "$iface")
    max_mtu=$(get_nic_max_mtu "$iface")
    # compute issues array
    local issues_arr=()
    if [[ "$txqlen" != "?" && "$txqlen" -lt "$desired_txqlen" ]]; then issues_arr+=("txqlen $txqlen<${desired_txqlen}"); fi
    local qdisc_type="${qdisc%% *}"
    if [[ "$qdisc_type" != "fq" ]]; then issues_arr+=("qdisc=${qdisc:-unknown}"); fi
    if [[ "$offload_issue" != "ok" ]]; then issues_arr+=("$offload_issue"); fi
    if [[ -n "$rings_cur" && -n "$rings_max" && "$rings_cur" != "$rings_max" ]]; then issues_arr+=("rings $rings_cur (max $rings_max)"); fi
    # JSON entry for this iface
    if (( first_if )); then first_if=0; else if_entries+=","; fi
    if_entries+="{\"iface\":$(json_quote "$iface"),\"state\":$(json_quote "$state"),\"speed_mbps\":$(json_quote "$if_speed"),\"txqlen\":$(json_quote "$txqlen"),\"desired_txqlen\":$(json_quote "$desired_txqlen"),\"qdisc\":$(json_quote "$qdisc"),\"driver\":$(json_quote "$driver"),\"current_mtu\":$(json_quote "$current_mtu"),\"max_mtu\":$(json_quote "$max_mtu"),\"offload_issue\":$(json_quote "$offload_issue"),\"issues\":["
    local first_j=1
    for j in "${issues_arr[@]}"; do
      if (( first_j )); then first_j=0; else if_entries+=','; fi
      if_entries+=$(json_quote "$j")
    done
    if_entries+="]}"
  done
  if_entries+="]"

  # Missing tools
  local missing_json="[]"
  if (( ${#MISSING_TOOLS[@]} > 0 )); then
    missing_json="["
    local mi=1
    for t in "${MISSING_TOOLS[@]}"; do
      if [[ $mi -eq 1 ]]; then mi=0; else missing_json+=","; fi
      missing_json+=$(json_quote "$t")
    done
    missing_json+="]"
  fi

  # driver updates unique
  local driver_json="[]"
  if (( ${#DRIVER_UPDATES[@]} > 0 )); then
    driver_json="["
    local di=1
    for d in "${DRIVER_UPDATES[@]}"; do
      if [[ $di -eq 1 ]]; then di=0; else driver_json+=","; fi
      driver_json+=$(json_quote "$d")
    done
    driver_json+="]"
  fi

  # Build top-level JSON
  printf "{\n"
  printf "  \"hostname\": %s,\n" "$(json_quote "$hostname")"
  printf "  \"os\": %s,\n" "$(json_quote "$os")"
  printf "  \"kernel\": %s,\n" "$(json_quote "$kernel")"
  printf "  \"memory_gib\": %s,\n" "$mem_gb"
  printf "  \"cpus\": %s,\n" "$cpu_count"
  printf "  \"smt\": %s,\n" "$(json_quote "$smt")"
  printf "  \"ipv6_present\": %s,\n" "$ipv6_json"
  printf "  \"tcp_cc_current\": %s,\n" "$(json_quote "$tcp_cc_current")"
  printf "  \"tcp_cc_available\": %s,\n" "$(json_quote "$tcp_cc_available")"
  printf "  \"fqdns\": %s,\n" "$fqdns_json"
  printf "  \"sysctl_recs\": %s,\n" "$sysctl_entries"
  printf "  \"interfaces\": %s,\n" "$if_entries"
  printf "  \"missing_tools\": %s,\n" "$missing_json"
  printf "  \"driver_updates\": %s,\n" "$driver_json"
  # Interface-specific issues
  local if_issues_json="[]"
  if (( ${#IF_ISSUES[@]} > 0 )); then
    if_issues_json="["
    local ii=1
    for t in "${IF_ISSUES[@]}"; do
      if [[ $ii -eq 1 ]]; then ii=0; else if_issues_json+=","; fi
      if_issues_json+=$(json_quote "$t")
    done
    if_issues_json+="]"
  fi
  printf "  \"iface_issues\": %s,\n" "$if_issues_json"
  printf "  \"sysctl_mismatches\": %s\n" "$SYSCTL_MISMATCHES"
  printf "}\n"

  USE_COLOR=$old_color
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
    cyan) echo -e "${C_CYAN}${text}${C_RESET}";;
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

# Detect if running on EL9
is_el9() {
  if [[ -f /etc/os-release ]]; then
    local version_id
    version_id=$(awk -F= '/^VERSION_ID=/ {print $2}' /etc/os-release | tr -d '"')
    if [[ "$version_id" =~ ^9\. ]]; then
      return 0
    fi
  fi
  return 1
}

# Warn if not on EL9 (for GRUB/BLS operations)
warn_if_not_el9() {
  local operation="$1"
  if ! is_el9; then
    local os_name
    os_name=$(awk -F= '/^PRETTY_NAME=/ {print $2}' /etc/os-release 2>/dev/null | tr -d '"' || echo "unknown")
    log_warn "Detected OS: $os_name (not EL9)"
    log_warn "The $operation operation is optimized for Enterprise Linux 9"
    log_warn "On non-EL9 systems, GRUB configuration may differ - proceed with caution"
    if [[ $DRY_RUN -ne 1 ]] && [[ $AUTO_YES -ne 1 ]]; then
      read -r -p "Continue anyway? [y/N] " resp
      if [[ ! "$resp" =~ ^[Yy]$ ]]; then
        log_info "$operation cancelled by user"
        return 1
      fi
    fi
  fi
  return 0
}

# Get tuning parameters for a specific link speed and target type
# Usage: get_tuning_for_speed <speed_mbps> <target_type> <param_name>
# Returns: the specific parameter value for the speed/type combination
get_tuning_for_speed() {
  local speed="$1"
  local target="$2"
  local param="$3"
  local -n tuning_table
  
  # Determine which tuning table to use based on speed and target type
  if [[ $speed -ge 400000 ]]; then
    # 400G+
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_400G_MEASUREMENT || tuning_table=TUNING_400G_DTN
  elif [[ $speed -ge 200000 ]]; then
    # 200G
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_200G_MEASUREMENT || tuning_table=TUNING_200G_DTN
  elif [[ $speed -ge 100000 ]]; then
    # 100G
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_100G_MEASUREMENT || tuning_table=TUNING_100G_DTN
  elif [[ $speed -ge 40000 ]]; then
    # 40G
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_40G_MEASUREMENT || tuning_table=TUNING_40G_DTN
  elif [[ $speed -ge 25000 ]]; then
    # 25G
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_25G_MEASUREMENT || tuning_table=TUNING_25G_DTN
  else
    # 10G and below
    [[ "$target" == "measurement" ]] && tuning_table=TUNING_10G_MEASUREMENT || tuning_table=TUNING_10G_DTN
  fi
  
  echo "${tuning_table[$param]}"
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
  # Nothing else to add for get_ifaces; return list of candidates

  # De-duplicate and print
  if [[ ${#candidates[@]} -gt 0 ]]; then
    printf "%s\n" "${candidates[@]}" | sort -u
  fi
}

# Given an IP address, return the interface name that has that address configured
ip_to_iface() {
  local ip="$1"
  # Match the address portion before slash
  # ip -o addr prints: <idx>: <iface> <family> <addr>/<prefix> ...
  ip -o addr 2>/dev/null | awk -v ip="$ip" '$4 ~ ip"/" {print $2; exit}' || true
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

# Get available TCP congestion control algorithms
get_tcp_cc_available() {
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo ""
}

# Get current TCP congestion control algorithm
get_tcp_cc_current() {
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
}

# Check if BBRv3 is available
has_bbrv3() {
  get_tcp_cc_available | grep -qw "bbr"
}

# Get NIC max MTU capability
get_nic_max_mtu() {
  local iface="$1"
  if command -v ethtool >/dev/null 2>&1; then
    ethtool "$iface" 2>/dev/null | grep -i "max mtu" | awk '{print $NF}' || echo "unknown"
  else
    echo "unknown"
  fi
}

# Get current MTU for NIC
get_nic_mtu() {
  local iface="$1"
  ip link show "$iface" 2>/dev/null | grep -oP 'mtu \K\d+' || echo "unknown"
}

# Reverse DNS lookup for IP
reverse_dns_lookup() {
  local ip="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' || echo ""
  elif command -v host >/dev/null 2>&1; then
    host "$ip" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//' || echo ""
  else
    echo ""
  fi
}

# Forward DNS lookup to verify match
verify_dns_match() {
  local fqdn="$1" ip="$2"
  # Query both A and AAAA records and match whichever corresponds to the local IP
  local answers a mapped_iface local_iface
  answers=""
  if command -v dig >/dev/null 2>&1; then
    answers=$( (dig +short A "$fqdn" 2>/dev/null || true; dig +short AAAA "$fqdn" 2>/dev/null || true) | tr '\n' ' ' )
  elif command -v host >/dev/null 2>&1; then
    answers=$(host "$fqdn" 2>/dev/null | awk '/has address|has IPv6 address/ {print $NF}' | tr '\n' ' ')
  else
    return 1
  fi

  # If the explicit IP is present among resolved answers, it is an exact match
  for a in $answers; do
    [[ "$a" == "$ip" ]] && return 0
  done

  # Otherwise, attempt to treat a match if any resolved address belongs to the same
  # local interface as the supplied IP (i.e., aliasing or IPv4/IPv6 pair on same iface)
  local_iface=$(ip_to_iface "$ip" || true)
  if [[ -z "$local_iface" ]]; then
    return 1
  fi
  for a in $answers; do
    mapped_iface=$(ip_to_iface "$a" || true)
    if [[ -n "$mapped_iface" ]] && [[ "$mapped_iface" == "$local_iface" ]]; then
      return 0
    fi
  done
  return 1
}

# Get all FQDNs for the host
 

# Check if IPv6 is configured on any non-loopback interface
check_ipv6_config() {
  local iface ipv6_found=0
  for iface in $(get_ifaces); do
    # Check for global unicast IPv6 addresses (exclude link-local fe80:: and loopback ::1)
    if ip -6 addr show "$iface" 2>/dev/null | grep -q 'scope global'; then
      ipv6_found=1
      break
    fi
  done
  echo "$ipv6_found"
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
    local current_normalized
    current_normalized=$(echo "$current" | awk '{$1=$1; print}')
    local wanted_normalized
    wanted_normalized=$(echo "$wanted" | awk '{$1=$1; print}')
    if [[ "$current_normalized" != "$wanted_normalized" ]]; then
      status="*"
      ((SYSCTL_MISMATCHES+=1))
      log_detail "SYSCTL mismatch: $key current='$current' recommended='$wanted'"
    else
      log_detail "SYSCTL ok: $key=$current"
    fi
    # Colorize current value - green when equal, yellow otherwise
    local current_print
    if [[ "$current_normalized" == "$wanted_normalized" ]]; then
      current_print="$(colorize green "$current")"
    else
      current_print="$(colorize yellow "$current")"
    fi
    printf "%-35s %-35s %-35s %s\n" "$key" "$current_print" "$wanted" "$status"
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
  
  # Use speed-specific tuning tables from fasterdata.es.net recommendations
  SCALED_RMEM_MAX=$(get_tuning_for_speed "$MAX_LINK_SPEED" "$TARGET_TYPE" "rmem_max")
  SCALED_WMEM_MAX=$(get_tuning_for_speed "$MAX_LINK_SPEED" "$TARGET_TYPE" "wmem_max")
  SCALED_BACKLOG=$(get_tuning_for_speed "$MAX_LINK_SPEED" "$TARGET_TYPE" "netdev_max_backlog")
  local tcp_rmem tcp_wmem
  tcp_rmem=$(get_tuning_for_speed "$MAX_LINK_SPEED" "$TARGET_TYPE" "tcp_rmem")
  tcp_wmem=$(get_tuning_for_speed "$MAX_LINK_SPEED" "$TARGET_TYPE" "tcp_wmem")
  
  # Update SYSCTL_RECS with speed-specific values
  SYSCTL_RECS[net.core.rmem_max]=$SCALED_RMEM_MAX
  SYSCTL_RECS[net.core.wmem_max]=$SCALED_WMEM_MAX
  SYSCTL_RECS[net.core.netdev_max_backlog]=$SCALED_BACKLOG
  SYSCTL_RECS[net.ipv4.tcp_rmem]="$tcp_rmem"
  SYSCTL_RECS[net.ipv4.tcp_wmem]="$tcp_wmem"
  
  # Set defaults to 1/4 of max (common practice)
  SYSCTL_RECS[net.core.rmem_default]=$((SCALED_RMEM_MAX / 4))
  SYSCTL_RECS[net.core.wmem_default]=$((SCALED_WMEM_MAX / 4))
}

cache_kernel_versions() {
  RUNNING_KERNEL=$(uname -r 2>/dev/null || true)
  LATEST_KERNEL=""
  if command -v dnf >/dev/null 2>&1; then
    LATEST_KERNEL=$(dnf -q list --showduplicates kernel 2>/dev/null | grep kernel.x86_64 | awk '{print $2}' | sort -V | tail -1)
  fi
}

apply_sysctl() {
  # Write tuned sysctls to a sysctl.d file to avoid clobbering /etc/sysctl.conf
  local sysctl_file="/etc/sysctl.d/90-fasterdata.conf"
  if [[ $DRY_RUN -ne 1 ]]; then
    require_root
  fi
  log_info "Updating $sysctl_file with fasterdata tuning parameters"
  
  # Skip all actual changes if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would update $sysctl_file and apply sysctl settings (skipped)"
    return
  fi
  
  # backup existing file
  if [[ -f "$sysctl_file" ]]; then
    local timestamp
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)
    cp -a "$sysctl_file" "${sysctl_file}.${timestamp}.bak" 2>/dev/null || true
    log_info "Backed up existing $sysctl_file to ${sysctl_file}.${timestamp}.bak"
  fi
  log_info "Detected max link speed (Mbps): ${MAX_LINK_SPEED:-0}"

  # Iterate all recommendations from SYSCTL_RECS so we apply the scaled values.
  log_info "Applying live sysctl values for keys:"
  for key in $(printf '%s\n' "${!SYSCTL_RECS[@]}" | sort); do
    local value
    value=${SYSCTL_RECS[$key]}
    local update
    update="$key=$value"
    local escaped_key
    escaped_key="${key//./\.}"
    if grep -q "^${escaped_key}=" "$sysctl_file" 2>/dev/null; then
      sed -i "s|^${escaped_key}=.*|${update}|" "$sysctl_file"
    else
      echo "$update" >> "$sysctl_file"
    fi
  done
  # Show the file we wrote for debugging visibility
  log_info "Wrote sysctl file: $sysctl_file"
  log_detail "--- BEGIN $sysctl_file ---"
  if [[ -r "$sysctl_file" ]]; then
    while IFS= read -r line; do log_detail "$line"; done <"$sysctl_file"
  fi
  log_detail "--- END $sysctl_file ---"
  
  if ! has_bbr; then
    log_warn "bbr not available; falling back to cubic at runtime (file still sets bbr)"
  fi
  log_info "Applying sysctl settings"
  # Use --system to make sure sysctl.d files are read in the correct order
  sysctl --system >/dev/null 2>&1 || sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
  # Ensure running kernel receives the exact recommendation by setting live values.
  for key in $(printf '%s\n' "${!SYSCTL_RECS[@]}" | sort); do
    local value
    value=${SYSCTL_RECS[$key]}
    # Live apply and verify
    if sysctl -w "$key=$value" >/dev/null 2>&1; then
      local cur
      cur=$(sysctl -n "$key" 2>/dev/null || echo "(unset)")
      # Normalize strings with awk for whitespace comparisons
      local cur_n wanted_n
      cur_n=$(echo "$cur" | awk '{$1=$1; print}')
      wanted_n=$(echo "$value" | awk '{$1=$1; print}')
      if [[ "$cur_n" != "$wanted_n" ]]; then
        log_warn "Sysctl $key live value did not match applied value: current='$cur' expected='$value'"
      else
        log_info "Applied sysctl $key=$value"
      fi
    else
      log_warn "Failed to apply sysctl $key=$value (sysctl -w failed)"
    fi
  done
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

  local short_line
  # Colorize txqlen: green if it meets/exceeds desired txqlen, yellow otherwise
  local txqlen_display="$txqlen"
  if [[ "$txqlen" =~ ^[0-9]+$ ]] && [[ "$desired_txqlen" =~ ^[0-9]+$ ]] && (( txqlen >= desired_txqlen )); then
    txqlen_display="$(colorize green "$txqlen")"
  else
    txqlen_display="$(colorize yellow "$txqlen")"
  fi
  # Prepare qdisc display, color only the qdisc 'value' (first word)
  local qdisc_val qdisc_rest qdisc_display
  if [[ -n "$qdisc" ]]; then
    qdisc_val="${qdisc%% *}"
    qdisc_rest="${qdisc#"${qdisc_val}"}"
  else
    qdisc_val="?"
    qdisc_rest=""
  fi
  if [[ "$qdisc_val" == "fq" ]]; then
    qdisc_display="$(colorize green "$qdisc_val")${qdisc_rest}"
  else
    qdisc_display="$(colorize yellow "$qdisc_val")${qdisc_rest}"
  fi
  short_line=$(printf "%-12s state=%-7s speed=%-9s txqlen=%-6s(rec>=%-5s) qdisc=%-6s driver=%s" "$iface" "${state:-?}" "$speed_str" "$txqlen_display" "$desired_txqlen" "$qdisc_display" "$driver")
  printf "\n%s" "$short_line"
  local offload_str="offload=${offload_issue}"
  [[ -n "$rings_note" ]] && offload_str+=" $rings_note"
  printf " %s\n" "$offload_str"

  # Jumbo frame (MTU) audit
  local current_mtu max_mtu mtu_status=""
  current_mtu=$(get_nic_mtu "$iface")
  max_mtu=$(get_nic_max_mtu "$iface")
  # Colorize current MTU (>=9000 = green, otherwise yellow)
  local mtu_color="yellow" current_mtu_disp
  if [[ "$current_mtu" =~ ^[0-9]+$ ]] && [[ "$current_mtu" -ge 9000 ]]; then
    mtu_color="green"
  fi
  current_mtu_disp=$(colorize "$mtu_color" "$current_mtu")
  # Only show max if known
  local max_mtu_disp
  if [[ "$max_mtu" != "unknown" ]]; then
    max_mtu_disp=" max=$max_mtu"
  else
    max_mtu_disp=""
  fi
  printf "  MTU: current=%s%s\n" "$current_mtu_disp" "$max_mtu_disp"
  if [[ "$current_mtu" == "unknown" || "$current_mtu" -lt 9000 ]]; then
    mtu_status="mtu=$current_mtu (recomm: 9000)"
    # Add to issues so it shows up in the interface summary
    issues+=("$mtu_status")
  fi

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
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    return
  fi
  
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

iface_packet_pacing_audit() {
  local iface="$1"
  local pacing_rate="$2"
  
  # Only audit packet pacing for DTN nodes
  if [[ "$TARGET_TYPE" != "dtn" ]]; then
    return 0
  fi
  
  # Check current qdisc - should be tbf (token bucket filter) for pacing
  local current_qdisc
  current_qdisc=$(tc qdisc show dev "$iface" 2>/dev/null | head -n1)
  
  # If we're not applying pacing, just report current state
  if [[ $APPLY_PACKET_PACING -eq 0 ]]; then
    if [[ "$current_qdisc" != *"tbf"* ]]; then
      return 1  # Not using tbf; would need packet pacing applied
    fi
    return 0  # Already using tbf
  fi
  
  return 0
}

iface_apply_packet_pacing() {
  local iface="$1"
  local pacing_rate="$2"
  
  if [[ "$TARGET_TYPE" != "dtn" ]] || [[ $APPLY_PACKET_PACING -eq 0 ]]; then
    return
  fi
  
  log_info "Applying packet pacing ($pacing_rate) to $iface via tc tbf qdisc"
  
  # Parse rate and convert to bits per second for tc
  # tc expects rate in: bit, kbit, mbit, gbit, tbit, or bps, kbps, mbps, gbps, tbps
  local rate_normalized="$pacing_rate"
  
  # Normalize case if needed (tc accepts both cases)
  rate_normalized="${rate_normalized,,}"  # lowercase
  
  # Verify rate is in acceptable format
  if ! [[ "$rate_normalized" =~ ^[0-9]+(kbps|mbps|gbps|tbps|kbit|mbit|gbit|tbit|bit|bps)$ ]]; then
    log_warn "Invalid packet pacing rate format: $pacing_rate (use e.g., 2gbps, 10000mbps)"
    return 1
  fi
  
  # Get interface speed to validate pacing rate doesn't exceed link speed
  local if_speed
  if_speed=$(get_iface_speed "$iface")
  
  # Set up tbf (token bucket filter) qdisc
  # tbf parameters: rate=limit latency=burst
  # burst size calculation: typical is rate * 0.001 (1ms worth of packets)
  # For example: 2gbps with 1ms latency = 2000000000 bits/sec * 0.001 = 2000000 bits = 250000 bytes
  
  # Calculate burst size in bytes (assuming 1ms worth of packets at the specified rate)
  # Formula: (rate in bps) * 0.001 seconds / 8 bits per byte
  local burst_bytes
  case "$rate_normalized" in
    *gbps)
      local gbps_val="${rate_normalized%gbps}"
      burst_bytes=$((gbps_val * 125000))  # (gbps * 1e9 bits/s * 0.001s) / 8 bits/byte
      ;;
    *mbps)
      local mbps_val="${rate_normalized%mbps}"
      burst_bytes=$((mbps_val * 125))  # (mbps * 1e6 bits/s * 0.001s) / 8 bits/byte
      ;;
    *kbps)
      local kbps_val="${rate_normalized%kbps}"
      burst_bytes=$((kbps_val / 8))  # (kbps * 1e3 bits/s * 0.001s) / 8 bits/byte
      ;;
    *)
      # Default burst size: 1 MB for very high rates, smaller for others
      burst_bytes=1000000
      ;;
  esac
  
  # Ensure burst size is reasonable (minimum 1500 bytes for MTU, maximum 10 MB)
  [[ $burst_bytes -lt 1500 ]] && burst_bytes=1500
  [[ $burst_bytes -gt 10485760 ]] && burst_bytes=10485760
  
  # Apply tbf qdisc with the specified rate and calculated burst
  tc qdisc replace dev "$iface" root tbf rate "$rate_normalized" burst "$burst_bytes" latency 100ms >/dev/null 2>&1 || \
    log_warn "Failed to apply packet pacing qdisc to $iface"
  
  log_info "Packet pacing qdisc set on $iface: rate=$rate_normalized burst=$burst_bytes"
}

# shellcheck disable=SC2120
create_ethtool_persist_service() {
  # Generates systemd service to persist ethtool settings and qdisc across reboots
  local svcfile="/etc/systemd/system/ethtool-persist.service"
  if [[ $DRY_RUN -ne 1 ]]; then
    require_root
  fi
  
  log_info "Generating $svcfile to persist ethtool settings and qdisc"
  
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
    
    # Capture qdisc settings (fq for normal mode, tbf for packet pacing)
    if [[ "$TARGET_TYPE" == "dtn" ]] && [[ $APPLY_PACKET_PACING -eq 1 ]]; then
      # DTN with packet pacing: use tbf qdisc
      local pacing_rate="$PACKET_PACING_RATE"
      local rate_normalized="${pacing_rate,,}"
      local burst_bytes
      case "$rate_normalized" in
        *gbps)
          local gbps_val="${rate_normalized%gbps}"
          burst_bytes=$((gbps_val * 125000))
          ;;
        *mbps)
          local mbps_val="${rate_normalized%mbps}"
          burst_bytes=$((mbps_val * 125))
          ;;
        *kbps)
          local kbps_val="${rate_normalized%kbps}"
          burst_bytes=$((kbps_val / 8))
          ;;
        *)
          burst_bytes=1000000
          ;;
      esac
      [[ $burst_bytes -lt 1500 ]] && burst_bytes=1500
      [[ $burst_bytes -gt 10485760 ]] && burst_bytes=10485760
      exec_cmds+=("ExecStart=/sbin/tc qdisc replace dev $iface root tbf rate $rate_normalized burst $burst_bytes latency 100ms")
    else
      # Default: use fq qdisc for fair queuing
      exec_cmds+=("ExecStart=/sbin/tc qdisc replace dev $iface root fq")
    fi
  done
  
  # Show what would be written (always to log; to stdout if requested)
  {
    echo "[Unit]"
    echo "Description=Persist ethtool settings and qdisc (Fasterdata)"
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
  
  # Only write file if not dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would write $svcfile and enable ethtool-persist.service (skipped)"
    return
  fi
  
  {
    echo "[Unit]"
    echo "Description=Persist ethtool settings and qdisc (Fasterdata)"
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
}

ensure_tuned_profile() {
  if ! command -v tuned-adm >/dev/null 2>&1; then
    log_warn "tuned-adm not installed; skipping tuned profile"
    MISSING_TOOLS+=("tuned-adm (dnf install tuned)")
    return
  fi
  local active
  active=$(tuned-adm active 2>/dev/null | awk '{print $4}' || true)
  if [[ "$MODE" == "audit" ]]; then
    local tuned_display
    if [[ -z "$active" ]] || [[ "$active" == "unknown" ]]; then
      tuned_display="$(colorize red "unknown")"
    elif [[ "$active" == "network-throughput" ]]; then
      tuned_display="$(colorize green "$active")"
    else
      tuned_display="$(colorize yellow "$active")"
    fi
    echo "tuned-adm active: ${tuned_display} (rec: network-throughput)"
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
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would set CPU governor to 'performance' (skipped)"
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
    echo "IOMMU enabled via kernel command-line: $(colorize green enabled)"
  else
    log_warn "IOMMU not enabled in kernel command-line (CPU: $cpu_vendor, rec: $iommu_cmd for SR-IOV/perf tuning)"
    echo "IOMMU: $(colorize yellow disabled)"
    echo "IOMMU setup: Edit GRUB configuration to enable IOMMU (per Fasterdata):"
    echo "  1. Edit /etc/default/grub"
    echo "  2. Add to GRUB_CMDLINE_LINUX: $iommu_cmd"
    echo "  3. Example: GRUB_CMDLINE_LINUX=\"root=... $iommu_cmd ...\""
    # Suggest the right GRUB regeneration command depending on boot style
    local regen_cmd
    if command -v grubby >/dev/null 2>&1 && [[ -d /boot/loader/entries ]]; then
      regen_cmd="grubby --update-kernel=ALL --args=\"$iommu_cmd\""
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
      regen_cmd="grub2-mkconfig -o /boot/grub2/grub.cfg"
    elif command -v update-grub >/dev/null 2>&1; then
      regen_cmd="update-grub"
    else
      regen_cmd="(use the distro-specific grub regen command, e.g. grubby/grub2-mkconfig/update-grub)"
    fi
    echo "  4. Regenerate GRUB: ${regen_cmd}"
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
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would setup IOMMU (skipped)"
    return
  fi
  
  require_root
  
  # Warn if not on EL9
  warn_if_not_el9 "IOMMU configuration" || return
  
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
  # If the caller supplied custom IOMMU args via --iommu-args, use that instead
  if [[ -n "$IOMMU_ARGS" ]]; then
    iommu_cmd="$IOMMU_ARGS"
    log_info "Using custom IOMMU args: $IOMMU_ARGS"
  fi
  if echo "$cmdline" | grep -q -E 'iommu=pt|intel_iommu=on|amd_iommu=on'; then
    log_info "IOMMU appears to be enabled: $cmdline"
    return
  fi
  log_warn "IOMMU not in kernel cmdline (CPU: $cpu_vendor). Will add: $iommu_cmd"
  local backup
  backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
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
  local backup
  backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "Dry-run: would copy /etc/default/grub -> $backup"
  else
    cp -a /etc/default/grub "$backup"
    log_info "Backed up /etc/default/grub to $backup"
  fi
  # Read existing value and ensure we append without duplicates
  local existing
  existing=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | head -1 | sed 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/' || true)
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -z "$existing" ]]; then
      echo "Dry-run: would set GRUB_CMDLINE_LINUX=\"$iommu_cmd\""
    else
      if echo "$existing" | grep -qF "$iommu_cmd"; then
        echo "Dry-run: GRUB already contains required IOMMU flags"
      else
        local newval
        newval="$existing $iommu_cmd"
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
        local newval
        newval="$existing $iommu_cmd"
        # Replace the line
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
      fi
    fi
  fi
  # Regenerate grub - on RHEL/Rocky 9+ with BLS, use grubby instead
  if [[ $DRY_RUN -eq 1 ]]; then
    if command -v grubby >/dev/null 2>&1 && [[ -d /boot/loader/entries ]]; then
      echo "Dry-run: would run grubby --update-kernel=ALL --args=\"$iommu_cmd\""
    else
      echo "Dry-run: would run grub2-mkconfig -o /boot/grub2/grub.cfg or update-grub"
    fi
    return
  fi
  
  # Check if system uses BLS (Boot Loader Specification) - RHEL/Rocky 9+
  if command -v grubby >/dev/null 2>&1 && [[ -d /boot/loader/entries ]]; then
    log_info "Detected BLS boot system, using grubby to update kernel entries"
    if ! grubby --update-kernel=ALL --args="$iommu_cmd" 2>&1; then
      log_warn "grubby failed to update kernel entries"
      return
    fi
    log_info "Updated all kernel entries with IOMMU parameters using grubby"
  else
    # Traditional GRUB2 system
    if command -v grub2-mkconfig >/dev/null 2>&1; then
      grub2-mkconfig -o /boot/grub2/grub.cfg
    elif command -v update-grub >/dev/null 2>&1; then
      update-grub || true
    else
      log_warn "No grub2-mkconfig or update-grub found; edit /etc/default/grub manually"
      return
    fi
  fi
  log_info "GRUB config updated; please reboot to apply IOMMU settings"
}

apply_smt() {
  # Apply SMT changes at runtime and optionally persist via GRUB (adds/removes 'nosmt')
  if [[ "$MODE" != "apply" ]]; then
    log_warn "--apply-smt ignored unless --mode apply"
    return
  fi
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would apply SMT setting to $APPLY_SMT (skipped)"
    return
  fi
  
  require_root
  if [[ ! -r /sys/devices/system/cpu/smt/control ]]; then
    log_warn "SMT control not available on this system"
    return
  fi
  local cur
  cur=$(cat /sys/devices/system/cpu/smt/control)
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
    # Warn if not on EL9
    warn_if_not_el9 "SMT persistence (GRUB)" || return
    
    local grubnosmt
    if [[ "$APPLY_SMT" == "off" ]]; then
      grubnosmt="nosmt"
    else
      grubnosmt=""
    fi
    # Edit GRUB similar to apply_iommu (backup/append/remove nosmt)
    local backup
    backup="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Dry-run: would copy /etc/default/grub -> $backup"
    else
      cp -a /etc/default/grub "$backup"
      log_info "Backed up /etc/default/grub to $backup"
    fi
    local existing
    existing=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | head -1 | sed 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/' || true)
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
            local newval
            newval="$existing $grubnosmt"
            echo "Dry-run: would update GRUB_CMDLINE_LINUX to: $newval"
          fi
        else
          # Remove nosmt bit if present (preview)
          local newval
          newval=$(echo "$existing" | sed 's/\bnosmt\b//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
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
            local newval
            newval="$existing $grubnosmt"
            sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
          fi
        else
          # Remove nosmt bit if present
          local newval
          newval=$(echo "$existing" | sed 's/\bnosmt\b//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
          sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$newval\"|" /etc/default/grub
        fi
      fi
    fi
    # Regenerate grub - on RHEL/Rocky 9+ with BLS, use grubby instead
    if [[ $DRY_RUN -eq 1 ]]; then
      if command -v grubby >/dev/null 2>&1 && [[ -d /boot/loader/entries ]]; then
        if [[ -n "$grubnosmt" ]]; then
          echo "Dry-run: would run grubby --update-kernel=ALL --args=\"$grubnosmt\""
        else
          echo "Dry-run: would run grubby --update-kernel=ALL --remove-args=\"nosmt\""
        fi
      else
        echo "Dry-run: would run grub2-mkconfig -o /boot/grub2/grub.cfg or update-grub"
      fi
      return
    fi
    
    # Check if system uses BLS (Boot Loader Specification) - RHEL/Rocky 9+
    if command -v grubby >/dev/null 2>&1 && [[ -d /boot/loader/entries ]]; then
      log_info "Detected BLS boot system, using grubby to update kernel entries"
      if [[ -n "$grubnosmt" ]]; then
        if ! grubby --update-kernel=ALL --args="$grubnosmt" 2>&1; then
          log_warn "grubby failed to update kernel entries"
          return
        fi
        log_info "Updated all kernel entries with nosmt parameter using grubby"
      else
        # Remove nosmt from all kernels
        if ! grubby --update-kernel=ALL --remove-args="nosmt" 2>&1; then
          log_warn "grubby failed to remove nosmt from kernel entries"
          return
        fi
        log_info "Removed nosmt parameter from all kernel entries using grubby"
      fi
    else
      # Traditional GRUB2 system
      if command -v grub2-mkconfig >/dev/null 2>&1; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
      elif command -v update-grub >/dev/null 2>&1; then
        update-grub || true
      else
        log_warn "No grub2-mkconfig or update-grub found; edit /etc/default/grub manually"
        return
      fi
    fi
    log_info "GRUB updated to persist SMT change; reboot to apply"
  fi
}

apply_tcp_cc() {
  # Apply TCP congestion control algorithm
  if [[ -z "$APPLY_TCP_CC" ]]; then
    return
  fi
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would apply TCP congestion control to $APPLY_TCP_CC (skipped)"
    return
  fi
  
  require_root
  log_info "Setting TCP congestion control to $APPLY_TCP_CC"
  if sysctl -w "net.ipv4.tcp_congestion_control=$APPLY_TCP_CC" >/dev/null 2>&1; then
    log_info "TCP congestion control set to $APPLY_TCP_CC"
  else
    log_warn "Failed to set TCP congestion control to $APPLY_TCP_CC"
  fi
}

apply_jumbo() {
  # Apply 9000 MTU jumbo frames to all NICs
  if [[ $APPLY_JUMBO -ne 1 ]]; then
    return
  fi
  
  # Skip if dry-run
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run: would apply jumbo MTU settings (skipped)"
    return
  fi
  
  require_root
  
  local iface current_mtu max_mtu target_mtu=9000
  for iface in $(get_ifaces); do
    current_mtu=$(get_nic_mtu "$iface")
    max_mtu=$(get_nic_max_mtu "$iface")
    
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Dry-run: would set $iface MTU to $target_mtu (current=$current_mtu, max=$max_mtu)"
      continue
    fi
    
    # Check if NIC supports jumbo frames
    if [[ "$max_mtu" != "unknown" && "$max_mtu" -ge "$target_mtu" ]]; then
      if [[ "$current_mtu" != "$target_mtu" ]]; then
        log_info "Setting $iface MTU to $target_mtu (was $current_mtu)"
        if ip link set dev "$iface" mtu "$target_mtu" >/dev/null 2>&1; then
          log_info "$iface MTU set to $target_mtu"
          # Persist MTU across reboots: try NetworkManager (nmcli) first
          if command -v nmcli >/dev/null 2>&1; then
            local conn_names
            conn_names=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v dev="$iface" '$2==dev {print $1}')
            for conn in $conn_names; do
              log_info "Persisting MTU to $conn via nmcli"
              if nmcli connection modify "$conn" 802-3-ethernet.mtu "$target_mtu" >/dev/null 2>&1; then
                nmcli connection up "$conn" >/dev/null 2>&1 || log_warn "Failed to bring connection $conn back up after MTU change"
              else
                log_warn "Failed to persist MTU for $conn via nmcli"
              fi
            done
          else
            # Try interface config file for classic ifcfg (RHEL-style) and set MTU
            local ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-$iface"
            if [[ -f "$ifcfg_file" ]]; then
              if grep -q '^MTU=' "$ifcfg_file"; then
                sed -i "s/^MTU=.*/MTU=$target_mtu/" "$ifcfg_file" || log_warn "Failed to update $ifcfg_file MTU"
              else
                echo "MTU=$target_mtu" >> "$ifcfg_file" || log_warn "Failed to append MTU to $ifcfg_file"
              fi
            else
              log_info "No NM or ifcfg file found; MTU will not be persisted for $iface (please configure NM or ifcfg to persist)"
            fi
          fi
        else
          log_warn "Failed to set $iface MTU to $target_mtu"
        fi
      else
        log_info "$iface MTU already at $target_mtu"
      fi
    else
      if [[ "$max_mtu" == "unknown" ]]; then
        log_warn "$iface max MTU unknown; skipping (may not support jumbo frames)"
      else
        log_warn "$iface max MTU is $max_mtu; cannot set to $target_mtu"
      fi
    fi
  done
}

##############################################################################
# State Management Functions (Save/Restore)
##############################################################################

ensure_state_directories() {
  # Create state management directories if they don't exist
  for dir in "$STATE_DIR" "$STATE_SUBDIR" "$BACKUP_SUBDIR" "$LOG_SUBDIR"; do
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir" 2>/dev/null || {
        log_warn "Cannot create directory $dir (need root permissions for state management)"
        return 1
      }
    fi
  done
  return 0
}

generate_state_filename() {
  local label="$1"
  local timestamp
  timestamp=$(date -u +%Y%m%d-%H%M%S)
  if [[ -n "$label" ]]; then
    echo "${timestamp}-${label}.json"
  else
    echo "${timestamp}.json"
  fi
}

resolve_state_file() {
  # Resolve state file from label or filename
  # Returns full path to state file or empty if not found
  local input="$1"
  
  # If it's an absolute path and exists, use it
  if [[ "$input" == /* ]] && [[ -f "$input" ]]; then
    echo "$input"
    return 0
  fi
  
  # If it's just a filename in the state directory
  if [[ -f "$STATE_SUBDIR/$input" ]]; then
    echo "$STATE_SUBDIR/$input"
    return 0
  fi
  
  # Try to find by label (search for files ending with -LABEL.json)
  local matches
  matches=$(find "$STATE_SUBDIR" -name "*-${input}.json" 2>/dev/null | head -1)
  if [[ -n "$matches" ]]; then
    echo "$matches"
    return 0
  fi
  
  # Not found
  return 1
}

capture_sysctl_state() {
  # Capture current sysctl values as JSON
  local keys=(
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.core.rmem_default"
    "net.core.wmem_default"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
    "net.core.netdev_max_backlog"
    "net.ipv4.tcp_congestion_control"
    "net.ipv4.tcp_mtu_probing"
    "net.core.default_qdisc"
  )
  
  local json="{"
  local first=1
  for key in "${keys[@]}"; do
    local value
    value=$(sysctl -n "$key" 2>/dev/null || echo "")
    if [[ -n "$value" ]]; then
      [[ $first -eq 0 ]] && json+=","
      json+="\"$key\":\"$value\""
      first=0
    fi
  done
  json+="}"
  echo "$json"
}

capture_sysctl_file_state() {
  # Capture /etc/sysctl.d/90-fasterdata.conf state
  local sysctl_file="/etc/sysctl.d/90-fasterdata.conf"
  local json="{"
  json+="\"path\":\"$sysctl_file\","
  
  if [[ -f "$sysctl_file" ]]; then
    json+="\"exists\":true,"
    # Create backup
    local backup_name
    backup_name="90-fasterdata.conf.$(date -u +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_SUBDIR/$backup_name"
    if cp "$sysctl_file" "$backup_path" 2>/dev/null; then
      json+="\"backup_path\":\"$backup_path\","
    else
      json+="\"backup_path\":null,"
    fi
    # Store content as base64
    local content_b64
    content_b64=$(base64 -w 0 "$sysctl_file" 2>/dev/null || base64 "$sysctl_file" 2>/dev/null || echo "")
    json+="\"content_base64\":\"$content_b64\""
  else
    json+="\"exists\":false,"
    json+="\"backup_path\":null,"
    json+="\"content_base64\":null"
  fi
  
  json+="}"
  echo "$json"
}

capture_interface_state() {
  local iface="$1"
  
  # Get interface state
  local state
  state=$(ip link show "$iface" 2>/dev/null | awk '/state/ {print $9}' || echo "unknown")
  
  # Get MTU
  local mtu
  mtu=$(get_nic_mtu "$iface")
  
  # Get txqueuelen
  local txqlen
  if [[ -f /sys/class/net/$iface/tx_queue_len ]]; then
    txqlen=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "0")
  else
    txqlen="0"
  fi
  
  # Get speed
  local speed
  speed=$(get_iface_speed "$iface")
  
  # Get qdisc
  local qdisc_full
  qdisc_full=$(tc qdisc show dev "$iface" 2>/dev/null | head -n1 || echo "unknown")
  
  # Build JSON
  local json="{"
  json+="\"state\":\"$state\","
  json+="\"mtu\":$mtu,"
  json+="\"txqueuelen\":$txqlen,"
  json+="\"speed\":$speed,"
  json+="\"qdisc\":\"$qdisc_full\","
  
  # Ethtool features
  if command -v ethtool >/dev/null 2>&1; then
    local features
    features=$(ethtool -k "$iface" 2>/dev/null | grep -E '^(rx-checksumming|tx-checksumming|scatter-gather|tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|large-receive-offload):' || true)
    
    json+="\"ethtool_features\":{"
    local feat_first=1
    while IFS=: read -r feat_name feat_val; do
      feat_name=$(echo "$feat_name" | tr -d ' ')
      feat_val=$(echo "$feat_val" | awk '{print $1}')
      [[ $feat_first -eq 0 ]] && json+=","
      json+="\"$feat_name\":\"$feat_val\""
      feat_first=0
    done <<< "$features"
    json+="},"
    
    # Ring buffers
    local ring_info
    ring_info=$(ethtool -g "$iface" 2>/dev/null || echo "")
    local rx_cur rx_max tx_cur tx_max
    rx_cur=$(echo "$ring_info" | awk '/^RX:/ {getline; print $2; exit}' || echo "0")
    rx_max=$(echo "$ring_info" | awk '/^RX:/ {print $2; exit}' || echo "0")
    tx_cur=$(echo "$ring_info" | awk '/^TX:/ {getline; print $2; exit}' || echo "0")
    tx_max=$(echo "$ring_info" | awk '/^TX:/ {print $2; exit}' || echo "0")
    
    json+="\"ring_buffers\":{"
    json+="\"rx\":${rx_cur:-0},"
    json+="\"rx_max\":${rx_max:-0},"
    json+="\"tx\":${tx_cur:-0},"
    json+="\"tx_max\":${tx_max:-0}"
    json+="},"
  else
    json+="\"ethtool_features\":{},"
    json+="\"ring_buffers\":{},"
  fi
  
  # NetworkManager connection info
  if command -v nmcli >/dev/null 2>&1; then
    local nm_conn
    nm_conn=$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | awk -F: -v dev="$iface" '$2==dev {print $1; exit}' || echo "")
    json+="\"nm_connection\":\"$nm_conn\","
    
    if [[ -n "$nm_conn" ]]; then
      local nm_mtu
      nm_mtu=$(nmcli -t -f 802-3-ethernet.mtu connection show "$nm_conn" 2>/dev/null | cut -d: -f2 || echo "0")
      json+="\"nm_mtu\":${nm_mtu:-0}"
    else
      json+="\"nm_mtu\":0"
    fi
  else
    json+="\"nm_connection\":\"\","
    json+="\"nm_mtu\":0"
  fi
  
  json+="}"
  echo "$json"
}

capture_ethtool_service_state() {
  # Capture ethtool-persist.service state
  local svc_file="/etc/systemd/system/ethtool-persist.service"
  local json="{"
  json+="\"path\":\"$svc_file\","
  
  if [[ -f "$svc_file" ]]; then
    json+="\"exists\":true,"
    
    # Check if enabled
    local enabled=false
    if systemctl is-enabled ethtool-persist.service &>/dev/null; then
      enabled=true
    fi
    json+="\"enabled\":$enabled,"
    
    # Create backup
    local backup_name
    backup_name="ethtool-persist.service.$(date -u +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_SUBDIR/$backup_name"
    if cp "$svc_file" "$backup_path" 2>/dev/null; then
      json+="\"backup_path\":\"$backup_path\","
    else
      json+="\"backup_path\":null,"
    fi
    
    # Store content as base64
    local content_b64
    content_b64=$(base64 -w 0 "$svc_file" 2>/dev/null || base64 "$svc_file" 2>/dev/null || echo "")
    json+="\"content_base64\":\"$content_b64\""
  else
    json+="\"exists\":false,"
    json+="\"enabled\":false,"
    json+="\"backup_path\":null,"
    json+="\"content_base64\":null"
  fi
  
  json+="}"
  echo "$json"
}

capture_cpu_state() {
  # Capture CPU governor and SMT state
  local json="{"
  
  # CPU governors
  json+="\"governors\":{"
  if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    local cpu=0
    local first=1
    for gov_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      [[ ! -f "$gov_file" ]] && continue
      local gov
      gov=$(cat "$gov_file" 2>/dev/null || echo "unknown")
      [[ $first -eq 0 ]] && json+=","
      json+="\"cpu$cpu\":\"$gov\""
      first=0
      ((cpu++))
    done
  fi
  json+="},"
  
  # SMT state
  if [[ -r /sys/devices/system/cpu/smt/control ]]; then
    local smt
    smt=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo "unknown")
    json+="\"smt\":{\"control\":\"$smt\",\"supported\":true}"
  else
    json+="\"smt\":{\"control\":\"unknown\",\"supported\":false}"
  fi
  
  json+="}"
  echo "$json"
}

capture_tuned_state() {
  # Capture tuned profile state
  local json="{"
  
  if command -v tuned-adm >/dev/null 2>&1; then
    local active
    active=$(tuned-adm active 2>/dev/null | awk '{print $4}' || echo "unknown")
    json+="\"available\":true,"
    json+="\"active_profile\":\"$active\""
  else
    json+="\"available\":false,"
    json+="\"active_profile\":\"unknown\""
  fi
  
  json+="}"
  echo "$json"
}

do_save_state() {
  # Main function to save system state
  require_root
  
  if ! ensure_state_directories; then
    echo "ERROR: Cannot create state directories (need root permissions)" >&2
    return 1
  fi
  
  local state_file
  state_file="$STATE_SUBDIR/$(generate_state_filename "$STATE_LABEL")"
  
  log_info "Saving system state to $state_file"
  
  # Build state JSON
  local state_json="{"
  
  # Metadata
  state_json+="\"metadata\":{"
  state_json+="\"version\":\"1.0\","
  state_json+="\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  state_json+="\"hostname\":\"$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown)\","
  state_json+="\"kernel\":\"$(uname -r)\","
  state_json+="\"label\":\"${STATE_LABEL:-auto}\","
  state_json+="\"created_by\":\"fasterdata-tuning.sh v1.2.0\""
  state_json+="},"
  
  # Sysctl values
  state_json+="\"sysctl\":$(capture_sysctl_state),"
  
  # Sysctl file
  state_json+="\"sysctl_file\":$(capture_sysctl_file_state),"
  
  # Interfaces
  state_json+="\"interfaces\":{"
  local ifs
  ifs=$(get_ifaces)
  local first=1
  for iface in $ifs; do
    [[ $first -eq 0 ]] && state_json+=","
    state_json+="\"$iface\":$(capture_interface_state "$iface")"
    first=0
  done
  state_json+="},"
  
  # Ethtool persist service
  state_json+="\"ethtool_service\":$(capture_ethtool_service_state),"
  
  # CPU state
  state_json+="\"cpu\":$(capture_cpu_state),"
  
  # Tuned state
  state_json+="\"tuned\":$(capture_tuned_state),"
  
  # Warnings
  state_json+="\"warnings\":["
  state_json+="\"Ring buffer settings may not be fully restorable if hardware limits change\","
  state_json+="\"State restoration does not include GRUB/boot configuration\","
  state_json+="\"NetworkManager connection changes may cause brief network interruption\""
  state_json+="]"
  
  state_json+="}"
  
  # Write state file
  if echo "$state_json" | python3 -m json.tool > "$state_file" 2>/dev/null; then
    log_info "State saved successfully to $state_file"
    echo "State file: $state_file"
    if [[ -n "$STATE_LABEL" ]]; then
      echo "Label: $STATE_LABEL"
    fi
    return 0
  else
    # Fallback if python3 not available or json.tool fails
    echo "$state_json" > "$state_file"
    log_info "State saved to $state_file (unformatted JSON)"
    echo "State file: $state_file"
    return 0
  fi
}

do_list_states() {
  # List all saved states
  if [[ ! -d "$STATE_SUBDIR" ]]; then
    echo "No saved states found (directory $STATE_SUBDIR does not exist)"
    return 0
  fi
  
  local states
  states=$(find "$STATE_SUBDIR" -name "*.json" -type f 2>/dev/null | sort -r)
  
  if [[ -z "$states" ]]; then
    echo "No saved states found in $STATE_SUBDIR"
    return 0
  fi
  
  echo "Saved States:"
  echo "============="
  
  while IFS= read -r state_file; do
    local basename
    basename=$(basename "$state_file")
    
    # Try to extract metadata from JSON
    if command -v python3 >/dev/null 2>&1; then
      local timestamp label hostname
      timestamp=$(python3 -c "import json,sys; print(json.load(open('$state_file')).get('metadata',{}).get('timestamp','unknown'))" 2>/dev/null || echo "unknown")
      label=$(python3 -c "import json,sys; print(json.load(open('$state_file')).get('metadata',{}).get('label','unknown'))" 2>/dev/null || echo "unknown")
      hostname=$(python3 -c "import json,sys; print(json.load(open('$state_file')).get('metadata',{}).get('hostname','unknown'))" 2>/dev/null || echo "unknown")
      
      echo ""
      echo "File: $basename"
      echo "  Timestamp: $timestamp"
      echo "  Label: $label"
      echo "  Hostname: $hostname"
      echo "  Path: $state_file"
    else
      echo ""
      echo "File: $basename"
      echo "  Path: $state_file"
    fi
  done <<< "$states"
  
  echo ""
}

do_delete_state() {
  # Delete a saved state file
  require_root
  
  local state_file
  state_file=$(resolve_state_file "$DELETE_STATE")
  
  if [[ -z "$state_file" ]]; then
    echo "ERROR: State file not found: $DELETE_STATE" >&2
    echo "Use --list-states to see available states" >&2
    return 1
  fi
  
  if [[ $AUTO_YES -ne 1 ]]; then
    read -r -p "Delete state file $state_file? [y/N] " resp
    if [[ ! "$resp" =~ ^[Yy]$ ]]; then
      log_info "Delete cancelled"
      return 0
    fi
  fi
  
  if rm "$state_file" 2>/dev/null; then
    log_info "Deleted state file: $state_file"
    return 0
  else
    echo "ERROR: Failed to delete $state_file" >&2
    return 1
  fi
}

do_diff_state() {
  # Show differences between current and saved state
  local state_file
  state_file=$(resolve_state_file "$DIFF_STATE")
  
  if [[ -z "$state_file" ]]; then
    echo "ERROR: State file not found: $DIFF_STATE" >&2
    echo "Use --list-states to see available states" >&2
    return 1
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 required for diff functionality" >&2
    return 1
  fi
  
  log_info "Comparing current state with $state_file"
  
  # Load saved state
  local saved_state
  saved_state=$(cat "$state_file")
  
  echo ""
  echo "Differences between current state and saved state:"
  echo "==================================================="
  echo ""
  
  # Compare sysctl values
  echo "Sysctl Parameters:"
  echo "------------------"
  local keys=(
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.core.rmem_default"
    "net.core.wmem_default"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
    "net.core.netdev_max_backlog"
    "net.ipv4.tcp_congestion_control"
    "net.ipv4.tcp_mtu_probing"
    "net.core.default_qdisc"
  )
  
  for key in "${keys[@]}"; do
    local current saved
    current=$(sysctl -n "$key" 2>/dev/null || echo "")
    saved=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('sysctl',{}).get('$key',''))" 2>/dev/null || echo "")
    
    if [[ "$current" != "$saved" ]]; then
      echo "  $key:"
      echo "    Current: $current"
      echo "    Saved:   $saved"
    fi
  done
  
  echo ""
  echo "Interface Settings:"
  echo "-------------------"
  
  local ifs
  ifs=$(get_ifaces)
  for iface in $ifs; do
    local has_diff=0
    local diff_output=""
    
    # Check MTU
    local current_mtu saved_mtu
    current_mtu=$(get_nic_mtu "$iface")
    saved_mtu=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('mtu',0))" 2>/dev/null || echo "0")
    
    if [[ "$current_mtu" != "$saved_mtu" ]] && [[ "$saved_mtu" != "0" ]]; then
      diff_output+="    MTU: $current_mtu (saved: $saved_mtu)\n"
      has_diff=1
    fi
    
    # Check txqueuelen
    local current_txq saved_txq
    if [[ -f /sys/class/net/$iface/tx_queue_len ]]; then
      current_txq=$(cat "/sys/class/net/$iface/tx_queue_len" 2>/dev/null || echo "0")
    else
      current_txq="0"
    fi
    saved_txq=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('txqueuelen',0))" 2>/dev/null || echo "0")
    
    if [[ "$current_txq" != "$saved_txq" ]] && [[ "$saved_txq" != "0" ]]; then
      diff_output+="    txqueuelen: $current_txq (saved: $saved_txq)\n"
      has_diff=1
    fi
    
    if [[ $has_diff -eq 1 ]]; then
      echo "  $iface:"
      echo -e "$diff_output"
    fi
  done
  
  echo ""
  echo "Use --restore-state to restore the saved configuration"
  echo ""
}

do_restore_state() {
  # Main function to restore system state
  require_root
  
  local state_file
  state_file=$(resolve_state_file "$RESTORE_STATE")
  
  if [[ -z "$state_file" ]]; then
    echo "ERROR: State file not found: $RESTORE_STATE" >&2
    echo "Use --list-states to see available states" >&2
    return 1
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 required for state restoration" >&2
    return 1
  fi
  
  log_info "Restoring system state from $state_file"
  
  # Load state file
  local saved_state
  saved_state=$(cat "$state_file")
  
  # Validate JSON
  if ! python3 -c "import json,sys; json.loads('$saved_state')" 2>/dev/null; then
    echo "ERROR: Invalid JSON in state file" >&2
    return 1
  fi
  
  # Show what will be restored
  echo ""
  echo "State to be restored:"
  echo "====================="
  local saved_hostname saved_timestamp saved_label
  saved_hostname=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('metadata',{}).get('hostname','unknown'))" 2>/dev/null)
  saved_timestamp=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('metadata',{}).get('timestamp','unknown'))" 2>/dev/null)
  saved_label=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('metadata',{}).get('label','unknown'))" 2>/dev/null)
  
  echo "  Hostname: $saved_hostname"
  echo "  Timestamp: $saved_timestamp"
  echo "  Label: $saved_label"
  echo ""
  
  # Warn if different hostname
  local current_hostname
  current_hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown")
  if [[ "$current_hostname" != "$saved_hostname" ]]; then
    log_warn "State was saved on different host: $saved_hostname (current: $current_hostname)"
  fi
  
  if [[ $AUTO_YES -ne 1 ]]; then
    read -r -p "Proceed with restoration? [y/N] " resp
    if [[ ! "$resp" =~ ^[Yy]$ ]]; then
      log_info "Restoration cancelled"
      return 0
    fi
  fi
  
  echo ""
  log_info "Beginning state restoration..."
  
  # Restore sysctl values
  echo ""
  log_info "Restoring sysctl parameters..."
  local keys=(
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.core.rmem_default"
    "net.core.wmem_default"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
    "net.core.netdev_max_backlog"
    "net.ipv4.tcp_congestion_control"
    "net.ipv4.tcp_mtu_probing"
    "net.core.default_qdisc"
  )
  
  for key in "${keys[@]}"; do
    local value
    value=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('sysctl',{}).get('$key',''))" 2>/dev/null || echo "")
    
    if [[ -n "$value" ]]; then
      if sysctl -w "$key=$value" >/dev/null 2>&1; then
        echo "  ✓ $key = $value"
      else
        log_warn "Failed to restore $key=$value"
      fi
    fi
  done
  
  # Restore sysctl file
  echo ""
  log_info "Restoring sysctl configuration file..."
  local sysctl_file="/etc/sysctl.d/90-fasterdata.conf"
  local file_existed
  file_existed=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('sysctl_file',{}).get('exists',False))" 2>/dev/null)
  
  if [[ "$file_existed" == "True" ]]; then
    local content_b64
    content_b64=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('sysctl_file',{}).get('content_base64',''))" 2>/dev/null || echo "")
    
    if [[ -n "$content_b64" ]]; then
      if echo "$content_b64" | base64 -d > "$sysctl_file" 2>/dev/null; then
        echo "  ✓ Restored $sysctl_file"
      else
        log_warn "Failed to restore $sysctl_file"
      fi
    fi
  else
    # File didn't exist in saved state, remove it if present
    if [[ -f "$sysctl_file" ]]; then
      if rm "$sysctl_file" 2>/dev/null; then
        echo "  ✓ Removed $sysctl_file (did not exist in saved state)"
      else
        log_warn "Failed to remove $sysctl_file"
      fi
    else
      echo "  ✓ $sysctl_file (not present in saved state, not present now)"
    fi
  fi
  
  # Restore interface settings
  echo ""
  log_info "Restoring interface settings..."
  local ifs
  ifs=$(get_ifaces)
  
  for iface in $ifs; do
    # Check if interface was in saved state
    local iface_existed
    iface_existed=$(python3 -c "import json,sys; print('$iface' in json.loads('$saved_state').get('interfaces',{}))" 2>/dev/null)
    
    if [[ "$iface_existed" != "True" ]]; then
      log_warn "Interface $iface was not in saved state, skipping"
      continue
    fi
    
    echo "  Interface: $iface"
    
    # Restore MTU
    local saved_mtu
    saved_mtu=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('mtu',0))" 2>/dev/null || echo "0")
    if [[ "$saved_mtu" != "0" ]] && [[ "$saved_mtu" != "null" ]]; then
      if ip link set dev "$iface" mtu "$saved_mtu" >/dev/null 2>&1; then
        echo "    ✓ MTU: $saved_mtu"
      else
        log_warn "Failed to restore MTU for $iface"
      fi
    fi
    
    # Restore txqueuelen
    local saved_txq
    saved_txq=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('txqueuelen',0))" 2>/dev/null || echo "0")
    if [[ "$saved_txq" != "0" ]] && [[ "$saved_txq" != "null" ]]; then
      if ip link set dev "$iface" txqueuelen "$saved_txq" >/dev/null 2>&1; then
        echo "    ✓ txqueuelen: $saved_txq"
      else
        log_warn "Failed to restore txqueuelen for $iface"
      fi
    fi
    
    # Restore ethtool features (best effort)
    if command -v ethtool >/dev/null 2>&1; then
      # Try to restore common features
      local features=("rx-checksumming" "tx-checksumming" "scatter-gather" "tcp-segmentation-offload" "generic-segmentation-offload" "generic-receive-offload" "large-receive-offload")
      for feat in "${features[@]}"; do
        local saved_val
        saved_val=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('ethtool_features',{}).get('$feat',''))" 2>/dev/null || echo "")
        
        if [[ "$saved_val" == "on" ]] || [[ "$saved_val" == "off" ]]; then
          ethtool -K "$iface" "$feat" "$saved_val" >/dev/null 2>&1 || true
        fi
      done
      echo "    ✓ Ethtool features restored (best effort)"
    fi
    
    # Restore qdisc
    local saved_qdisc
    saved_qdisc=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('interfaces',{}).get('$iface',{}).get('qdisc',''))" 2>/dev/null || echo "")
    if [[ -n "$saved_qdisc" ]]; then
      # Extract qdisc type (first word)
      local qdisc_type="${saved_qdisc%% *}"
      if [[ "$qdisc_type" =~ ^(fq|fq_codel|pfifo_fast|mq|tbf)$ ]]; then
        if tc qdisc replace dev "$iface" root "$qdisc_type" >/dev/null 2>&1; then
          echo "    ✓ qdisc: $qdisc_type"
        else
          log_warn "Failed to restore qdisc for $iface"
        fi
      fi
    fi
  done
  
  # Restore ethtool-persist service
  echo ""
  log_info "Restoring ethtool-persist service..."
  local svc_file="/etc/systemd/system/ethtool-persist.service"
  local svc_existed
  svc_existed=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('ethtool_service',{}).get('exists',False))" 2>/dev/null)
  
  if [[ "$svc_existed" == "True" ]]; then
    local content_b64
    content_b64=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('ethtool_service',{}).get('content_base64',''))" 2>/dev/null || echo "")
    
    if [[ -n "$content_b64" ]]; then
      if echo "$content_b64" | base64 -d > "$svc_file" 2>/dev/null; then
        systemctl daemon-reload
        
        local was_enabled
        was_enabled=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('ethtool_service',{}).get('enabled',False))" 2>/dev/null)
        
        if [[ "$was_enabled" == "True" ]]; then
          systemctl enable ethtool-persist.service >/dev/null 2>&1
          echo "  ✓ Restored and enabled ethtool-persist.service"
        else
          systemctl disable ethtool-persist.service >/dev/null 2>&1
          echo "  ✓ Restored ethtool-persist.service (disabled)"
        fi
      else
        log_warn "Failed to restore ethtool-persist.service"
      fi
    fi
  else
    # Service didn't exist in saved state
    if [[ -f "$svc_file" ]]; then
      systemctl disable ethtool-persist.service >/dev/null 2>&1 || true
      if rm "$svc_file" 2>/dev/null; then
        echo "  ✓ Removed ethtool-persist.service (did not exist in saved state)"
      else
        log_warn "Failed to remove ethtool-persist.service"
      fi
      systemctl daemon-reload
    else
      echo "  ✓ ethtool-persist.service (not present in saved state, not present now)"
    fi
  fi
  
  # Restore CPU governor
  echo ""
  log_info "Restoring CPU governor..."
  if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    local cpu=0
    for gov_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      [[ ! -f "$gov_file" ]] && continue
      
      local saved_gov
      saved_gov=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('cpu',{}).get('governors',{}).get('cpu$cpu',''))" 2>/dev/null || echo "")
      
      if [[ -n "$saved_gov" ]] && [[ "$saved_gov" != "null" ]]; then
        if echo "$saved_gov" > "$gov_file" 2>/dev/null; then
          echo "  ✓ CPU $cpu: $saved_gov"
        else
          log_warn "Failed to restore governor for CPU $cpu"
        fi
      fi
      ((cpu++))
    done
  else
    echo "  ✓ CPU governor not supported on this system"
  fi
  
  # Restore tuned profile
  echo ""
  log_info "Restoring tuned profile..."
  if command -v tuned-adm >/dev/null 2>&1; then
    local saved_profile
    saved_profile=$(python3 -c "import json,sys; print(json.loads('$saved_state').get('tuned',{}).get('active_profile',''))" 2>/dev/null || echo "")
    
    if [[ -n "$saved_profile" ]] && [[ "$saved_profile" != "unknown" ]] && [[ "$saved_profile" != "null" ]]; then
      if tuned-adm profile "$saved_profile" >/dev/null 2>&1; then
        echo "  ✓ Tuned profile: $saved_profile"
      else
        log_warn "Failed to restore tuned profile: $saved_profile"
      fi
    else
      echo "  ✓ No tuned profile in saved state"
    fi
  else
    echo "  ✓ tuned-adm not available"
  fi
  
  echo ""
  log_info "State restoration complete!"
  echo ""
  echo "Summary:"
  echo "  - Sysctl parameters restored"
  echo "  - Interface settings restored"
  echo "  - Configuration files restored"
  echo "  - CPU governor restored"
  echo "  - Tuned profile restored"
  echo ""
  echo "Note: Some settings may require a reboot to take full effect."
  echo "Run with --mode audit to verify the restored state."
  echo ""
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
    # Colorize memory based on host target type
    local mem_color="green"
    if [[ "$TARGET_TYPE" == "measurement" ]]; then
      if (( mem_gb >= 16 )); then
        mem_color="green"
      elif (( mem_gb >= 8 )); then
        mem_color="yellow"
      else
        mem_color="red"
      fi
    else
      # DTN thresholds
      if (( mem_gb >= 128 )); then
        mem_color="green"
      elif (( mem_gb >= 32 )); then
        mem_color="yellow"
      else
        mem_color="red"
      fi
    fi
    mem_info_str="$(colorize "$mem_color" "${mem_info_str}")"
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
    smt_status_raw=$(cat /sys/devices/system/cpu/smt/control)
    local recommended_smt
    if [[ "$TARGET_TYPE" == "dtn" ]]; then
      recommended_smt="on"
    else
      recommended_smt="off"
    fi
    # Color based on whether current matches recommended
    if [[ "$smt_status_raw" == "$recommended_smt" ]]; then
      smt_status="$(colorize green "$smt_status_raw")"
    else
      smt_status="$(colorize yellow "$smt_status_raw")"
    fi
  else
    smt_status="not available"
  fi
  
  echo "Host Info:"
  echo "  Hostname: $fqdn"
  
  # Show all FQDNs if multiple NICs have IPs
  local all_fqdns
  all_fqdns=$(get_host_fqdns)
  if [[ -n "$all_fqdns" ]]; then
    echo "  All FQDNs:"
    while IFS= read -r fq; do
      echo "    - $fq"
    done <<<"$all_fqdns"
  fi
  
  echo "  OS: ${os_release:-unknown}"
  echo "  Kernel: $kernel_ver"
  echo "  Memory: $mem_info_str"
  echo "  CPUs: $cpu_info"
  echo "  SMT: $smt_status"
  
  # Show TCP congestion control info
  local tcp_cc_current tcp_cc_available bbrv3_note
  tcp_cc_current=$(get_tcp_cc_current)
  tcp_cc_available=$(get_tcp_cc_available)
  bbrv3_note=""
  if has_bbrv3; then
    bbrv3_note=" (BBRv3 available - preferred)"
  fi
  local tcp_cc_display
  if [[ "$tcp_cc_current" == "bbr" ]]; then
    tcp_cc_display="$(colorize green "$tcp_cc_current")"
  else
    tcp_cc_display="$(colorize yellow "$tcp_cc_current")"
  fi
  echo "  TCP Congestion Control: $tcp_cc_display (available: $tcp_cc_available)$bbrv3_note"
  
  # Check IPv6 configuration
  local ipv6_status
  if [[ $(check_ipv6_config) -eq 1 ]]; then
    ipv6_status=$(colorize green "configured")
  else
    ipv6_status=$(colorize yellow "not configured (consider enabling dual-stack IPv4/IPv6)")
  fi
  echo "  IPv6: $ipv6_status"
}

check_smt() {
  if [[ ! -r /sys/devices/system/cpu/smt/control ]]; then
    log_detail "SMT control not available on this system"
    return
  fi
  local smt_status
  smt_status=$(cat /sys/devices/system/cpu/smt/control)
  log_detail "SMT status: $smt_status"
  
  local recommended_smt
  if [[ "$TARGET_TYPE" == "dtn" ]]; then
    recommended_smt="on"
  else
    # default to measurement behavior
    recommended_smt="off"
  fi
  if [[ "$smt_status" != "$recommended_smt" ]]; then
    log_warn "SMT is currently $smt_status (recommendation: $recommended_smt for $TARGET_TYPE hosts)"
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
    local modpath pkg
    modpath=$(modinfo -n "$drv" 2>/dev/null || true)
    pkg=$(rpm -q --whatprovides "$modpath" 2>/dev/null | head -n1 || true)

    log_detail "Driver $iface: driver=$drv version=${version:-unknown} firmware=${fw:-unknown} vendor=${vendor:-unknown} pkg=${pkg:-unknown} bus=${bus:-unknown}"
    local version_disp fw_disp
    version_disp=$(colorize cyan "${version:-unknown}")
    fw_disp=$(colorize cyan "${fw:-unknown}")
    driver_disp=$(colorize cyan "${drv:-unknown}")
    echo "  $iface: driver=${driver_disp} version=${version_disp} firmware=${fw_disp} vendor=${vendor:-unknown} pkg=${pkg:-unknown}"

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
  if [[ "$TARGET_TYPE" == "dtn" ]]; then
    if [[ $APPLY_PACKET_PACING -eq 1 ]]; then
      echo "- Packet pacing: ENABLED (rate=$PACKET_PACING_RATE, qdisc=tbf)"
    else
      echo "- Packet pacing: not applied (use --apply-packet-pacing with --mode apply to enable)"
      echo "  Recommended pacing rate: $PACKET_PACING_RATE (adjustable via --packet-pacing-rate)"
    fi
  fi
  local sysctl_mismatches_disp
  if (( SYSCTL_MISMATCHES > 0 )); then
    sysctl_mismatches_disp="$(colorize yellow "$SYSCTL_MISMATCHES")"
  else
    sysctl_mismatches_disp="$(colorize green "$SYSCTL_MISMATCHES")"
  fi
  echo "- Sysctl mismatches: $sysctl_mismatches_disp"
  if (( ${#IF_ISSUES[@]} > 0 )); then
    local if_issues_disp
    if_issues_disp="$(colorize yellow "${#IF_ISSUES[@]}")"
    echo "- Interfaces needing attention ($if_issues_disp):"
    for item in "${IF_ISSUES[@]}"; do
      echo "  * $item"
    done
  else
    echo "- Interfaces needing attention: $(colorize green "0")"
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
    echo "- Required tools: $(colorize green "present")"
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
      --packet-pacing-rate) PACKET_PACING_RATE="$2"; shift 2;;
      --apply-packet-pacing) APPLY_PACKET_PACING=1; shift;;
      --color) USE_COLOR=1; shift;;
      --nocolor) USE_COLOR=0; shift;;
        --apply-iommu) APPLY_IOMMU=1; shift;;
        --iommu-args) IOMMU_ARGS="$2"; shift 2;;
      --apply-smt) APPLY_SMT="$2"; shift 2;;
      --persist-smt) PERSIST_SMT=1; shift;;
      --apply-tcp-cc) APPLY_TCP_CC="$2"; shift 2;;
      --apply-jumbo) APPLY_JUMBO=1; shift;;
      --yes) AUTO_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
          --json) OUTPUT_JSON=1; shift;;
      --save-state) SAVE_STATE=1; shift;;
      --label) STATE_LABEL="$2"; shift 2;;
      --restore-state) RESTORE_STATE="$2"; shift 2;;
      --list-states) LIST_STATES=1; shift;;
      --diff-state) DIFF_STATE="$2"; shift 2;;
      --delete-state) DELETE_STATE="$2"; shift 2;;
      --auto-save-before) AUTO_SAVE_BEFORE=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; usage; exit 1;;
    esac
  done

  # Handle state management operations first (they exit early)
  if [[ $LIST_STATES -eq 1 ]]; then
    do_list_states
    exit 0
  fi
  
  if [[ -n "$DELETE_STATE" ]]; then
    do_delete_state
    exit $?
  fi
  
  if [[ -n "$DIFF_STATE" ]]; then
    do_diff_state
    exit $?
  fi
  
  if [[ -n "$RESTORE_STATE" ]]; then
    do_restore_state
    exit $?
  fi
  
  if [[ $SAVE_STATE -eq 1 ]]; then
    do_save_state
    exit $?
  fi

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
  
  # Validate TCP CC flags
  if [[ -n "$APPLY_TCP_CC" ]]; then
    if [[ "$MODE" != "apply" ]]; then
      echo "ERROR: --apply-tcp-cc requires --mode apply" >&2
      exit 1
    fi
    local available_cc
    available_cc=$(get_tcp_cc_available)
    if ! echo "$available_cc" | grep -qw "$APPLY_TCP_CC"; then
      echo "ERROR: TCP congestion control '$APPLY_TCP_CC' not available. Available: $available_cc" >&2
      exit 1
    fi
  fi
  
  # Validate jumbo flag
  if [[ $APPLY_JUMBO -eq 1 && "$MODE" != "apply" ]]; then
    echo "ERROR: --apply-jumbo requires --mode apply" >&2
    exit 1
  fi

  # Validate packet pacing flags
  if [[ $APPLY_PACKET_PACING -eq 1 ]]; then
    if [[ "$MODE" != "apply" ]]; then
      log_warn "--apply-packet-pacing ignored unless --mode apply"
      APPLY_PACKET_PACING=0
    fi
    if [[ "$TARGET_TYPE" != "dtn" ]]; then
      log_warn "--apply-packet-pacing is for DTN targets only (--target dtn); ignoring"
      APPLY_PACKET_PACING=0
    fi
  fi

  if [[ "$OUTPUT_JSON" -eq 1 && "$MODE" != "audit" ]]; then
    echo "ERROR: --json is only supported with --mode audit" >&2; exit 1
  fi
  
  # Validate auto-save-before flag
  if [[ $AUTO_SAVE_BEFORE -eq 1 && "$MODE" != "apply" ]]; then
    echo "ERROR: --auto-save-before requires --mode apply" >&2
    exit 1
  fi
  
  # Auto-save state before applying changes
  if [[ $AUTO_SAVE_BEFORE -eq 1 && "$MODE" == "apply" ]]; then
    log_info "Auto-saving state before applying changes..."
    if [[ -z "$STATE_LABEL" ]]; then
      STATE_LABEL="pre-apply-auto"
    fi
    if do_save_state; then
      echo ""
    else
      log_warn "Failed to auto-save state, continuing with apply..."
    fi
  fi

  if [[ "$MODE" == "audit" ]]; then
    print_host_info
    print_sysctl_diff
    # add spacing for readability before tuned-adm and NIC checks
    echo
    # (no immediate JSON output here; we'll emit JSON after completing interface checks)
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
      if ! iface_packet_pacing_audit "$iface" "$PACKET_PACING_RATE"; then
        IF_ISSUES+=("$iface: needs packet pacing (DTN target with non-tbf qdisc)")
      fi
    else
      iface_apply "$iface"
      iface_apply_packet_pacing "$iface" "$PACKET_PACING_RATE"
    fi
  done

  # Extra host checks
  if [[ "$MODE" == "audit" ]]; then
    # Blank line to separate NIC info from cpufreq/cpupower checks
    echo
    check_cpu_governor
    echo
    # spacing after NICs before cpufreq/cpupower checks
    echo
    check_iommu
    # spacing between IOMMU output and driver info
    echo
    check_smt
    check_drivers
    # If JSON output requested, print machine-readable JSON and exit after gathering all data
    if [[ "$OUTPUT_JSON" -eq 1 ]]; then
      print_json
      exit 0
    fi
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
    if [[ -n "$APPLY_TCP_CC" ]]; then
      apply_tcp_cc
    fi
    if [[ $APPLY_JUMBO -eq 1 ]]; then
      apply_jumbo
    fi
    log_info "Apply complete. Consider rebooting or rerunning audit to confirm settings."
  else
    # spacing after driver info before audit completion line
    echo
    log_info "Audit complete. Entries marked with '*' differ from recommended values."
  fi

  print_summary
}

main "$@"
