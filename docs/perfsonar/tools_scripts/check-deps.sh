#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Simple dependency checker for perfSONAR tools in this directory.
# Prints missing commands and suggests package install commands for apt/dnf.

PKG_DNF=(bash coreutils iproute NetworkManager rsync curl openssl)
PKG_APT=(bash coreutils iproute2 network-manager rsync curl openssl)

declare -A CMD_TO_PKG_DNF=(
  [ip]=iproute
  [nmcli]=NetworkManager
  [rsync]=rsync
  [curl]=curl
  [openssl]=openssl
  [nft]=nftables
  [fail2ban-client]=fail2ban
  [podman]=podman
  [docker]=docker
  [docker-compose]=docker-compose
)
declare -A CMD_TO_PKG_APT=(
  [ip]=iproute2
  [nmcli]=network-manager
  [rsync]=rsync
  [curl]=curl
  [openssl]=openssl
  [nft]=nftables
  [fail2ban-client]=fail2ban
  [podman]=podman
  [docker]=docker.io
  [docker-compose]=docker-compose
)

ESSENTIAL=(bash ip nmcli rsync curl openssl)
OPTIONAL=(nft fail2ban-client podman docker docker-compose podman-compose restorecon getenforce)

missing=()
missing_optional=()

for cmd in "${ESSENTIAL[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

for cmd in "${OPTIONAL[@]}"; do
  if [ "$cmd" = "docker-compose" ]; then
    # Accept either docker-compose or podman-compose as sufficient
    if ! command -v docker-compose >/dev/null 2>&1 && ! command -v podman-compose >/dev/null 2>&1; then
      missing_optional+=("docker-compose")
    fi
  else
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_optional+=("$cmd")
    fi
  fi
done

echo "Dependency check for perfSONAR tools"
echo
if [ ${#missing[@]} -eq 0 ]; then
  echo "All essential commands present: ${ESSENTIAL[*]}"
else
  echo "Missing essential commands:"
  for m in "${missing[@]}"; do
    echo "  - $m"
  done
  echo
fi

if [ ${#missing_optional[@]} -gt 0 ]; then
  echo "Missing optional commands (may be required for some features):"
  for m in "${missing_optional[@]}"; do
    echo "  - $m"
  done
  echo
fi

# Suggest install commands for common distros (dnf/apt)
suggest_dnf=()
suggest_apt=()
for m in "${missing[@]}" "${missing_optional[@]}"; do
  [ -z "$m" ] && continue
  pkg=${CMD_TO_PKG_DNF[$m]:-}
  if [ -n "$pkg" ]; then suggest_dnf+=("$pkg"); fi
  pkg2=${CMD_TO_PKG_APT[$m]:-}
  if [ -n "$pkg2" ]; then suggest_apt+=("$pkg2"); fi
done

if [ ${#suggest_dnf[@]} -gt 0 ]; then
  # dedupe
  mapfile -t uniq_dnf < <(printf '%s\n' "${suggest_dnf[@]}" | awk '!seen[$0]++')
  echo "Install on Fedora/RHEL/CentOS (dnf):"
  printf '  sudo dnf install -y %s\n' "${uniq_dnf[*]}"
  echo
fi

if [ ${#suggest_apt[@]} -gt 0 ]; then
  mapfile -t uniq_apt < <(printf '%s\n' "${suggest_apt[@]}" | awk '!seen[$0]++')
  echo "Install on Debian/Ubuntu (apt):"
  echo "  sudo apt-get update"
  printf '  sudo apt-get install -y %s\n' "${uniq_apt[*]}"
  echo
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "One or more essential commands are missing. Install the suggested packages before proceeding."
  exit 2
fi

echo "All essential dependencies satisfied. Optional packages can be installed as needed." 
exit 0
