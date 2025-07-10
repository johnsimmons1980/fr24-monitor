#!/bin/bash

# Simple wrapper script for systemd to start lighttpd directly
# This avoids the complexity of the manager script for systemd
# PORTABLE: Uses dynamic path detection - works regardless of install location

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIGHTTPD_CONFIG="$SCRIPT_DIR/lighttpd.conf"

# Start lighttpd in foreground for systemd
exec lighttpd -f "$LIGHTTPD_CONFIG" -D
