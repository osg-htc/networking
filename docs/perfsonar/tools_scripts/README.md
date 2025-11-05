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

Write the auto-detected config to /etc (does not apply changes):

```bash
sudo bash perfSONAR-pbr-nm.sh --generate-config-auto
```
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
Shawn McKee (script author) - smckee@umich.edu
