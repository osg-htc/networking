#!/bin/bash
# Version: 1.0.0
# Author: Shank McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# testpoint-entrypoint-wrapper.sh
# Version: 1.0.0
# Author: Shawn McKee, University of Michigan
# Acknowledgements: Supported by IRIS-HEP and OSG-LHC
# --------------------------------
# Purpose:
#   Wrapper entrypoint for the perfsonar-testpoint container that automatically
#   patches Apache SSL configuration to use Let's Encrypt certificates on startup.
#
# Usage:
#   Use this script as the entrypoint in your docker-compose.yml or podman run command.
#   The SERVER_FQDN environment variable is optional - if not set, the script will
#   auto-discover certificates in /etc/letsencrypt/live.
#
# Example in docker-compose.yml:
#   services:
#     testpoint:
#       entrypoint: ["/opt/perfsonar-tp/tools_scripts/testpoint-entrypoint-wrapper.sh"]
#       environment:
#         - SERVER_FQDN=psum05.aglt2.org  # Optional: auto-discovers if not set
#       volumes:
#         - /opt/perfsonar-tp/tools_scripts:/opt/perfsonar-tp/tools_scripts:ro
#
# Notes:
#   - SERVER_FQDN is optional; script auto-discovers first cert in /etc/letsencrypt/live
#   - Patches Apache config if Let's Encrypt certs are found
#   - Falls back to default certificates if certs don't exist (allows first-time deployment)
#   - After patching, delegates to the container's original entrypoint (systemd)
#
# Author: OSG perfSONAR deployment tools
# Version: 1.1.0

set -e

APACHE_SSL_CONF="/etc/apache2/sites-available/default-ssl.conf"

# Auto-discover Let's Encrypt certificate directory or use SERVER_FQDN if set
if [[ -n "${SERVER_FQDN:-}" ]]; then
    # Explicit FQDN provided
    CERT_DIR="/etc/letsencrypt/live/${SERVER_FQDN}"
    echo "==> Using SERVER_FQDN: ${SERVER_FQDN}"
elif [[ -d "/etc/letsencrypt/live" ]]; then
    # Auto-discover: find the first non-README directory in /etc/letsencrypt/live
    DISCOVERED=$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d ! -name 'README' | head -n1)
    if [[ -n "$DISCOVERED" ]]; then
        CERT_DIR="$DISCOVERED"
        DISCOVERED_FQDN=$(basename "$CERT_DIR")
        echo "==> Auto-discovered certificate directory: ${DISCOVERED_FQDN}"
        SERVER_FQDN="$DISCOVERED_FQDN"
    else
        echo "==> No Let's Encrypt certificates found in /etc/letsencrypt/live"
        CERT_DIR=""
    fi
else
    echo "==> /etc/letsencrypt/live does not exist. Skipping SSL certificate patch."
    CERT_DIR=""
fi

# Only proceed if we have a certificate directory
if [[ -n "$CERT_DIR" ]]; then
    FULLCHAIN="${CERT_DIR}/fullchain.pem"
    PRIVKEY="${CERT_DIR}/privkey.pem"
    CHAIN="${CERT_DIR}/chain.pem"

    # Check if Let's Encrypt certificates exist
    if [[ -f "$FULLCHAIN" ]] && [[ -f "$PRIVKEY" ]]; then
        echo "==> Let's Encrypt certificates found for ${SERVER_FQDN}"
        echo "==> Patching Apache SSL configuration..."

        # Check if Apache config exists
        if [[ -f "$APACHE_SSL_CONF" ]]; then
            # Create a backup on first run (check if .patched marker exists)
            if [[ ! -f "${APACHE_SSL_CONF}.patched" ]]; then
                echo "==> Creating backup: ${APACHE_SSL_CONF}.original"
                cp -a "$APACHE_SSL_CONF" "${APACHE_SSL_CONF}.original"
            fi

            # Patch the SSL certificate paths
            sed -i \
                -e "s|SSLCertificateFile\s\+/etc/ssl/certs/ssl-cert-snakeoil.pem|SSLCertificateFile      ${FULLCHAIN}|g" \
                -e "s|SSLCertificateKeyFile\s\+/etc/ssl/private/ssl-cert-snakeoil.key|SSLCertificateKeyFile ${PRIVKEY}|g" \
                "$APACHE_SSL_CONF"

            # Add or update SSLCertificateChainFile
            if grep -q "^\s*SSLCertificateChainFile" "$APACHE_SSL_CONF"; then
                # Update existing SSLCertificateChainFile line
                sed -i \
                    -e "s|SSLCertificateChainFile\s\+.*|SSLCertificateChainFile ${CHAIN}|g" \
                    "$APACHE_SSL_CONF"
            else
                # Add SSLCertificateChainFile after SSLCertificateKeyFile line
                # Use awk to insert the line to avoid sed escaping issues
                awk -v chain="$CHAIN" '/SSLCertificateKeyFile/ {print; print "                SSLCertificateChainFile " chain; next}1' \
                    "$APACHE_SSL_CONF" > "${APACHE_SSL_CONF}.tmp" && \
                    mv "${APACHE_SSL_CONF}.tmp" "$APACHE_SSL_CONF"
            fi

            # Create marker file to indicate patching was done
            touch "${APACHE_SSL_CONF}.patched"

            echo "==> ✓ Apache SSL configuration patched successfully"
            echo "    SSLCertificateFile      ${FULLCHAIN}"
            echo "    SSLCertificateKeyFile   ${PRIVKEY}"
            echo "    SSLCertificateChainFile ${CHAIN}"
        else
            echo "WARNING: Apache SSL config not found at ${APACHE_SSL_CONF}"
            echo "Skipping SSL certificate patch. Config may be generated later."
        fi
    else
        echo "==> Let's Encrypt certificates not found for ${SERVER_FQDN}"
        echo "    Expected: ${FULLCHAIN}"
        echo "    Skipping SSL certificate patch (will use default certificates)"
        echo "    Obtain certificates and restart the container to enable Let's Encrypt."
    fi
fi

echo "==> Starting perfSONAR testpoint container..."

# Delegate to the original entrypoint
# Common perfSONAR testpoint entrypoints:
# - /sbin/init or /usr/sbin/init (systemd - default for production image)
# - /usr/bin/supervisord (if using supervisord)
# - Custom entrypoint script

# Try to detect and use the original entrypoint
# Default to systemd as it's used in the production image
if [[ -x /sbin/init ]]; then
    exec /sbin/init
elif [[ -x /usr/sbin/init ]]; then
    exec /usr/sbin/init
elif [[ -x /usr/bin/supervisord ]]; then
    exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
else
    # Fallback: if no known entrypoint, just keep container running
    # (useful for debugging; replace with actual entrypoint if known)
    echo "WARNING: No known entrypoint found. Keeping container alive with sleep."
    exec tail -f /dev/null
fi
