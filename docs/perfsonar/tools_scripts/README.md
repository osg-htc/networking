perfSONAR multi-NIC NetworkManager configuration
===============================================

This directory contains `perfSONAR-pbr-nm.sh`, a Bash script to configure
static IPv4/IPv6 addressing and per-NIC source-based routing via NetworkManager
(nmcli).

Quick overview
--------------
- Script: `perfSONAR-pbr-nm.sh`
- Config file: `/etc/perfSONAR-multi-nic-config.conf`
- Log file: `/var/log/perfSONAR-multi-nic-config.log`

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
sudo dnf install -y bash coreutils iproute NetworkManager rsync curl openssl nftables podman podman-compose docker-compose fail2ban policycoreutils
```

Debian / Ubuntu (apt):

```bash
sudo apt-get update
sudo apt-get install -y bash coreutils iproute2 network-manager rsync curl openssl nftables podman podman-compose docker.io docker-compose fail2ban policycoreutils
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
sudo bash perfSONAR-pbr-nm.sh --dry-run --debug
```

Generate an example or auto-detected config (preview, dry-run only):

```bash
sudo bash perfSONAR-pbr-nm.sh --generate-config-debug
```

Write the auto-detected config to /etc (does not apply changes):

```bash
sudo bash perfSONAR-pbr-nm.sh --generate-config-auto
```

Run for real (be careful):

```bash
sudo bash perfSONAR-pbr-nm.sh
# or non-interactive
sudo bash perfSONAR-pbr-nm.sh --yes

Gateway requirement and generator warnings
-----------------------------------------
- Any NIC with an IPv4 address must have a corresponding IPv4 gateway; likewise for IPv6.
- The auto-generator will warn if it cannot detect a gateway for a NIC that has an address. The generated config will include a WARNING block listing affected NICs. Edit `NIC_IPV4_GWS` and/or `NIC_IPV6_GWS` accordingly before running the script to apply changes.

Backups and safety
------------------

- Before applying changes, the script creates a timestamped backup of existing NetworkManager connections. It prefers `rsync` when available and falls back to `cp -a`. If the backup fails, the script aborts without removing existing configurations.
```

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
