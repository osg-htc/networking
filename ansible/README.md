# Ansible: perfSONAR Testpoint (Minimal Skeleton)

This minimal Ansible skeleton installs and configures a perfSONAR testpoint on RHEL-family systems with optional features you can toggle:
- fail2ban
- SELinux
- nftables

It is designed to be small, idempotent, and easy to try. Extend as needed for your environment.

## Prerequisites
- Control node with Ansible >= 2.12
- Target host: RHEL/Alma/Rocky 8/9 (sudo privileges)
- Network access to OS and perfSONAR repos

## Inventory Example
See [inventory.example](inventory.example). Place your target host(s) in the `testpoints` group.

## Feature Toggles
These booleans can be set in group_vars, host_vars, or via `-e` extra vars:
- `enable_fail2ban` (default: false)
- `enable_selinux`   (default: false)
- `enable_nftables`  (default: false)

Additional variables:
- `selinux_state`: enforcing | permissive | disabled (default: enforcing when enabled)
- `testpoint_sysctls`: list of sysctl name/value pairs (default provided)
- `testpoint_services`: list of services to enable/start (default provided)

## Quick Start
```bash
# Dry run
ansible-playbook -i ansible/inventory.example ansible/site.yml --check

# Apply with optional features enabled
ansible-playbook -i ansible/inventory.example ansible/site.yml \
  -e enable_fail2ban=true -e enable_selinux=true -e enable_nftables=true
```

## Notes
- nftables: This deploys a minimal ruleset to `/etc/nftables.conf` and enables the nftables service. If you already use another firewall (firewalld/iptables), test carefully and avoid conflicts.
- SELinux: The role sets the SELinux mode only when `enable_selinux=true`. On systems without SELinux, the role is skipped.
- Debian/Ubuntu: Not tested here. Tasks are guarded where practical; contributions welcome.

## Uninstall / Revert
- Remove packages if desired and restore prior firewall configuration manually. This skeleton does not attempt to revert system-wide firewall configuration automatically.

## Replicating `install-perfsonar-testpoint.md` steps (opt-in)

The role includes opt-in tasks to replicate the helper-script-based setup from
`docs/personas/quick-deploy/install-perfsonar-testpoint.md`. These are disabled
by default to avoid surprising changes. Enable them via role defaults or by
passing extra-vars to the playbook.

Key variables (role defaults in `ansible/roles/testpoint/defaults/main.yml`):

- `perfsonar_install_tools_scripts` (bool, default: false)
  - When true, the role will download the helper scripts into
    `/opt/perfsonar-tp/tools_scripts` (from the `docs/perfsonar/tools_scripts` raw URLs)
- `perfsonar_tools_root` (string, default: `/opt/perfsonar-tp`) - destination root
- `perfsonar_run_check_deps` (bool, default: false) - run the `check-deps.sh` script
- `perfsonar_pbr_action` (string, default: 'none') - one of: `none`, `generate`, `apply`, `rebuild`

Examples:

1) Bootstrap helper scripts only (no network changes):

```bash
ansible-playbook -i ansible/inventory.example ansible/site.yml -e perfsonar_install_tools_scripts=true
```

2) Bootstrap scripts and generate `/etc/perfSONAR-multi-nic-config.conf` (auto-detect):

```bash
ansible-playbook -i ansible/inventory.example ansible/site.yml \
  -e perfsonar_install_tools_scripts=true -e perfsonar_pbr_action=generate
```

3) Bootstrap scripts and apply in-place PBR changes (use with caution):

```bash
ansible-playbook -i ansible/inventory.example ansible/site.yml \
  -e perfsonar_install_tools_scripts=true -e perfsonar_pbr_action=apply
```

Notes and safety:

- These tasks call upstream shell scripts on the target node. Review and test
  in a VM/console before running on production hardware. For destructive PBR
  changes use `perfsonar_pbr_action=rebuild`.
- The role will not enable the PBR apply unless the `perfsonar_install_tools_scripts`
  variable is true.

## Example `group_vars/testpoints.yml`

A minimal example of variables for the `testpoints` group (this file is
already present at `ansible/group_vars/testpoints.yml`). Copy or override
these in your environment as needed.

```yaml
# Defaults for the testpoints group — override as needed
enable_fail2ban: false
enable_selinux: false
enable_nftables: false

selinux_state: enforcing

# Services may vary by version; override if needed
testpoint_services:
  - pscheduler-scheduler
  - pscheduler-runner

# Baseline sysctl tuning (override to suit your NIC/OS)
testpoint_sysctls:
  - { name: 'net.core.rmem_max', value: '67108864' }
  - { name: 'net.core.wmem_max', value: '67108864' }
```
