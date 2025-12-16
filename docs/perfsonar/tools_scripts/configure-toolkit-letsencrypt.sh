#!/bin/bash
# configure-toolkit-letsencrypt.sh
# ---------------------------------
# Purpose:
#   Update Apache SSL configuration for perfSONAR Toolkit RPM installations
#   to use Let's Encrypt certificates instead of the default self-signed certificates.
#
# Usage:
#   ./configure-toolkit-letsencrypt.sh <SERVER_FQDN>
#
# Example:
#   ./configure-toolkit-letsencrypt.sh ps-toolkit.example.org
#
# Notes:
#   - Run this script on the host after obtaining Let's Encrypt certificates
#   - The script modifies /etc/httpd/conf.d/ssl.conf (RHEL/AlmaLinux/Rocky Apache config)
#   - After running this script, reload Apache: systemctl reload httpd
#
# Author: OSG perfSONAR deployment tools
# Version: 1.0.0
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC

set -euo pipefail

# Apache SSL configuration for RHEL/AlmaLinux/Rocky (httpd)
APACHE_SSL_CONF="/etc/httpd/conf.d/ssl.conf"
BACKUP_SUFFIX=".bak.$(date +%s)"

usage() {
    cat <<EOF
Usage: $0 <SERVER_FQDN>

Configure Apache SSL to use Let's Encrypt certificates for perfSONAR Toolkit.

Arguments:
  SERVER_FQDN    The fully-qualified domain name for which Let's Encrypt certs were issued
                 (e.g., ps-toolkit.example.org). The script expects certs to be present at:
                   /etc/letsencrypt/live/<SERVER_FQDN>/fullchain.pem
                   /etc/letsencrypt/live/<SERVER_FQDN>/privkey.pem

Example:
  $0 ps-toolkit.example.org

Notes:
  - Creates a backup of the original config file before patching.
  - After running this script, reload Apache:
      systemctl reload httpd

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
CHAIN="${CERT_DIR}/chain.pem"

# Validate that certs exist
if [[ ! -f "$FULLCHAIN" ]]; then
    echo "Error: Certificate file not found: $FULLCHAIN"
    echo "Ensure Let's Encrypt certificates have been issued for $SERVER_FQDN first."
    echo ""
    echo "To obtain certificates, run:"
    echo "  systemctl stop httpd"
    echo "  certbot certonly --standalone -d $SERVER_FQDN -m <your-email> --agree-tos"
    echo "  systemctl start httpd"
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
    echo "Ensure Apache (httpd) is installed and configured."
    exit 1
fi

# Backup the original config
echo "Backing up $APACHE_SSL_CONF -> ${APACHE_SSL_CONF}${BACKUP_SUFFIX}"
cp -a "$APACHE_SSL_CONF" "${APACHE_SSL_CONF}${BACKUP_SUFFIX}"

# Patch the SSL certificate paths using sed
# Replace default self-signed cert paths with Let's Encrypt paths
echo "Patching $APACHE_SSL_CONF to use Let's Encrypt certificates..."

# Common default certificate paths in RHEL/AlmaLinux/Rocky
# - SSLCertificateFile /etc/pki/tls/certs/localhost.crt
# - SSLCertificateKeyFile /etc/pki/tls/private/localhost.key
# - Or perfSONAR-specific paths like /etc/pki/tls/certs/perfsonar-*.pem

sed -i.tmp \
    -e "s|^\s*SSLCertificateFile\s\+.*|SSLCertificateFile ${FULLCHAIN}|g" \
    -e "s|^\s*SSLCertificateKeyFile\s\+.*|SSLCertificateKeyFile ${PRIVKEY}|g" \
    "$APACHE_SSL_CONF"

# Add or update SSLCertificateChainFile if present
if grep -q "^\s*SSLCertificateChainFile" "$APACHE_SSL_CONF"; then
    # Update existing SSLCertificateChainFile line
    sed -i.tmp2 \
        -e "s|^\s*SSLCertificateChainFile\s\+.*|SSLCertificateChainFile ${CHAIN}|g" \
        "$APACHE_SSL_CONF"
    rm -f "${APACHE_SSL_CONF}.tmp2"
else
    # Add SSLCertificateChainFile after SSLCertificateKeyFile line if not present
    # Note: In modern Apache with fullchain.pem, this is optional but doesn't hurt
    sed -i.tmp2 \
        -e "/^SSLCertificateKeyFile.*${PRIVKEY//\//\\/}/a\\
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
echo "  1. Verify Apache configuration syntax:"
echo "       apachectl configtest"
echo ""
echo "  2. Reload Apache to apply changes:"
echo "       systemctl reload httpd"
echo ""
echo "  3. Verify HTTPS is serving the Let's Encrypt certificate:"
echo "       curl -vI https://${SERVER_FQDN}/ 2>&1 | grep -i 'subject:'"
echo "       echo | openssl s_client -connect ${SERVER_FQDN}:443 -servername ${SERVER_FQDN} 2>/dev/null | openssl x509 -noout -issuer -dates"
echo ""
