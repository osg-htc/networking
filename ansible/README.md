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
- nftables: This deploys a minimal ruleset to `/etc/nftables.conf` and enables the nftables service. **WARNING**: The default policy is DROP, which will block all traffic except SSH (port 22), loopback, and established connections. Test carefully before applying to remote systems to avoid being locked out. If you already use another firewall (firewalld/iptables), test carefully and avoid conflicts.
- SELinux: The role sets the SELinux mode only when `enable_selinux=true`. On systems without SELinux, the role is skipped.
- Debian/Ubuntu: Not tested here. Tasks are guarded where practical; contributions welcome.

## Uninstall / Revert
- Remove packages if desired and restore prior firewall configuration manually. This skeleton does not attempt to revert system-wide firewall configuration automatically.
