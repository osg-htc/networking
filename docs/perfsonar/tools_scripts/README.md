perfSONAR multi-NIC NetworkManager configuration
===============================================

This directory contains `perfSONAR-pbr-nm.sh`, a Bash script to configure
static IPv4/IPv6 addressing and per-NIC source-based routing via NetworkManager
(nmcli).

Quick overview
--------------
- Script: `perfSONAR-pbr-nm.sh`
- Script: `fasterdata-tuning.sh` (Fasterdata audit/apply host tuning script)
- Config file: `/etc/perfSONAR-multi-nic-config.conf`
- Log file: `/var/log/perfSONAR-multi-nic-config.log`

Install helper
--------------
A small helper is provided to populate `/opt/perfsonar-tp/tools_scripts` from
this repository using a shallow sparse checkout. It copies only the
`docs/perfsonar/tools_scripts` directory and preserves executable bits.

- Script: `install_tools_scripts.sh` (path: `docs/perfsonar/tools_scripts/install_tools_scripts.sh`)
- Purpose: idempotent installer for `/opt/perfsonar-tp/tools_scripts`
- Options: `--dry-run` (preview), `--skip-testpoint` (don't clone testpoint repo)

Usage examples
--------------

Preview what would happen (safe):

```bash
bash docs/perfsonar/tools_scripts/install_tools_scripts.sh --dry-run
```

Install into `/opt/perfsonar-tp/tools_scripts` (creates the directory if missing):

```bash
bash docs/perfsonar/tools_scripts/install_tools_scripts.sh
```

If you already have the perfSONAR testpoint repo checked out in `/opt/perfsonar-tp`,
skip cloning with:

```bash
bash docs/perfsonar/tools_scripts/install_tools_scripts.sh --skip-testpoint
```

Fasterdata host tuning script
-----------------------------
- Script: `fasterdata-tuning.sh` — audit/apply host & NIC tuning (ESnet Fasterdata-aligned) for EL9 systems
- Path: `docs/perfsonar/tools_scripts/fasterdata-tuning.sh`

Download
--------
You can download the raw script from the GitHub repo (master branch):

```
https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
```

Or once the site is built, from the site URL:

```
https://osg-htc.org/networking/perfsonar/tools_scripts/fasterdata-tuning.sh
```

Quick install
-------------
```bash
# Download and install in /usr/local/bin
sudo curl -L -o /usr/local/bin/fasterdata-tuning.sh https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh
sudo chmod +x /usr/local/bin/fasterdata-tuning.sh
```

Usage examples
--------------

Audit (default) a measurement host:
```bash
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement
```

Apply tuning (requires root):
```bash
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn
```

Notes
-----
- Shows a `Host Info` summary and performs various checks (sysctl, ethtool, drivers, SMT, IOMMU). IOMMU changes require GRUB edits and reboot; SMT toggles can be done via `/sys/devices/system/cpu/smt/control`.
- In apply mode the script writes `/etc/sysctl.d/90-fasterdata.conf` and writes/enables a systemd `ethtool-persist.service` to persist NIC settings.

Requirements
------------
- Must be run as root. The script now enforces running as root early in
  execution and will exit if run as a non-privileged user. Run it with sudo
  or from a root shell.
- NetworkManager (`nmcli`) is required. The script checks for the presence of
  `nmcli` and will abort if it is not installed. Install NetworkManager via
  your distribution's package manager before running.

Dependencies and package install hints
-------------------------------------

The scripts in this directory call a number of external commands. Install
these packages (or their distro equivalents) before using the tools below.

Essential packages

- bash (Bash 4.3+)
- coreutils (cp/mv/rm/mkdir/chmod/chown)
- iproute2 (provides `ip` and `ip route`)
- NetworkManager (provides `nmcli`)
- rsync (recommended for safe backups; scripts fall back to `cp`)
- curl
- openssl

Optional / feature packages

- nftables (provides `nft`) — required for `perfSONAR-install-nftables.sh`
- fail2ban (provides `fail2ban-client`) — optional; only used if present
- SELinux user tools (provides `getenforce`, `setenforce`, `restorecon`) —
  used by SELinux-related operations
- A container engine: `podman` or `docker` — required for the lsregistration
  updater/extractor when operating against the running testpoint container
- podman-compose or docker-compose — useful for running the testpoint
  compose bundle locally

Note: the `check-deps.sh` helper accepts `podman-compose` as an alternative
provider to `docker-compose` and will report the dependency as satisfied if
either binary is present.

Example install commands

Note: package names vary slightly across distributions. Adapt as needed.

Fedora / RHEL / CentOS (dnf):

```bash
dnf install -y bash coreutils iproute NetworkManager rsync curl openssl nftables podman podman-compose docker-compose fail2ban policycoreutils
```

Debian / Ubuntu (apt):

```bash
apt-get update
apt-get install -y bash coreutils iproute2 network-manager rsync curl openssl nftables podman podman-compose docker.io docker-compose fail2ban policycoreutils
```

If you intend to use the lsregistration container helpers, ensure either
`podman` or `docker` is installed and that the service can list and access
containers (e.g., `podman ps` or `docker ps` works as root).

If `rsync` is not available the scripts will attempt a `cp -a` fallback, but
installing `rsync` provides safer, more robust backups.

Safety first
------------
This script will REMOVE ALL existing NetworkManager connections when run.
Always test in a VM or console-attached host and use `--dry-run` to preview
changes. The script creates a timestamped backup of existing connections before
modifying anything.

Compatibility and fallbacks
---------------------------

- The script prefers to configure routing and policy rules via NetworkManager
  (`nmcli`). However, `nmcli` support for advanced `routes` entries and
  `routing-rules` varies across versions and distributions. If `nmcli` cannot
  apply a given route or routing-rule, the script will attempt a compatibility
  fallback using the `ip route` and `ip rule` commands directly.

- Because the script now requires root, it no longer invokes `sudo` internally
  (the caller should run it with root privileges). This makes behavior
  deterministic in automation and avoids interactive sudo prompts.

How to run (dry-run / debug)
----------------------------

Preview what the script would do without changing the system:

```bash
bash perfSONAR-pbr-nm.sh --dry-run --debug
```

Generate an example or auto-detected config (preview, dry-run only):

```bash
bash perfSONAR-pbr-nm.sh --generate-config-debug
```

Write the auto-detected config to /etc (does not apply changes):

```bash
bash perfSONAR-pbr-nm.sh --generate-config-auto
```

Run for real (be careful):

```bash
bash perfSONAR-pbr-nm.sh
# or non-interactive
bash perfSONAR-pbr-nm.sh --yes

```

Gateway requirement, inference, and generator warnings
-----------------------------------------------------

- Any NIC with an IPv4 address must have a corresponding IPv4 gateway; likewise for IPv6.
- Conservative gateway inference: if a NIC has an address/prefix but no gateway, the tool will try to reuse a gateway from another NIC on the SAME subnet.
  - IPv4: subnets are checked in bash; one unambiguous match is required.
  - IPv6: requires `python3` (`ipaddress` module) to verify the gateway is in the same prefix; link-local gateways (fe80::/10) are not reused; one unambiguous match is required.
  - If multiple gateways match, no guess is made; a warning is logged and validation will require you to set it explicitly.
- This inference runs in two places:
  1) During auto-generation (`--generate-config-auto` or `--generate-config-debug`) so the written config can be immediately useful.
  2) During normal execution after loading the config but before validation, so missing gateways may be filled automatically.

Example: generated config with inferred gateways

```bash
NIC_NAMES=(
  "eth0"
  "eth1"
)

NIC_IPV4_ADDRS=(
  "192.0.2.10"
  "192.0.2.20"
)
NIC_IPV4_PREFIXES=(
  "/24"
  "/24"
)
NIC_IPV4_GWS=(
  "192.0.2.1"  # guessed from eth0
  "192.0.2.1"  # guessed (reused gateway)
)

NIC_IPV6_ADDRS=(
  "2001:db8::10"
  "2001:db8::20"
)
NIC_IPV6_PREFIXES=(
  "/64"
  "/64"
)
NIC_IPV6_GWS=(
  "2001:db8::1"  # guessed from eth0
  "2001:db8::1"  # guessed (reused gateway)
)
```

When gateways are inferred, a NOTE section is added near the bottom of the generated file listing each guess. The script will also print a NOTICE to the console/log. Review and edit the guessed values if needed before applying changes.

If gateways remain missing after inference, the generator writes a WARNING block listing the affected NICs and the script will refuse to proceed until you set the gateways.

Backups and safety
------------------

- Before applying changes, the script creates a timestamped backup of existing NetworkManager connections. It prefers `rsync` when available and falls back to `cp -a`. If the backup fails, the script aborts without removing existing configurations.


Tests
-----

A small set of unit-style tests is provided under `tests/`. These are designed
to exercise pure validation and sanitization helpers without modifying system
configuration. They source the script (functions only) and run checks in a
non-destructive way.

Run the tests:

```bash
cd docs/perfsonar
./tests/run_tests.sh
```

Notes
-----

- The script requires Bash (uses `local -n` namerefs). Run tests on a system
  with Bash 4.3+.
- For more extensive validation, run `shellcheck -x perfSONAR-pbr-nm.sh` and
  address any issues reported.

Contact
-------

Shawn McKee (script author) — [smckee@umich.edu](mailto:smckee@umich.edu)
