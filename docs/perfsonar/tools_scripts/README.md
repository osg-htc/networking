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

Safety first
------------
This script will REMOVE ALL existing NetworkManager connections when run.
Always test in a VM or console-attached host and use `--dry-run` to preview
changes. The script creates a timestamped backup of existing connections before
modifying anything.

How to run (dry-run / debug)
---------------------------
Preview what the script would do without changing the system:

```bash
sudo bash perfSONAR-pbr-nm.sh --dry-run --debug
```

Generate an example or auto-detected config (preview):

```bash
sudo bash perfSONAR-pbr-nm.sh --generate-config-debug
```

Run for real (be careful):

```bash
sudo bash perfSONAR-pbr-nm.sh
# or non-interactive
sudo bash perfSONAR-pbr-nm.sh --yes
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
