#!/bin/bash

set -e

echo "Ubuntu Compatibility Patch Script for tacplusNG"
echo "================================================"
echo

# Check for required tools
check_tool() {
    local tool=$1
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: $tool is not installed"
        echo "Please install $tool and run this script again"
        exit 1
    else
        echo "✓ $tool is installed"
    fi
}

echo "Checking for required tools..."
check_tool sed
check_tool find
check_tool grep
echo

# Apply patch to tac_plus-ng/headers.h
echo "Applying patch to tac_plus-ng/headers.h..."
HEADERS_FILE="tac_plus-ng/headers.h"

if [ ! -f "$HEADERS_FILE" ]; then
    echo "ERROR: $HEADERS_FILE not found"
    echo "Please run this script from the tacplusNG root directory"
    exit 1
fi

# Comment out the OpenSSL warning
if grep -q "^#warning Disabling OpenSSL support" "$HEADERS_FILE"; then
    sed -i.bak 's/^#warning Disabling OpenSSL support/\/\/#warning Disabling OpenSSL support/' "$HEADERS_FILE"
    echo "✓ Commented out OpenSSL warning in $HEADERS_FILE"
    echo "  Backup saved as ${HEADERS_FILE}.bak"
else
    if grep -q "^//#warning Disabling OpenSSL support" "$HEADERS_FILE"; then
        echo "✓ OpenSSL warning already commented out in $HEADERS_FILE"
    else
        echo "⚠ OpenSSL warning not found in $HEADERS_FILE (might be already patched or removed)"
    fi
fi
echo

# Apply patch to mavis/ldapmavis-mt.c
echo "Applying patch to mavis/ldapmavis-mt.c..."
LDAP_FILE="mavis/ldapmavis-mt.c"

if [ ! -f "$LDAP_FILE" ]; then
    echo "ERROR: $LDAP_FILE not found"
    echo "Please run this script from the tacplusNG root directory"
    exit 1
fi

# Comment out TLS1.3 lines
if grep -q "^[[:space:]]*else if (!strcmp(tmp, \"TLS1_3\"))" "$LDAP_FILE"; then
    # Create a temporary file with the patches applied
    cp "$LDAP_FILE" "${LDAP_FILE}.tmp"
    
    # Comment out the TLS1_3 strcmp line
    sed -i 's/^\([[:space:]]*\)else if (!strcmp(tmp, "TLS1_3"))/\1\/\/      else if (!strcmp(tmp, "TLS1_3"))/' "${LDAP_FILE}.tmp"
    
    # Comment out the ldap_tls_protocol_min line
    sed -i 's/^\([[:space:]]*\)ldap_tls_protocol_min = LDAP_OPT_X_TLS_PROTOCOL_TLS1_3;/\1\/\/          ldap_tls_protocol_min = LDAP_OPT_X_TLS_PROTOCOL_TLS1_3;/' "${LDAP_FILE}.tmp"
    
    # Check if changes were made
    if ! diff -q "$LDAP_FILE" "${LDAP_FILE}.tmp" > /dev/null; then
        mv "$LDAP_FILE" "${LDAP_FILE}.bak"
        mv "${LDAP_FILE}.tmp" "$LDAP_FILE"
        echo "✓ Commented out TLS1.3 lines in $LDAP_FILE"
        echo "  Backup saved as ${LDAP_FILE}.bak"
    else
        rm "${LDAP_FILE}.tmp"
        echo "⚠ No changes needed in $LDAP_FILE (might be already patched)"
    fi
else
    if grep -q "^[[:space:]]*\/\/.*else if (!strcmp(tmp, \"TLS1_3\"))" "$LDAP_FILE"; then
        echo "✓ TLS1.3 lines already commented out in $LDAP_FILE"
    else
        echo "⚠ TLS1.3 lines not found in $LDAP_FILE (might be already patched or removed)"
    fi
fi
echo

echo "================================================"
echo "Patch application complete!"
echo
echo "Summary:"
echo "- Backup files created with .bak extension"
echo "- You can now proceed with building tacplusNG"
echo
echo "To restore original files, run:"
echo "  mv ${HEADERS_FILE}.bak ${HEADERS_FILE}"
echo "  mv ${LDAP_FILE}.bak ${LDAP_FILE}"