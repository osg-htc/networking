#!/usr/bin/env bash
set -euo pipefail

# Test helpers for perfSONAR script validation functions
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Source the script (functions are defined; main execution is deferred)
# shellcheck source=../perfSONAR-pbr-nm.sh
source "$DIR/perfSONAR-pbr-nm.sh"

fail() { echo "[FAIL] $*"; exit 1; }
pass() { echo "[PASS] $*"; }

# is_ipv4 tests
is_ipv4 "192.0.2.1" || fail "is_ipv4 should accept 192.0.2.1"
! is_ipv4 "999.0.0.1" || fail "is_ipv4 should reject 999.0.0.1"
pass "is_ipv4 checks"

# is_ipv6 tests (basic)
is_ipv6 "::1" || fail "is_ipv6 should accept ::1"
is_ipv6 "2001:db8::1" || fail "is_ipv6 should accept 2001:db8::1"
! is_ipv6 "not-an-ip" || fail "is_ipv6 should reject non-IPs"
pass "is_ipv6 checks"

# validate_prefix
validate_prefix "/24" 32 || fail "validate_prefix /24 <=32 should pass"
validate_prefix "/64" 128 || fail "validate_prefix /64 <=128 should pass"
! validate_prefix "/129" 128 || fail "validate_prefix /129 >128 should fail"
pass "validate_prefix checks"

# is_ip wrapper
is_ip "-" || fail "is_ip should treat '-' as OK"
is_ip "192.0.2.2" || fail "is_ip should accept IPv4"
is_ip "2001:db8::2" || fail "is_ip should accept IPv6"
pass "is_ip checks"

echo "All validation tests passed."
