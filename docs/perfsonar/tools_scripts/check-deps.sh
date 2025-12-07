#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# check-deps.sh
# Simple dependency checker for perfSONAR tools in this directory.
# Prints missing commands and suggests package install commands for apt/dnf.
#
# Version: 1.0.0 - 2025-11-09
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

VERSION="1.0.0"
PROG_NAME="$(basename "$0")"

# Check for --version or --help flags
if [ "${1:-}" = "--version" ]; then
    echo "$PROG_NAME version $VERSION"
    exit 0
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<EOF
Usage: $PROG_NAME [--version|--help]

Checks for required and optional dependencies for perfSONAR installation scripts.
Suggests package installation commands for EL (dnf) and Debian (apt) distributions.

Options:
  --version    Show version information
  --help, -h   Show this help message

Exit codes:
  0 - All essential dependencies present
  1 - Missing essential dependencies
EOF
    exit 0
fi

# PKG_DNF and PKG_APT are kept for documentation and future use; they may not be referenced directly
# shellcheck disable=SC2034
PKG_DNF=(bash coreutils iproute NetworkManager rsync curl openssl)
# shellcheck disable=SC2034
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
  [podman-compose]=podman-compose
  [restorecon]=policycoreutils
  [getenforce]=policycoreutils
  [dig]=bind-utils
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
  [podman-compose]=podman-compose
  [restorecon]=policycoreutils
  [getenforce]=policycoreutils
  [dig]=dnsutils
)

ESSENTIAL=(bash ip nmcli rsync curl openssl)
OPTIONAL=(nft fail2ban-client podman podman-compose restorecon getenforce dig)

missing=()
missing_optional=()

for cmd in "${ESSENTIAL[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

for cmd in "${OPTIONAL[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing_optional+=("$cmd")
  fi
done

echo "Dependency check for perfSONAR install scripts requirements"
echo
if [ ${#missing[@]} -eq 0 ]; then
  # Print essentials on one line regardless of IFS settings
  essentials_joined=$(printf '%s ' "${ESSENTIAL[@]}")
  essentials_joined=${essentials_joined% }
  echo "All essential commands present: ${essentials_joined}"
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

# Also build optional-only install suggestions (useful when essentials are
# already satisfied and the admin only wants the optional feature packages).
suggest_dnf_optional=()
suggest_apt_optional=()
for m in "${missing_optional[@]}"; do
  [ -z "$m" ] && continue
  pkg=${CMD_TO_PKG_DNF[$m]:-}
  if [ -n "$pkg" ]; then suggest_dnf_optional+=("$pkg"); fi
  pkg2=${CMD_TO_PKG_APT[$m]:-}
  if [ -n "$pkg2" ]; then suggest_apt_optional+=("$pkg2"); fi
done

if [ ${#suggest_dnf[@]} -gt 0 ]; then
  # dedupe
  mapfile -t uniq_dnf < <(printf '%s\n' "${suggest_dnf[@]}" | awk '!seen[$0]++')
  echo "Install on Fedora/RHEL/CentOS (dnf):"
  # Join packages with spaces explicitly to avoid IFS (set to "\n\t") introducing newlines
  dnf_pkgs=$(printf '%s ' "${uniq_dnf[@]}")
  dnf_pkgs=${dnf_pkgs% }  # trim trailing space
  printf '  dnf install -y %s\n' "$dnf_pkgs"
  echo
fi

if [ ${#suggest_apt[@]} -gt 0 ]; then
  mapfile -t uniq_apt < <(printf '%s\n' "${suggest_apt[@]}" | awk '!seen[$0]++')
  echo "Install on Debian/Ubuntu (apt):"
  # Join packages with spaces explicitly to avoid IFS newline joining
  apt_pkgs=$(printf '%s ' "${uniq_apt[@]}")
  apt_pkgs=${apt_pkgs% }
  printf '  apt-get update && apt-get install -y %s\n' "$apt_pkgs"
  echo
fi

# If optional packages are missing, print an explicit one-line example that
# installs only those optional packages (no essentials). This is handy when
# essentials are already present and the admin wants to add optional features.
if [ ${#suggest_dnf_optional[@]} -gt 0 ]; then
  mapfile -t uniq_dnf_opt < <(printf '%s\n' "${suggest_dnf_optional[@]}" | awk '!seen[$0]++')
  dnf_opt_pkgs=$(printf '%s ' "${uniq_dnf_opt[@]}")
  dnf_opt_pkgs=${dnf_opt_pkgs% }
  echo "Optional-only install example for Fedora/RHEL/CentOS (dnf):"
  printf '  dnf install -y %s\n' "$dnf_opt_pkgs"
  echo
fi

if [ ${#suggest_apt_optional[@]} -gt 0 ]; then
  mapfile -t uniq_apt_opt < <(printf '%s\n' "${suggest_apt_optional[@]}" | awk '!seen[$0]++')
  apt_opt_pkgs=$(printf '%s ' "${uniq_apt_opt[@]}")
  apt_opt_pkgs=${apt_opt_pkgs% }
  echo "Optional-only install example for Debian/Ubuntu (apt):"
  printf '  apt-get update && apt-get install -y %s\n' "$apt_opt_pkgs"
  echo
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "One or more essential commands are missing. Install the suggested packages before proceeding."
  exit 2
fi

echo "All essential dependencies satisfied. Optional packages can be installed as needed." 
exit 0
