#!/usr/bin/env bash
# =============================================================================
# FORTRESS Zone Segmentation Verification Script
# =============================================================================
# Runs 7 connectivity tests to verify that network zone isolation is correctly
# enforced. Uses docker exec to run ping/curl from within each zone container.
#
# Zone Architecture:
#   DMZ   (10.10.1.0/24) - Container: fortress-nginx
#   App   (10.10.2.0/24) - Container: fortress-flask
#   Data  (10.10.3.0/24) - Container: fortress-postgres
#   Admin (10.10.4.0/24) - Container: fortress-admin
#
# Expected Connectivity:
#   DMZ   -> App: ALLOW    DMZ   -> Data: DENY    DMZ   -> Admin: DENY
#   App   -> Data: ALLOW   App   -> Admin: DENY
#   Data  -> DMZ: DENY
#   Admin -> All: ALLOW
#
# Usage:
#   ./verify_segmentation.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Container and IP configuration
# ---------------------------------------------------------------------------
readonly DMZ_CONTAINER="fortress-nginx"
readonly APP_CONTAINER="fortress-flask"
readonly DATA_CONTAINER="fortress-postgres"
readonly ADMIN_CONTAINER="fortress-admin"

# Representative IPs within each zone subnet
readonly DMZ_IP="10.10.1.10"
readonly APP_IP="10.10.2.10"
readonly DATA_IP="10.10.3.10"
readonly ADMIN_IP="10.10.4.10"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=7

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Prints a colored result line
print_result() {
    local test_num="$1"
    local description="$2"
    local result="$3"  # PASS or FAIL

    if [[ "$result" == "PASS" ]]; then
        echo -e "  Test ${test_num}: \033[32mPASS\033[0m - ${description}"
        ((PASS_COUNT++))
    else
        echo -e "  Test ${test_num}: \033[31mFAIL\033[0m - ${description}"
        ((FAIL_COUNT++))
    fi
}

# Test that a connection SUCCEEDS from one container to a target IP.
# Uses ping with a short timeout. Falls back to curl if ping is unavailable.
test_can_reach() {
    local container="$1"
    local target_ip="$2"

    # Try ping first (3 packets, 2-second timeout)
    if docker exec "$container" ping -c 1 -W 2 "$target_ip" &>/dev/null; then
        return 0
    fi

    # Fall back to curl if ping is not available in the container
    if docker exec "$container" curl -s --connect-timeout 2 "http://${target_ip}" &>/dev/null; then
        return 0
    fi

    return 1
}

# Test that a connection is BLOCKED from one container to a target IP.
# Returns 0 (success) if the connection is indeed blocked.
test_cannot_reach() {
    local container="$1"
    local target_ip="$2"

    # If ping or curl succeeds, the connection is NOT blocked -> test fails
    if docker exec "$container" ping -c 1 -W 2 "$target_ip" &>/dev/null; then
        return 1
    fi

    if docker exec "$container" curl -s --connect-timeout 2 "http://${target_ip}" &>/dev/null; then
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Pre-flight: ensure all containers are running
# ---------------------------------------------------------------------------
preflight_check() {
    local missing=false
    for container in "$DMZ_CONTAINER" "$APP_CONTAINER" "$DATA_CONTAINER" "$ADMIN_CONTAINER"; do
        if ! docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null | grep -q "true"; then
            echo "[ERROR] Container '$container' is not running."
            missing=true
        fi
    done
    if $missing; then
        echo "[ERROR] One or more required containers are not running. Aborting."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Test Suite
# ---------------------------------------------------------------------------
run_tests() {
    echo "=============================================="
    echo " FORTRESS Zone Segmentation Verification"
    echo "=============================================="
    echo ""

    # -----------------------------------------------------------------------
    # Test 1: DMZ -> App (SHOULD SUCCEED)
    # The DMZ zone (nginx) must be able to forward traffic to the App zone.
    # -----------------------------------------------------------------------
    if test_can_reach "$DMZ_CONTAINER" "$APP_IP"; then
        print_result 1 "DMZ can reach App zone" "PASS"
    else
        print_result 1 "DMZ can reach App zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 2: DMZ -> Data (SHOULD FAIL)
    # The DMZ zone must NOT have direct access to the Data zone.
    # -----------------------------------------------------------------------
    if test_cannot_reach "$DMZ_CONTAINER" "$DATA_IP"; then
        print_result 2 "DMZ cannot reach Data zone" "PASS"
    else
        print_result 2 "DMZ cannot reach Data zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 3: DMZ -> Admin (SHOULD FAIL)
    # The DMZ zone must NOT have access to the Admin zone.
    # -----------------------------------------------------------------------
    if test_cannot_reach "$DMZ_CONTAINER" "$ADMIN_IP"; then
        print_result 3 "DMZ cannot reach Admin zone" "PASS"
    else
        print_result 3 "DMZ cannot reach Admin zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 4: App -> Data (SHOULD SUCCEED)
    # The App zone (flask) must be able to reach the Data zone (postgres).
    # -----------------------------------------------------------------------
    if test_can_reach "$APP_CONTAINER" "$DATA_IP"; then
        print_result 4 "App can reach Data zone" "PASS"
    else
        print_result 4 "App can reach Data zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 5: App -> Admin (SHOULD FAIL)
    # The App zone must NOT have access to the Admin zone.
    # -----------------------------------------------------------------------
    if test_cannot_reach "$APP_CONTAINER" "$ADMIN_IP"; then
        print_result 5 "App cannot reach Admin zone" "PASS"
    else
        print_result 5 "App cannot reach Admin zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 6: Data -> DMZ (SHOULD FAIL)
    # The Data zone must NOT initiate connections to the DMZ.
    # -----------------------------------------------------------------------
    if test_cannot_reach "$DATA_CONTAINER" "$DMZ_IP"; then
        print_result 6 "Data cannot reach DMZ zone" "PASS"
    else
        print_result 6 "Data cannot reach DMZ zone" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Test 7: Admin -> All zones (SHOULD SUCCEED)
    # The Admin zone must be able to reach every other zone.
    # -----------------------------------------------------------------------
    local admin_ok=true
    if ! test_can_reach "$ADMIN_CONTAINER" "$DMZ_IP"; then
        admin_ok=false
    fi
    if ! test_can_reach "$ADMIN_CONTAINER" "$APP_IP"; then
        admin_ok=false
    fi
    if ! test_can_reach "$ADMIN_CONTAINER" "$DATA_IP"; then
        admin_ok=false
    fi

    if $admin_ok; then
        print_result 7 "Admin can reach all zones" "PASS"
    else
        print_result 7 "Admin can reach all zones" "FAIL"
    fi

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    echo ""
    echo "=============================================="
    echo " Results: ${PASS_COUNT}/${TOTAL_TESTS} PASSED, ${FAIL_COUNT}/${TOTAL_TESTS} FAILED"
    echo "=============================================="

    # Exit with non-zero status if any test failed
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
preflight_check
run_tests
