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

- **Not sure which to use?**
  - [Why perfSONAR in OSG/WLCG?](../../perfsonar-in-osg.md) — motivation and context
  - [Deployment Models & Options](../../perfsonar/deployment-models.md) — hardware, container vs RPM, and more

## Choose Your Deployment Type

| Option | Best For | Guide |
|--------|----------|-------|
| 🐳 **Testpoint** (Container) | Lightweight, central archiving, minimal local resources | [Install perfSONAR Testpoint](install-perfsonar-testpoint.md) |
| 📦 **Toolkit** (RPM) | Full-featured, local web UI, on-site data | [Install perfSONAR Toolkit](install-perfsonar-toolkit.md) |

---

## What’s Next?

- Each install guide covers:
  - Post-install validation & troubleshooting
  - Security hardening
  - Registration & mesh enrollment
  - Multi-NIC and advanced network setup

- For automation, multi-host, or CI/CD: see [Automated Setup Examples](automated-setup/README.md)
- For advanced/legacy/manual steps: see [Manual Steps (legacy)](../../perfsonar/installation.md)

---

## Post-Deploy Configuration

### Host Tuning (Optional but Recommended)

Optimize kernel and NIC settings for network throughput:

- **[Fasterdata Tuning](../../perfsonar/tools_scripts/fasterdata-tuning.md)** — ESnet recommendations for high-performance hosts
- Tool: `fasterdata-tuning.sh` (audit and apply modes, ~15 minutes)

---

## Support & Resources

- [Quick Triage Checklist](../troubleshoot/triage-checklist.md)
- [perfSONAR FAQ](../../perfsonar/faq.md)
- [Troubleshooter Guide](../troubleshoot/landing.md)
- [Network Troubleshooting Guide](../../network-troubleshooting.md)
- [Tools & Scripts](../../perfsonar/tools_scripts/README.md)
- [perfSONAR user mailing list](https://lists.internet2.edu/sympa/info/perfsonar-user)
- [OSG GOC support](https://support.opensciencegrid.org/)
- [WLCG GGUS ticket](https://ggus.eu/) → "WLCG perfSONAR support"
