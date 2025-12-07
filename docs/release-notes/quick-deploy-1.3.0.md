# Release Notes - Quick Deploy Guide v1.3.0

**Release Date:** November 9, 2025

## Overview


Version 1.3.0 represents a major documentation and usability improvement release. All 20 recommendations from the
comprehensive documentation review have been implemented, significantly enhancing clarity, correctness, and consistency
across the entire perfSONAR testpoint deployment guide.

## High-Priority Fixes

### Correctness Improvements

1. **Fixed documentation typo** - Corrected "configuraiton" → "configuration" in Step 3

1. **Added bind-utils requirement** - DNS validation package now included in Step 1 installation

1. **Clarified command execution context** - All pscheduler commands now show proper container execution syntax

1. **Documented certbot flags** - Added comprehensive explanation of all certbot command options

## Consistency Improvements

### Script Versioning


All helper scripts now include version headers (v1.0.0):

- `check-deps.sh`

- `check-perfsonar-dns.sh`

- `seed_testpoint_host_dirs.sh`

- `perfSONAR-auto-enroll-psconfig.sh`

- `install_tools_scripts.sh`

### Enhanced Script Usability


All scripts now support:

- `--version` flag for version information

- `--help` / `-h` flag with comprehensive usage documentation

- Documented exit codes for automation

- Consistent command-line interface

### Documentation Additions

1. **SELinux volume labels explained** - Clear documentation of `:Z` vs `:z` flag usage

1. **Bootstrap verification** - Step 2 now includes verification commands

1. **Auto-update testing** - Step 6.5 includes testing instructions

1. **Maintenance flexibility** - Ongoing maintenance section now context-aware

## New Sections

### Comprehensive Troubleshooting Guide


Added extensive troubleshooting appendix covering:

- **Container Issues**

- Container won't start or exits immediately

- SELinux denials blocking operations

- **Networking Issues**

- Policy-based routing not working

- DNS resolution failures

- **Certificate Issues**

- Let's Encrypt issuance failures

- Certificate not loaded after renewal

- **perfSONAR Service Issues**

- Services not running

- Apache/pScheduler/OWAMP errors

- **Auto-Update Issues**

- Timer not running

- Images not updating

- **General Debugging Tips**

- Container management commands

- Networking diagnostic commands

- Log inspection commands

### Recovery Instructions

1. **PBR network recovery** - Step 3 now includes detailed recovery procedures for SSH disconnections

1. **Console access guidance** - BMC/iLO/iDRAC usage documented

1. **Backup restoration** - How to restore from NetworkManager connection backups

## Technical Improvements

### Package Management

- `bind-utils` (EL) / `dnsutils` (Debian) added to Step 1 installation

- Dependencies clearly documented for each step

### Command Clarity


All examples now show:

- Proper container execution context (`podman exec -it perfsonar-testpoint ...`)

- Host vs container command distinction

- Full command paths for clarity

### Exit Code Documentation


All scripts now document their exit codes:

- `0` - Success

- `1` - Usage/argument errors

- `2` - Missing prerequisites

- `3` - Operation failures

## Breaking Changes


None. All changes are backward compatible.

## Upgrade Path

### From v1.2.0

1. Pull latest changes:

```bash cd /opt/perfsonar-tp/tools_scripts curl -fsSL https://raw.githubusercontent.com/osg-
htc/networking/master/docs/perfsonar/tools_scripts/install_tools_scripts.sh | bash -s -- /opt/perfsonar-tp
```text

1. Review new troubleshooting guide for common issues

1. Test new script features:

```bash /opt/perfsonar-tp/tools_scripts/check-deps.sh --version /opt/perfsonar-tp/tools_scripts/check-deps.sh --help
```

## Validation


All recommendations from the documentation review have been implemented and verified:

- ✅ Typo corrections

- ✅ Package requirements updated

- ✅ Script version headers added

- ✅ --version flags implemented

- ✅ Help documentation enhanced

- ✅ SELinux documentation added

- ✅ Verification steps added

- ✅ Testing instructions included

- ✅ Troubleshooting guide created

- ✅ Recovery procedures documented

- ✅ Certbot flags explained

- ✅ Maintenance schedules contextualized

- ✅ Command execution clarified

## Git Tags

- Previous: `v1.2.0`

- Current: `v1.3.0`

## Commits

- `132492f` - docs: Major documentation improvements for v1.3.0

- `8d6b10b` - feat: Add --version flag and improved help to all scripts

## Contributors

- Automated code review and implementation

- Based on comprehensive 20-point documentation review

## Next Steps


Future improvements may include:

- Cross-references between main guide and detailed script READMEs

- Centralized logging strategy documentation

- Additional automation examples

- CI/CD integration examples

---

For the complete installation guide, see [Installing a perfSONAR Testpoint for WLCG/OSG](../personas/quick-
deploy/install-perfsonar-testpoint.md).
