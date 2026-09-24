# Register perfSONAR service in WLCG CRIC

The registration workflow is managed in WLCG CRIC.

Use the official instructions:

- <https://cric.docs.cern.ch/how-to/register-perfsonar/>

Quick notes:

- Register one service per role (`Latency` and/or `Bandwidth`) per host.
- Update existing entries when service role or hostname changes; avoid duplicates.
- Ensure service state is `ACTIVE`.
- GOCDB and OSG Topology registration are not required for this registration workflow.

If your site is not a WLCG member and cannot access WLCG CRIC, email
`wlcg-perfsonar-support@cern.ch` with the host FQDN and whether it is a latency
or throughput service.
