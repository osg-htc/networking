#!/usr/bin/env bash
# DEPRECATED: perfSONAR-extract-lsregistration.sh
# Version: 1.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
#
# This extractor script has been deprecated and removed from active
# maintenance. The preferred approach is to use
# `perfSONAR-update-lsregistration.sh` and the documented restore workflows in
# the Quick Deploy release notes.
#
# See: docs/perfsonar/tools_scripts/DEPRECATION.md

cat <<'EOF' >&2
Deprecated: perfSONAR-extract-lsregistration.sh

This helper is deprecated and no longer supported. Please see
docs/perfsonar/tools_scripts/DEPRECATION.md for details and migration
instructions.

To apply or restore lsregistration settings, prefer:
  /opt/perfsonar-tp/tools_scripts/perfSONAR-update-lsregistration.sh --help

Exiting.
EOF

exit 1
