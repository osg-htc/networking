#!/bin/bash
# patch_apache_ssl_for_letsencrypt.sh
# --------------------------------------
# Purpose:
#   Update Apache SSL configuration in /etc/apache2/sites-available/default-ssl.conf
#   to use Let's Encrypt certificates instead of the default self-signed snakeoil certs.
#
# Usage:
#   ./patch_apache_ssl_for_letsencrypt.sh <SERVER_FQDN>
#
# Example:
#   ./patch_apache_ssl_for_letsencrypt.sh psum05.aglt2.org
#
# Notes:
#   - Run this script on the host after obtaining Let's Encrypt certificates
#     and before starting the perfsonar-testpoint container (or after, then reload).
#   - The script modifies /etc/apache2/sites-available/default-ssl.conf on the host
#     (which is bind-mounted into the container).
#   - If the container is already running, reload Apache inside it after running this script:
#       podman exec perfsonar-testpoint systemctl reload httpd || \
#       podman exec perfsonar-testpoint apachectl -k graceful
#
# Author: OSG perfSONAR deployment tools
# Version: 1.0.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -euo pipefail

APACHE_SSL_CONF="/etc/apache2/sites-available/default-ssl.conf"
BACKUP_SUFFIX=".bak.$(date +%s)"

usage() {
    cat <<EOF
Usage: $0 <SERVER_FQDN>

Patch Apache SSL configuration to use Let's Encrypt certificates.

Arguments:
  SERVER_FQDN    The fully-qualified domain name for which Let's Encrypt certs were issued
                 (e.g., psum05.aglt2.org). The script expects certs to be present at:
                   /etc/letsencrypt/live/<SERVER_FQDN>/fullchain.pem
                   /etc/letsencrypt/live/<SERVER_FQDN>/privkey.pem

Example:
  $0 psum05.aglt2.org

Notes:
  - Creates a backup of the original config file before patching.
  - If the perfsonar-testpoint container is already running, reload Apache after:
      podman exec perfsonar-testpoint systemctl reload httpd

EOF
}

if [[ $# -lt 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    usage
    exit 0
fi

SERVER_FQDN="$1"
CERT_DIR="/etc/letsencrypt/live/${SERVER_FQDN}"
FULLCHAIN="${CERT_DIR}/fullchain.pem"
PRIVKEY="${CERT_DIR}/privkey.pem"

# Validate that certs exist
if [[ ! -f "$FULLCHAIN" ]]; then
    echo "Error: Certificate file not found: $FULLCHAIN"
    echo "Ensure Let's Encrypt certificates have been issued for $SERVER_FQDN first."
    exit 1
fi

if [[ ! -f "$PRIVKEY" ]]; then
    echo "Error: Private key file not found: $PRIVKEY"
    echo "Ensure Let's Encrypt certificates have been issued for $SERVER_FQDN first."
    exit 1
fi

# Validate that Apache config exists
if [[ ! -f "$APACHE_SSL_CONF" ]]; then
    echo "Error: Apache SSL config not found: $APACHE_SSL_CONF"
    echo "Ensure /etc/apache2 has been seeded from the perfsonar-testpoint container."
    exit 1
fi

# Backup the original config
echo "Backing up $APACHE_SSL_CONF -> ${APACHE_SSL_CONF}${BACKUP_SUFFIX}"
cp -a "$APACHE_SSL_CONF" "${APACHE_SSL_CONF}${BACKUP_SUFFIX}"

# Patch the SSL certificate paths using sed
# Replace snakeoil cert paths with Let's Encrypt paths
echo "Patching $APACHE_SSL_CONF to use Let's Encrypt certificates..."

# Let's Encrypt certificate chain file location
CHAIN="${CERT_DIR}/chain.pem"

sed -i.tmp \
    -e "s|SSLCertificateFile\s\+/etc/ssl/certs/ssl-cert-snakeoil.pem|SSLCertificateFile      ${FULLCHAIN}|g" \
    -e "s|SSLCertificateKeyFile\s\+/etc/ssl/private/ssl-cert-snakeoil.key|SSLCertificateKeyFile ${PRIVKEY}|g" \
    "$APACHE_SSL_CONF"

# Add or update SSLCertificateChainFile if it exists or add it after SSLCertificateKeyFile
# First, check if SSLCertificateChainFile already exists in the config
if grep -q "^\s*SSLCertificateChainFile" "$APACHE_SSL_CONF"; then
    # Update existing SSLCertificateChainFile line
    sed -i.tmp2 \
        -e "s|SSLCertificateChainFile\s\+.*|SSLCertificateChainFile ${CHAIN}|g" \
        "$APACHE_SSL_CONF"
    rm -f "${APACHE_SSL_CONF}.tmp2"
else
    # Add SSLCertificateChainFile after SSLCertificateKeyFile line
    sed -i.tmp2 \
        -e "/SSLCertificateKeyFile.*${PRIVKEY}/a\\
                SSLCertificateChainFile ${CHAIN}" \
        "$APACHE_SSL_CONF"
    rm -f "${APACHE_SSL_CONF}.tmp2"
fi

# Remove the temporary sed backup
rm -f "${APACHE_SSL_CONF}.tmp"

echo "✓ Successfully patched $APACHE_SSL_CONF"
echo ""
echo "Certificate paths updated to:"
echo "  SSLCertificateFile      ${FULLCHAIN}"
echo "  SSLCertificateKeyFile   ${PRIVKEY}"
echo "  SSLCertificateChainFile ${CHAIN}"
echo ""
echo "Next steps:"
echo "  1. If the perfsonar-testpoint container is already running, reload Apache:"
echo "       podman exec perfsonar-testpoint systemctl reload httpd"
echo "     or:"
echo "       podman exec perfsonar-testpoint apachectl -k graceful"
echo ""
echo "  2. If the container is not yet started, start it with podman-compose:"
echo "       (cd /opt/perfsonar-tp; podman-compose up -d)"
echo ""
echo "  3. Verify HTTPS is serving the Let's Encrypt certificate:"
echo "       curl -vI https://${SERVER_FQDN}/ 2>&1 | grep -i 'subject:'"
echo ""
