# perfSONAR Testpoint Container Restart Loop Issue

## Problem Description

The perfSONAR testpoint container enters a restart loop when using certain docker-compose.yml configurations. Thecontainer continuously restarts and fails to initialize systemd properly.

## Root Cause

The issue occurs when the docker-compose.yml file is configured with:

* `privileged: true`

* `cgroupns: private`

* **Missing** `/sys/fs/cgroup:/sys/fs/cgroup:rw` volume mount

The systemd process inside the container requires proper cgroup access to function. Without the cgroup volume mount,
systemd cannot initialize properly, causing the container to fail and restart repeatedly.

## Solution

Use the recommended docker-compose.yml configuration from the repository which includes:

``` yaml services: testpoint: container_name: perfsonar-testpoint image: hub.opensciencegrid.org/osg-htc/perfsonar-
testpoint:production network_mode: "host" cgroup: host  # Use cgroup: host instead of cgroupns: private environment:

* TZ=UTC

restart: unless-stopped tmpfs:

* /run

* /run/lock

* /tmp

volumes:

* /sys/fs/cgroup:/sys/fs/cgroup:rw  # REQUIRED for systemd

* /opt/perfsonar-tp/psconfig:/etc/perfsonar/psconfig:Z

* /var/www/html:/var/www/html:z

* /etc/apache2:/etc/apache2:z

* /etc/letsencrypt:/etc/letsencrypt:z

tty: true pids_limit: 8192 cap_add:

* CAP_NET_RAW

labels:

* io.containers.autoupdate=registry


``` text

## Fixing Existing Deployments

If you have an existing deployment with the restart loop issue:

1. Stop the containers:

``` bash cd /opt/perfsonar-tp podman-compose down
```

1. Update the docker-compose.yml file to use the recommended configuration from:

``` bash curl -fsSL \ <https://raw.githubusercontent.com/osg-
htc/networking/master/docs/perfsonar/tools_scripts/dockercompose.yml> \ -o /opt/perfsonar-tp/docker-compose.yml
``` text

1. Restart the service:

``` bash systemctl restart perfsonar-testpoint
```

## Verification

Check that containers are running properly:

``` bash podman ps systemctl status perfsonar-testpoint
``` text

The perfsonar-testpoint container should show status "Up" and not be restarting.

## Related Files

* Recommended compose file: `docs/perfsonar/tools_scripts/docker-compose.yml`

* Systemd service installer: `docs/perfsonar/tools_scripts/install-systemd-service.sh`

* Installation guide: `docs/perfsonar/install-testpoint.md`
