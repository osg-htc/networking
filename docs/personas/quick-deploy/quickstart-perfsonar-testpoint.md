---
title: Quickstart: perfSONAR Testpoint (Minimal)
description: Minimal set of commands and verification to deploy a perfSONAR testpoint for WLCG/OSG.
persona: quick-deploy
owners: [networking-team@osg-htc.org]
status: draft
tags: [quickstart, perfSONAR]
---

## Quickstart (minimal)

1. Prepare a clean EL8/EL9 host with network connectivity and root access.
2. Install packages (example for EL9):

```bash
sudo dnf install -y perfsonar-toolkit
```

3. Run initial configuration (example):

```bash
sudo psconfig setup --auto
```

4. Verify the testpoint is reachable and tests are scheduled:

```bash
curl -sSf http://localhost/ | head
pscheduler tasks --host localhost
```

See `automated-setup/README.md` for Ansible examples and optional feature toggles.
