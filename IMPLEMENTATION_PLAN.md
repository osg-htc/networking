# perfSONAR Toolkit Guide - Implementation Plan

## Summary

I've copied `install-perfsonar-testpoint.md` to `install-perfsonar-toolkit.md` and analyzed the perfSONAR upstream RPM installation documentation. I've created a detailed adaptation plan showing exactly what needs to change.

## Files Created

1. **`install-perfsonar-toolkit.md`** (copied, ready for editing)
2. **`TOOLKIT_ADAPTATION_PLAN.md`** (detailed change plan)
3. **This document** (implementation roadmap)

## Key Findings

### Deployment Differences

| Aspect | Testpoint (Container) | Toolkit (RPM) |
|--------|----------------------|---------------|
| Installation | podman/docker images | RPM packages via dnf |
| Services | Run inside containers | Native systemd services |
| Web UI | None | https://hostname/toolkit |
| Archive | Remote only | Local OpenSearch/Logstash |
| Updates | Container image pulls | dnf-automatic |
| Management | podman exec commands | Direct systemctl/filesystem |
| Security | Manual scripts | Auto-configured in toolkit bundle |

### Sections Requiring Changes

#### Major Rewrites Required

1. **Step 2** - Replace container prep with RPM installation:
   - Remove: orchestrator, podman packages, container tools
   - Add: DNF repo setup, perfsonar-toolkit installation, post-install scripts
   
2. **Step 5** - Replace container deployment with service management:
   - Remove: All podman-compose, container deployment, seeding, systemd units for containers
   - Add: Service verification, web UI setup guide, dnf-automatic configuration

#### Moderate Adaptations Required

3. **Step 4** - Note that toolkit pre-configures security:
   - perfsonar-toolkit-security already installed fail2ban and firewall rules
   - This step becomes "optional customization" rather than required setup

4. **Step 6** - Adapt pSConfig from container to native:
   - Change: `podman exec` commands → direct filesystem/service commands
   - Add: Web UI configuration option

5. **Step 7** - Adapt registration from container to native:
   - Change: `podman exec` commands → direct edits or web UI
   - Remove: Container-specific auto-update timer (use dnf-automatic instead)
   - Add: Web UI configuration as primary method

6. **Step 8** - Adapt validation from container to native:
   - Change: All `podman` commands → direct `systemctl`/`journalctl` commands
   - Add: Web UI health checks

#### Unchanged Sections

- **Step 1**: Install and Harden EL9 (identical)
- **Step 3**: Configure PBR (identical - works for both)

### Helper Scripts Compatibility

**Work unchanged:**
- ✅ `perfSONAR-pbr-nm.sh` (PBR configuration)
- ✅ `check-perfsonar-dns.sh` (DNS validation)
- ✅ `perfSONAR-install-nftables.sh` (custom firewall rules)

**Need adaptation:**
- ⚠️ `perfSONAR-update-lsregistration.sh` (remove podman exec wrapper)

**Not applicable:**
- ❌ `perfSONAR-orchestrator.sh` (testpoint-specific)
- ❌ `docker-compose.*.yml` (container-specific)
- ❌ `seed_testpoint_host_dirs.sh` (container-specific)
- ❌ `testpoint-entrypoint-wrapper.sh` (container-specific)
- ❌ `install-systemd-units.sh` (container-specific)

## Recommended Implementation Approach

### Option 1: Full Manual Edit (Most Accurate)

**Pros:**
- Complete control over content
- Can refine language and flow
- Ensure consistency with upstream docs

**Cons:**
- Time-consuming (~2-3 hours)
- Manual effort

**Steps:**
1. Work through adaptation plan section by section
2. Edit `install-perfsonar-toolkit.md` directly
3. Add new intro section about choosing testpoint vs toolkit
4. Update landing page with both options
5. Update mkdocs.yml navigation
6. Test build and verify

### Option 2: Automated Bulk Changes + Manual Review (Faster)

**Pros:**
- Faster initial transformation
- Systematic replacement of container commands

**Cons:**
- May need significant cleanup
- Risk of missing context-specific changes

**Steps:**
1. Use multi_replace_string_in_file for systematic changes:
   - Title changes
   - Step 2 rewrite
   - Step 5 rewrite
   - Container command adaptations
2. Manual review and refinement
3. Test build and verify

### Option 3: Hybrid Approach (Recommended)

**Pros:**
- Balance of speed and accuracy
- Leverage automation for mechanical changes
- Human oversight for critical sections

**Cons:**
- Requires careful planning

**Steps:**
1. Manual edits for major sections (Step 2, Step 5)
2. Automated bulk replacements for command adaptations
3. Manual additions (intro section, web UI guidance)
4. Test build and iterate

## Detailed Changes Checklist

### Title and Introduction
- [ ] Change title: "Installing a perfSONAR Testpoint" → "Installing a perfSONAR Toolkit"
- [ ] Update description to mention RPM installation
- [ ] Add key features: local web UI, measurement archive
- [ ] Reference upstream docs: https://docs.perfsonar.net/install_el.html
- [ ] Add "Choosing Between Toolkit and Testpoint" section

### Step 2 – Choose Your Deployment Path
- [ ] Remove entire orchestrator section (Path A)
- [ ] Remove podman/docker packages from manual install
- [ ] Add DNF repository configuration (EPEL, CRB, perfSONAR repo)
- [ ] Add `dnf install perfsonar-toolkit` command
- [ ] Add post-install configuration scripts
- [ ] Keep base packages (jq, curl, bind-utils, etc.)
- [ ] Keep bootstrap helper scripts section

### Step 3 – Configure PBR
- [ ] No changes (identical)

### Step 4 – Configure Security
- [ ] Add info box about toolkit automatic security hardening
- [ ] Reframe as "optional customization" rather than required
- [ ] Note that fail2ban/firewall already configured
- [ ] Keep nftables customization instructions

### Step 5 – Deploy perfSONAR
- [ ] Remove entire container deployment section
- [ ] Add "Start and Verify perfSONAR Services" section
- [ ] Add systemctl verification commands
- [ ] Add "Access the Web Interface" section
- [ ] Add first-time web UI setup instructions
- [ ] Add "Configure Automatic Updates" section (dnf-automatic)
- [ ] Remove all podman/compose references

### Step 6 – Configure pSConfig
- [ ] Replace: `podman exec perfsonar-testpoint ls` → `ls /etc/perfsonar/psconfig`
- [ ] Replace: `podman exec ... systemctl restart` → `systemctl restart`
- [ ] Add web UI configuration option
- [ ] Keep mesh enrollment concepts

### Step 7 – Register with WLCG/OSG
- [ ] Remove container exec commands
- [ ] Add web UI as primary configuration method
- [ ] Keep manual file editing as alternative
- [ ] Remove container auto-update section
- [ ] Note that dnf-automatic handles updates
- [ ] Keep OSG/WLCG registration workflow

### Step 8 – Validation
- [ ] Replace: `podman ps` → `systemctl status pscheduler-*`
- [ ] Replace: `podman logs` → `journalctl -u pscheduler-*`
- [ ] Replace: `podman exec ... systemctl` → `systemctl`
- [ ] Replace: `podman exec ... pscheduler` → `pscheduler`
- [ ] Add web UI health check
- [ ] Add measurement archive validation
- [ ] Keep network/security checks (adapt commands)

### Landing Page Updates
- [ ] Update `landing.md` title to be generic: "perfSONAR Deployment"
- [ ] Add section: "Choose Your Deployment Type"
- [ ] Add comparison: Testpoint (lightweight, container) vs Toolkit (full-featured, RPM)
- [ ] Link to both installation guides
- [ ] Update orchestrator description to be testpoint-specific

### Navigation Updates (mkdocs.yml)
- [ ] Update "Quick Deploy (Testpoint)" → "Quick Deploy Guides" (submenu)
- [ ] Add: "Install perfSONAR Testpoint (Container)"
- [ ] Add: "Install perfSONAR Toolkit (RPM)"
- [ ] Consider adding: "Deployment Comparison"

## Files to Update

1. **Primary documentation:**
   - `docs/personas/quick-deploy/install-perfsonar-toolkit.md` (major edit)
   - `docs/personas/quick-deploy/landing.md` (moderate edit)
   - `mkdocs.yml` (minor edit - navigation)

2. **Optional enhancements:**
   - `docs/perfsonar/deployment-models.md` (add detailed toolkit vs testpoint comparison)
   - Create `docs/personas/quick-deploy/deployment-comparison.md` (side-by-side feature matrix)

## Testing Plan

1. **Build site locally:**
   ```bash
   /root/Git-Repositories/.venv/bin/python3 -m mkdocs build
   ```

2. **Check for backticks:**
   ```bash
   /root/Git-Repositories/.venv/bin/python3 scripts/check_site_for_backticks.py --build
   ```

3. **Preview site:**
   ```bash
   /root/Git-Repositories/.venv/bin/python3 -m mkdocs serve
   ```
   Navigate to http://localhost:8000 and review:
   - Landing page
   - Toolkit installation guide
   - Testpoint installation guide (ensure unchanged)
   - Navigation links

4. **Check for broken links:**
   ```bash
   # If link checker exists
   python3 docs/tools/find_and_remove_broken_links.py
   ```

## Next Steps - Your Decision

I've prepared everything for you to proceed. You have several options:

### Option A: I can start making the edits now
- I'll systematically work through the adaptation plan
- Use multi_replace_string_in_file for efficient bulk changes
- Create a feature branch and open a PR when complete
- Estimated time: 30-45 minutes

### Option B: You want to review the plan first
- You can review `TOOLKIT_ADAPTATION_PLAN.md` in detail
- Provide feedback on specific sections
- Request changes to the approach
- Then I'll proceed with your guidance

### Option C: You want to make edits manually
- Use `TOOLKIT_ADAPTATION_PLAN.md` as your roadmap
- Work through sections at your own pace
- I can help with specific sections as needed

### Option D: Phased approach
- I create the toolkit doc with major sections rewritten
- You review the initial version
- I refine based on your feedback
- Iterate until complete

## Recommendation

I recommend **Option A** (start edits now) because:

1. ✅ I have complete context from upstream docs
2. ✅ The adaptation plan is detailed and systematic
3. ✅ Most changes are mechanical (command adaptations)
4. ✅ Major sections (Step 2, 5) have clear replacement content
5. ✅ We can iterate based on your review of the first draft

The result will be a complete, buildable toolkit guide that you can review, refine, and merge.

**What would you like to do?**
