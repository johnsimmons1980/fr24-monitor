#!/bin/bash

# Test script to trigger a reboot alert email
# This simulates what happens when the monitor detects a failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/fr24_monitor.sh"

# Override some functions to prevent actual reboot
perform_reboot() {
    echo "TEST MODE: Would normally reboot system here"
    echo "Email alert should have been sent above"
    return 0
}

# Set up test scenario
AIRCRAFT_THRESHOLD=5
DRY_RUN=true  # This prevents actual reboot

echo "=== Testing FR24 Monitor Email Alert System ==="
echo "This will simulate a reboot condition and send an alert email"
echo ""

# Simulate a failure condition
tracked_aircraft=0
echo "Simulating failure: tracked_aircraft=$tracked_aircraft, threshold=$AIRCRAFT_THRESHOLD"

# Create the conditions that would trigger a reboot
ENDPOINT_URL="http://test.example.com:8080"
uptime_hours=5

# Call the reboot logic (this should send an email)
echo "Triggering reboot alert logic..."

# Create email message
email_subject="FR24 Monitor Alert: System Reboot Required (TEST)"
email_message=$(cat << EOF
FR24 Monitor System Alert - TEST MODE

A system reboot would normally be triggered due to the following condition:
- Aircraft tracked: $tracked_aircraft
- Threshold: $AIRCRAFT_THRESHOLD  
- Uptime: $uptime_hours hours
- Endpoint: $ENDPOINT_URL

System Information:
- Hostname: $(hostname)
- Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')
- User: $(whoami)

Reason: Test alert - tracked aircraft ($tracked_aircraft) below threshold ($AIRCRAFT_THRESHOLD)

This is a TEST email to verify the alert system is working correctly.
No actual reboot was performed.

---
Sent by FR24 Monitor Alert System
EOF
)

# Send the email alert
if send_email_alert "$email_subject" "$email_message"; then
    echo ""
    echo "✅ SUCCESS: Test email alert sent successfully!"
    echo "Check your inbox at: $(jq -r '.to_email' email_config.json)"
else
    echo ""
    echo "❌ FAILED: Could not send test email alert"
    echo "Check the logs above for details"
fi

echo ""
echo "=== Test Complete ==="
