---
title: "Quick Deploy — perfSONAR for OSG/WLCG"
description: "Concise, verified quickstarts to deploy perfSONAR Testpoint or Toolkit for OSG/WLCG monitoring."
persona: quick-deploy
owners: ["networking-team@osg-htc.org"]
status: active
tags: [quickstart, perfSONAR, testpoint, toolkit, deployment]
---

# 🚀 Quick Deploy — perfSONAR for OSG/WLCG

Get perfSONAR running on OSG/WLCG in **1-2 hours** with guided installation.

---

## Choose Your Deployment Type

### 🐳 perfSONAR Testpoint (Container-based)

**Best for:** Lightweight deployment, central data archiving, minimal local resources

**Features:**
- Container-based deployment (podman/docker)
- No local web UI (measurements viewed via central services)
- Remote archiving only (data stored at WLCG/OSG central archive)
- Smaller footprint, simplified updates

**Time:** 30-60 minutes | **Guide:** [Install perfSONAR Testpoint](install-perfsonar-testpoint.md)

---

### 📦 perfSONAR Toolkit (RPM-based)

**Best for:** Full-featured installation, local web UI, on-site data storage

**Features:**
- RPM package installation
- Local web interface at `https://hostname/toolkit`
- Local measurement archive (OpenSearch + Logstash)
- Full perfSONAR capabilities
- Site-specific data retention

**Time:** 45-90 minutes | **Guide:** [Install perfSONAR Toolkit](install-perfsonar-toolkit.md)

---

## Before You Start

Understand the deployment landscape and requirements:

- **[Why perfSONAR in OSG/WLCG?](../../perfsonar-in-osg.md)** — motivation,
  importance, and what you're joining

- **[Deployment Models & Options](../../perfsonar/deployment-models.md)** —
  hardware requirements, testpoint vs. toolkit, containerized vs. bare metal

- **[Multiple NIC Guidance](../../perfsonar/multiple-nic-guidance.md)** — if
  deploying on a host with dual NICs

---

## Testpoint Installation Paths

### ⚡ Fast Track — Orchestrated Deploy (Recommended for Testpoint)

**Time:** 30-60 minutes | **Skill level:** System administrator

Follow the **[Testpoint Installation Guide](install-perfsonar-testpoint.md)** which uses the orchestrator for guided,
interactive or non-interactive deploys.

- `perfSONAR-orchestrator.sh` — automates package install, PBR, security, containers, certificates, and mesh enrollment

- Interactive mode: pause at each step to confirm/skip

- Non-interactive mode: `--non-interactive` flag for automated deployment

### 🤖 Automated/Repeatable Deploy

**Time:** Varies | **Skill level:** DevOps/automation engineer

For deploying multiple testpoints or CI/CD pipelines, see **[Automated Setup Examples](automated-setup/README.md)**.

### 🔧 Custom Deploy — Manual Step-by-Step

**Time:** 60–90 minutes | **Skill level:** System administrator + networking knowledge

For multi-NIC setups or customization, consult the legacy manual **[Manual Steps (legacy)](../../perfsonar/installation.md)**.

Covers: toolkit-based installs, detailed package/manual steps, and advanced network configs.

Reference: Ansible playbooks, orchestrator `--non-interactive` mode, containerized workflows.

---

## Post-Deploy Configuration

### Host Tuning (Optional but Recommended)

Optimize kernel and NIC settings for network throughput:

- **[Fasterdata Tuning](../../network-troubleshooting.md)** — ESnet recommendations for high-performance hosts

- Tool: `fasterdata-tuning.sh` (audit and apply modes, ~15 minutes)

### Network Configuration (Multi-NIC)

Set up policy-based routing and static IP addressing:

- **[Multi-NIC Setup Guide](../../perfsonar/multiple-nic-guidance.md)** — when using multiple interfaces

- Tool: `perfSONAR-pbr-nm.sh` (automatic NetworkManager configuration)

### LS Registration & Enrollment

Register your testpoint globally and enroll in test meshes:

- **[LS Registration Setup](../../perfsonar/tools_scripts/README-lsregistration.md)** — register for discovery

- **[Auto-Enrollment in Meshes](../../perfsonar/tools_scripts/README.md)** — join WLCG/OSG test meshes

- Tool: `perfSONAR-update-lsregistration.sh` and `perfSONAR-auto-enroll-psconfig.sh`

### Security Hardening (Optional)

Harden your testpoint with security features:

- **[fail2ban](../../features/fail2ban.md)** — prevent brute-force attacks

- **[nftables](../../features/nftables.md)** — firewall and rate limiting

- **[SELinux](../../features/selinux.md)** — mandatory access control

---

## Validation & Troubleshooting

Once deployed, verify everything is working:

- **[Quick Triage Checklist](../troubleshoot/triage-checklist.md)** — 5-minute verification steps

- **[perfSONAR FAQ](../../perfsonar/faq.md)** — answers to common questions

- **[Troubleshooter Guide](../troubleshoot/landing.md)** — detailed diagnostics if something isn't working

---

## Support & Resources

**Questions or issues?**

- **perfSONAR user community:** [Mailing list](https://lists.internet2.edu/sympa/info/perfsonar-user)

- **OSG-specific help:** [GOC support](https://support.opensciencegrid.org/)

- **WLCG-specific help:** [GGUS ticket](https://ggus.eu/) → "WLCG perfSONAR support"

- **General troubleshooting:** [Network Troubleshooting Guide](../../network-troubleshooting.md)

---

## Related Tools & Scripts

All tools and scripts are available in the [Tools section](../../perfsonar/tools_scripts/README.md), including:

- Orchestrator (`perfSONAR-orchestrator.sh`)

- PBR setup (`perfSONAR-pbr-nm.sh`)

- LS registration (`perfSONAR-update-lsregistration.sh`)

- Host tuning (`fasterdata-tuning.sh`)

- Auto-enrollment (`perfSONAR-auto-enroll-psconfig.sh`)
