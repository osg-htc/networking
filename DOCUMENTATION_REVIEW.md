# Documentation Review & Improvement Recommendations

**Date**: December 10, 2025  
**Scope**: perfSONAR tools_scripts documentation after PR #60 merge  
**Focus**: Clarity, conciseness, conflicts, and accuracy

---

## Critical Issues (Fix Immediately)

### 1. **Empty "Purpose" Section** ❌
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (line 8)

**Issue**: The "## Purpose" header exists but has no content.

**Impact**: First-time users don't understand what the script does.

**Fix**:
```markdown
## Purpose

The `fasterdata-tuning.sh` script helps network administrators optimize Enterprise Linux 9 systems for high-throughput data transfers by:

- **Auditing** current system configuration against ESnet Fasterdata best practices
- **Applying** recommended tuning automatically with safe defaults
- **Testing** different configurations via save/restore state management (v1.2.0+)
- **Persisting** settings across reboots via systemd and sysctl.d

Recommended for perfSONAR testpoints, Data Transfer Nodes (DTNs), and dedicated high-performance networking hosts.
```

---

### 2. **Incorrect File Path in Documentation** ❌
**Files**: 
- `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (lines 42, 120)

**Issue**: Documentation states script writes to `/etc/sysctl.conf` but actual script writes to `/etc/sysctl.d/90-fasterdata.conf`

**Current Text**:
```
- Applies and persists sysctl settings in `/etc/sysctl.conf`...
- Apply mode writes to `/etc/sysctl.conf` and creates...
```

**Actual Behavior** (from script line 976):
```bash
local sysctl_file="/etc/sysctl.d/90-fasterdata.conf"
```

**Impact**: Users may look in wrong location for sysctl settings, confusion about how persistence works.

**Fix**: Replace both occurrences with `/etc/sysctl.d/90-fasterdata.conf`

---

### 3. **Malformed Code Blocks** ⚠️
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (lines 77-142)

**Issue**: Several code blocks have inconsistent formatting:
- Line 77: Missing opening backtick fence for bash block
- Lines 81-84: Unnecessary blank line inside code block
- Lines 90-93: Unnecessary blank line inside code block  
- Lines 98-101: Unnecessary blank line inside code block
- Lines 130-133: Line break in middle of command

**Example of Current (broken)**:
```markdown
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement

 
Apply tuning (requires root):

```bash

sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn

```
```

**Should be**:
```markdown
```bash
# Audit mode (default)
bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode audit --target measurement

# Apply tuning (requires root)
sudo bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh --mode apply --target dtn
\```
```

**Impact**: Code blocks won't render properly, may confuse copy-paste, looks unprofessional.

---

## Medium Priority Issues (Should Fix Soon)

### 4. **Redundant Information Between README and Full Documentation** 📚
**Files**: 
- `docs/perfsonar/tools_scripts/README.md` (lines 40-82)
- `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (entire file)

**Issue**: README contains detailed usage examples that duplicate content in the full fasterdata-tuning.md guide.

**Impact**: 
- Maintenance burden (update in two places)
- Users may miss updates if only reading one file
- README becomes too long, defeating purpose of "quick start"

**Recommendation**:
- Keep README focused on **quick reference** (3-5 key examples max)
- Move detailed examples, flags documentation, and workflow to fasterdata-tuning.md
- Ensure README always links to full guide for details

**Example README section should be**:
```markdown
### Fasterdata Tuning Script

Audit and apply ESnet Fasterdata-inspired host and NIC tuning for EL9 systems.

**NEW in v1.2.0**: Save/restore state functionality for testing configurations.

**Quick Usage:**

```bash
# Audit current settings (no changes)
/usr/local/bin/fasterdata-tuning.sh --mode audit --target measurement

# Apply tuning (requires root)
sudo /usr/local/bin/fasterdata-tuning.sh --mode apply --target dtn

# Save state before testing
sudo /usr/local/bin/fasterdata-tuning.sh --save-state --label baseline
\```

**Full Documentation**: [Fasterdata Tuning Guide](fasterdata-tuning.md) — includes save/restore workflows, all flags, troubleshooting, and examples

**Download**: [Direct Link](https://raw.githubusercontent.com/osg-htc/networking/master/docs/perfsonar/tools_scripts/fasterdata-tuning.sh)
```

---

### 5. **Inconsistent Script Path References** 📝
**Throughout documentation**

**Issue**: Mixed usage of different script paths:
- `bash docs/perfsonar/tools_scripts/fasterdata-tuning.sh` (relative from repo root)
- `/usr/local/bin/fasterdata-tuning.sh` (installed location)
- `fasterdata-tuning.sh` (bare command assuming PATH)

**Impact**: Confusion about where script should be or how to run it.

**Recommendation**: Establish convention:
- **In usage examples**: Use installed path `/usr/local/bin/fasterdata-tuning.sh` OR just `fasterdata-tuning.sh` if added to PATH
- **In developer/contributor docs**: Use relative path from repo root
- Add note at top: "Examples assume script is installed to `/usr/local/bin/`. Adjust path if installed elsewhere."

---

### 6. **Missing Cross-References** 🔗
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md`

**Issue**: Document mentions "packet-pacing.md" but doesn't clearly link other related documentation:
- Multiple NIC setup (for multi-interface scenarios)
- perfSONAR installation guides (for context on when to use this)
- Troubleshooting guide (for when things go wrong)

**Recommendation**: Add "Related Documentation" section:
```markdown
## Related Documentation

- **[Packet Pacing Guide](../packet-pacing.md)** — Deep dive on DTN packet pacing
- **[Multiple NIC Guidance](../multiple-nic-guidance.md)** — Policy-based routing for multi-homed hosts
- **[perfSONAR Installation](../../personas/quick-deploy/landing.md)** — Deploy perfSONAR first, then tune
- **[Network Troubleshooting](../../network-troubleshooting.md)** — Debug connectivity issues
```

---

### 7. **Checksum Verification Section May Be Outdated** 🔐
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (lines 25-31)

**Issue**: References `fasterdata-tuning.sh.sha256` checksum file but doesn't indicate if this file exists or is maintained.

**Action Needed**: 
1. Check if `.sha256` file exists in repo
2. If not, either:
   - Create and maintain it (recommended for security)
   - Remove this section from docs
3. Consider adding GPG signature verification as alternative

**Command to check**:
```bash
ls docs/perfsonar/tools_scripts/fasterdata-tuning.sh.sha256
```

---

## Low Priority / Style Improvements

### 8. **Inconsistent Heading Capitalization** 📐
**Files**: Various

**Issue**: Mixed heading styles:
- "State Management: Save & Restore Configurations" (Title Case)
- "Why use this script?" (Sentence case)
- "Verify the checksum" (Sentence case)

**Recommendation**: Choose one style and apply consistently. Suggest **Sentence case** for readability:
- "State management: Save and restore configurations"
- "Why use this script?"
- "Verify the checksum"

---

### 9. **Verbose "What IS/NOT saved" Lists** 📋
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (lines 283-310)

**Issue**: Very detailed lists with checkmarks/crosses may be better as a table for scannability.

**Current**:
```
**What IS saved/restored:**

- ✅ Sysctl parameters (runtime values)
- ✅ Configuration files...
- ✅ Per-interface settings...
```

**Consider**: Compact table format:
```markdown
| Component | Saved/Restored | Notes |
|-----------|----------------|-------|
| Sysctl parameters | ✅ Yes | Runtime values |
| Per-interface settings | ✅ Yes | txqueuelen, MTU, ring buffers, offloads, qdisc |
| Configuration files | ✅ Yes | `/etc/sysctl.d/90-fasterdata.conf`, systemd services |
| GRUB kernel cmdline | ❌ No | Requires reboot; not suitable for testing cycles |
| Kernel module parameters | ❌ No | Out of scope |
```

---

### 10. **Long Example Workflow** 📖
**File**: `docs/perfsonar/tools_scripts/fasterdata-tuning.md` (lines 263-281)

**Issue**: 15-step workflow example is thorough but may overwhelm users.

**Recommendation**: 
- Keep detailed workflow but add a "Quick Testing Workflow" summary box at top:

```markdown
### Quick Testing Workflow

**TL;DR**: Save baseline → Apply tuning → Test → Restore → Compare

```bash
sudo fasterdata-tuning.sh --save-state --label baseline
sudo fasterdata-tuning.sh --mode apply --target measurement --auto-save-before
# Run your performance tests here
sudo fasterdata-tuning.sh --restore-state baseline --yes
fasterdata-tuning.sh --diff-state baseline
\```

**For detailed step-by-step workflow with multiple tuning profiles, see below.**
```

---

### 11. **README.md Lacks Version Information** ℹ️
**File**: `docs/perfsonar/tools_scripts/README.md`

**Issue**: No indication of which script versions have which features.

**Recommendation**: Add version table or release notes link:
```markdown
## Available Tools

| Tool | Current Version | Documentation |
|------|-----------------|---------------|
| **fasterdata-tuning.sh** | v1.2.0 | [Fasterdata Tuning Guide](fasterdata-tuning.md) |
| **perfSONAR-pbr-nm.sh** | v2.1.0 | [Multiple NIC Guidance](../multiple-nic-guidance.md) |
...

**Release Notes**: [CHANGELOG.md](CHANGELOG.md)
```

---

### 12. **Old README Cleanup** 🗑️
**File**: `docs/perfsonar/tools_scripts/README-old.md`

**Issue**: Old README backup file still in repository from PR #59 refactoring.

**Recommendation**: 
- If no longer needed, remove from repo
- If kept for historical reference, move to `archive/` directory
- Update any references if it's meant to be preserved

---

## Positive Observations ✨

**What's Working Well**:

1. ✅ **Save/Restore Documentation** is comprehensive and well-structured
2. ✅ **Code examples** are practical and copy-pasteable (aside from formatting issues noted)
3. ✅ **Safety warnings** are prominent and clear
4. ✅ **Table-based tool overview** in README is excellent
5. ✅ **State file format documentation** is detailed and useful for advanced users
6. ✅ **Caveats and limitations** are clearly documented
7. ✅ **Design document** (SAVE_RESTORE_DESIGN.md) is excellent for maintainers

---

## Action Items Summary

### Immediate (Critical):
- [ ] Fill in empty "Purpose" section
- [ ] Fix sysctl file path references (`/etc/sysctl.conf` → `/etc/sysctl.d/90-fasterdata.conf`)
- [ ] Fix malformed code blocks (remove extra blank lines, fix fence markers)

### Soon (Medium Priority):
- [ ] Reduce README duplication, keep it focused on quick reference
- [ ] Standardize script path references across all docs
- [ ] Add cross-references to related documentation
- [ ] Verify checksum file exists or remove that section
- [ ] Consider cleanup of README-old.md

### Nice to Have (Low Priority):
- [ ] Standardize heading capitalization
- [ ] Convert "What IS/NOT saved" to table format
- [ ] Add "Quick Testing Workflow" summary box
- [ ] Add version information to README
- [ ] Consider archiving SAVE_RESTORE_DESIGN.md (or move to docs/design/)

---

## Suggested Priority Order

1. **Phase 1** (30 minutes): Fix critical issues (#1, #2, #3)
2. **Phase 2** (1 hour): Address medium priority issues (#4, #5, #6, #7)
3. **Phase 3** (optional): Style improvements and polish

---

## Testing Recommendations

After documentation updates:
- [ ] Render docs locally with mkdocs to verify formatting
- [ ] Test all copy-paste code examples on clean EL9 system
- [ ] Verify all internal links work
- [ ] Check external links (fasterdata.es.net) are still valid
- [ ] Spell check all modified files

---

## Additional Notes

The documentation is generally **high quality** and the recent save/restore additions are well-documented. The issues found are mostly cosmetic formatting problems and minor inconsistencies rather than fundamental structural issues. Fixing the critical items will make the documentation production-ready.
