# Fasterdata-Tuning.sh Save/Restore Design Document

## Executive Summary

This document outlines the design for adding `--save-state` and `--restore-state` functionality to the fasterdata-tuning.sh script to enable before/after performance testing with the ability to return to a known configuration state.

## Problem Statement

Users need to test performance before and after applying fasterdata tuning configurations. To conduct meaningful tests, they must be able to:
1. Save the current system state before applying changes
2. Apply tuning changes
3. Test performance
4. Restore the original state
5. Repeat with different tuning configurations

## System State Inventory

### What the Script Currently Modifies

#### 1. **Sysctl Parameters** (Persistent & Runtime)
- **File**: `/etc/sysctl.d/90-fasterdata.conf`
- **Runtime**: Applied via `sysctl -w`
- **Parameters Modified**:
  - `net.core.rmem_max`
  - `net.core.wmem_max`
  - `net.core.rmem_default`
  - `net.core.wmem_default`
  - `net.ipv4.tcp_rmem` (min, default, max)
  - `net.ipv4.tcp_wmem` (min, default, max)
  - `net.core.netdev_max_backlog`
  - `net.ipv4.tcp_congestion_control`
  - `net.ipv4.tcp_mtu_probing`
  - `net.core.default_qdisc`

**Restoration Concerns**: 
- ✅ **Trackable**: Current values can be read via `sysctl -n <key>`
- ✅ **Restorable**: Can be written back via `sysctl -w` and file deletion/modification
- ⚠️ **Complexity**: Need to distinguish between system defaults and previously modified values

#### 2. **Per-Interface Settings** (Runtime & Persistent via systemd)
- **File**: `/etc/systemd/system/ethtool-persist.service`
- **Settings Modified Per Interface**:
  - **txqueuelen**: `ip link set dev <iface> txqueuelen <value>`
  - **Ring buffers**: `ethtool -G <iface> rx <max> tx <max>`
  - **Offload features**: `ethtool -K <iface> gro on/off gso on/off tso on/off lro on/off rx on/off tx on/off`
  - **QDisc**: `tc qdisc replace dev <iface> root fq` or `tc qdisc replace dev <iface> root tbf ...`
  - **MTU** (optional): `ip link set dev <iface> mtu <value>`

**Restoration Concerns**:
- ✅ **Trackable**: All current values readable via ethtool, ip, tc commands
- ✅ **Restorable**: Can be reapplied
- ⚠️ **Complexity**: Ring buffer changes may not be fully reversible if hardware doesn't support original values
- ⚠️ **State**: Need to capture current qdisc parameters, not just type

#### 3. **MTU Settings** (Persistent via NetworkManager or ifcfg)
- **NetworkManager**: `nmcli connection modify <conn> 802-3-ethernet.mtu <value>`
- **ifcfg files**: `/etc/sysconfig/network-scripts/ifcfg-<iface>` (legacy)

**Restoration Concerns**:
- ✅ **Trackable**: Current MTU readable via `ip link show <iface>`
- ✅ **Restorable**: Can be reapplied via nmcli or ip link
- ⚠️ **Persistence Mechanism**: Need to track which method was used (NM vs ifcfg)

#### 4. **GRUB Kernel Command Line** (Persistent, requires reboot)
- **File**: `/etc/default/grub`
- **BLS Entries**: `/boot/loader/entries/*.conf` (modified via grubby)
- **Parameters Modified**:
  - IOMMU: `intel_iommu=on iommu=pt` or `amd_iommu=on iommu=pt`
  - SMT: `nosmt` (when disabling)

**Restoration Concerns**:
- ✅ **Trackable**: Current cmdline in `/proc/cmdline`, GRUB config in `/etc/default/grub`
- ✅ **Restorable**: Can modify GRUB config and regenerate
- ⚠️ **Reboot Required**: Changes require reboot to take effect
- ⚠️ **Safety**: Backup required before modifying boot configuration
- ⚠️ **Complexity**: Need to handle both traditional GRUB and BLS systems

#### 5. **SMT (Simultaneous Multithreading)** (Runtime & Optional Persistent)
- **Runtime**: `/sys/devices/system/cpu/smt/control`
- **Persistent**: Via GRUB (see #4)

**Restoration Concerns**:
- ✅ **Trackable**: Current state readable from `/sys/devices/system/cpu/smt/control`
- ✅ **Restorable**: Runtime changes immediate, persistent requires GRUB modification
- ⚠️ **Two Layers**: Runtime and boot-time configuration may differ

#### 6. **CPU Governor** (Runtime only, not persistent by script)
- **Runtime**: `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` or via `cpupower`

**Restoration Concerns**:
- ✅ **Trackable**: Current governor readable per CPU
- ✅ **Restorable**: Can be set via sysfs or cpupower
- ⚠️ **Not Persistent**: Script doesn't persist this, so restoration only needs runtime

#### 7. **Tuned Profile** (Persistent)
- **Command**: `tuned-adm profile <profile>`

**Restoration Concerns**:
- ✅ **Trackable**: Current profile via `tuned-adm active`
- ✅ **Restorable**: Can be set via `tuned-adm profile`
- ⚠️ **Side Effects**: Changing tuned profile may modify other sysctl/system settings not tracked by this script

### Untracked Changes and Side Effects

#### Potential Issues:
1. **Tuned Profile Side Effects**: The `network-throughput` tuned profile may modify sysctls beyond what we track
2. **NetworkManager Modifications**: Changes to NM connections may trigger network restarts
3. **Kernel Module Parameters**: If drivers are updated/reloaded, module parameters may change
4. **systemd Service State**: The `ethtool-persist.service` is created and enabled
5. **File Permissions**: Created files have specific permissions that should be tracked

## Design: State Management System

### State File Format

Use JSON for structured, readable, version-controlled state files.

**State File Location**: `/var/lib/fasterdata-tuning/saved-states/<timestamp>-<label>.json`

**State File Structure**:
```json
{
  "metadata": {
    "version": "1.0",
    "timestamp": "2025-12-10T14:30:00Z",
    "hostname": "perfsonar.example.org",
    "kernel": "5.14.0-362.el9.x86_64",
    "label": "baseline",
    "created_by": "fasterdata-tuning.sh v1.2.0"
  },
  "sysctl": {
    "net.core.rmem_max": "134217728",
    "net.core.wmem_max": "134217728",
    "net.ipv4.tcp_congestion_control": "cubic",
    ...
  },
  "sysctl_file": {
    "path": "/etc/sysctl.d/90-fasterdata.conf",
    "exists": true,
    "content": "# base64 encoded content or null if doesn't exist",
    "backup_path": "/var/lib/fasterdata-tuning/backups/90-fasterdata.conf.20251210143000"
  },
  "interfaces": {
    "ens1f0": {
      "state": "UP",
      "mtu": 1500,
      "txqueuelen": 1000,
      "speed": 10000,
      "qdisc": {
        "type": "mq",
        "full_output": "qdisc mq 0: root..."
      },
      "ethtool": {
        "features": {
          "rx-checksumming": "on",
          "tx-checksumming": "on",
          "scatter-gather": "on",
          "tcp-segmentation-offload": "on",
          "generic-segmentation-offload": "on",
          "generic-receive-offload": "on",
          "large-receive-offload": "off"
        },
        "ring": {
          "rx": 4096,
          "rx_max": 4096,
          "tx": 4096,
          "tx_max": 4096
        }
      },
      "nm_connection": "System ens1f0",
      "nm_mtu": 1500
    }
  },
  "ethtool_persist_service": {
    "exists": false,
    "enabled": false,
    "content": null,
    "backup_path": null
  },
  "grub": {
    "cmdline_current": "BOOT_IMAGE=... root=... intel_iommu=on iommu=pt",
    "grub_file": "/etc/default/grub",
    "grub_cmdline_linux": "root=... quiet",
    "uses_bls": true,
    "backup_path": "/var/lib/fasterdata-tuning/backups/grub.20251210143000"
  },
  "cpu": {
    "governor": {
      "cpu0": "powersave",
      "cpu1": "powersave",
      "unique_governors": ["powersave"]
    },
    "smt": {
      "control": "on",
      "supported": true
    }
  },
  "tuned": {
    "active_profile": "virtual-guest",
    "available": true
  },
  "warnings": [
    "NIC ens1f0: Ring buffer settings may not be fully restorable if hardware limits change",
    "GRUB modifications require reboot to take effect"
  ]
}
```

### Implementation Plan

#### Phase 1: State Capture Functions

Create modular functions to capture each configuration component:

```bash
capture_sysctl_state() {
  # Returns JSON object with all relevant sysctl values
}

capture_interface_state() {
  # Per-interface: MTU, txqueuelen, qdisc, ethtool settings, NM config
}

capture_grub_state() {
  # GRUB config, current cmdline, BLS detection
}

capture_cpu_state() {
  # Governor per CPU, SMT state
}

capture_tuned_state() {
  # Active tuned profile
}

capture_files_state() {
  # Track existence and content of: 
  #   - /etc/sysctl.d/90-fasterdata.conf
  #   - /etc/systemd/system/ethtool-persist.service
  #   - /etc/default/grub
}
```

#### Phase 2: State Restoration Functions

Create restoration functions with validation:

```bash
restore_sysctl_state() {
  # Restore sysctl values from state file
  # Delete /etc/sysctl.d/90-fasterdata.conf if it didn't exist
  # Restore original content if it did exist
}

restore_interface_state() {
  # Per-interface restoration with validation
  # Check if interface still exists
  # Validate values are within hardware limits
}

restore_grub_state() {
  # Restore GRUB configuration
  # Warn about reboot requirement
  # Create backup before modification
}

restore_cpu_state() {
  # Restore CPU governor and SMT
}

restore_tuned_state() {
  # Restore tuned profile
}

restore_files_state() {
  # Restore or remove configuration files
  # Disable/remove systemd services if needed
}
```

#### Phase 3: Command-Line Interface

```bash
# Save current state with label
./fasterdata-tuning.sh --save-state [--label <name>]

# List saved states
./fasterdata-tuning.sh --list-states

# Restore specific state
./fasterdata-tuning.sh --restore-state <state-file-or-label>

# Show diff between current and saved state
./fasterdata-tuning.sh --diff-state <state-file-or-label>

# Delete saved state
./fasterdata-tuning.sh --delete-state <state-file-or-label>

# Apply and auto-save state before
./fasterdata-tuning.sh --mode apply --auto-save-before [--label pre-tuning]
```

### Safety Mechanisms

#### 1. Pre-Flight Checks
- Verify sufficient disk space in `/var/lib/fasterdata-tuning/`
- Check write permissions
- Validate JSON state file format before restoration

#### 2. Atomic Operations
- Create backups before any modifications
- Use temporary files with atomic moves
- Transaction log for multi-step operations

#### 3. Validation
- Verify interface still exists before restoration
- Check hardware capabilities before applying settings
- Validate sysctl keys exist before writing
- Confirm kernel module support for features

#### 4. Rollback on Failure
- If restoration fails mid-way, log error and stop
- Provide manual recovery instructions
- Keep backup files until successful restoration

#### 5. Warnings and Prompts
- Warn if restoring state from different kernel version
- Warn if restoring state from different hardware
- Prompt before GRUB modifications (unless --yes)
- Show diff before restoration (unless --yes)

### File Organization

```
/var/lib/fasterdata-tuning/
├── saved-states/
│   ├── 20251210-143000-baseline.json
│   ├── 20251210-150000-tuned-dtn.json
│   └── 20251210-153000-tuned-measurement.json
├── backups/
│   ├── 90-fasterdata.conf.20251210143000
│   ├── grub.20251210143000
│   └── ethtool-persist.service.20251210143000
├── logs/
│   ├── save-20251210-143000.log
│   └── restore-20251210-150000.log
└── lock
```

### Limitations and Caveats

#### Cannot Be Restored Without Reboot:
1. GRUB kernel command-line changes (IOMMU, nosmt)
2. Kernel module parameter changes

#### Hardware-Dependent Settings:
1. Ring buffer sizes - limited by NIC hardware
2. Ethtool offload features - depends on NIC capabilities
3. Link speed - physical limitation

#### Side Effects Not Tracked:
1. Tuned profile may modify additional sysctls
2. NetworkManager connection changes may trigger network interruptions
3. Driver updates/reloads

#### Race Conditions:
1. If network interfaces are added/removed between save and restore
2. If NetworkManager is actively reconfiguring interfaces
3. If other tools modify the same settings concurrently

### Testing Strategy

#### Unit Tests:
1. State capture functions return valid JSON
2. State restoration functions handle missing interfaces
3. Backup/restore of configuration files
4. JSON schema validation

#### Integration Tests:
1. Save state → Apply tuning → Restore state → Verify identical
2. Save state → Modify manually → Restore → Verify restored
3. Save state on system A → Attempt restore on system B → Proper warnings

#### Validation Tests:
1. Verify sysctl values match after restoration
2. Verify interface settings match after restoration
3. Verify file contents match after restoration
4. Verify systemd service state matches

### Documentation Requirements

1. **User Guide**: How to use save/restore for performance testing workflows
2. **Limitations**: What cannot be restored, what requires reboot
3. **Troubleshooting**: Common issues and manual recovery procedures
4. **State File Format**: Document JSON schema for advanced users
5. **Migration Guide**: How to use with existing installations

## Implementation Priorities

### P0 - Must Have (MVP):
1. ✅ Save/restore sysctl parameters
2. ✅ Save/restore per-interface runtime settings (txqueuelen, qdisc, ethtool)
3. ✅ Save/restore configuration files (90-fasterdata.conf, ethtool-persist.service)
4. ✅ Basic state file management (save, restore, list)
5. ✅ Validation and warnings

### P1 - Should Have:
1. Save/restore GRUB configuration (with reboot warnings)
2. Save/restore CPU governor and SMT
3. Save/restore tuned profile
4. Diff functionality
5. Auto-save before apply

### P2 - Nice to Have:
1. State migration/compatibility between script versions
2. Compressed state files
3. Remote state storage
4. State comparison reports (detailed HTML/markdown)
5. Integration with perfSONAR testing frameworks

## Open Questions

1. **Should we track process-level state** (e.g., running services, firewall rules)?
   - **Decision**: No, out of scope. Focus on network tuning only.

2. **How to handle partial restoration failures?**
   - **Decision**: Stop on first error, log what was restored, provide manual steps.

3. **Should state files be portable between hosts?**
   - **Decision**: No, but provide warnings if hostname/hardware differs.

4. **Should we integrate with git for state versioning?**
   - **Decision**: Phase 2 feature, not MVP.

5. **How to handle NetworkManager vs legacy ifcfg systems?**
   - **Decision**: Detect which is in use, save that info in state, restore using same method.

## Success Criteria

1. User can save current state with one command
2. User can restore saved state and verify all tracked settings match
3. System behaves identically after save/restore cycle (for tracked settings)
4. Clear warnings about settings requiring reboot
5. Comprehensive error messages and recovery guidance
6. Zero data loss: all backups preserved even if restoration fails
