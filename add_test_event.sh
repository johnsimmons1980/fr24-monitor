#!/bin/bash

# Script to add a test reboot event to the FR24 monitoring database
# This is useful for testing the web dashboard display

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="$SCRIPT_DIR/fr24_monitor.db"

echo "🧪 Adding Test Reboot Event to FR24 Monitor Database"
echo "=================================================="

# Check if database exists
if [[ ! -f "$DB_FILE" ]]; then
    echo "❌ Database not found: $DB_FILE"
    echo "Please run the FR24 monitor first to create the database"
    exit 1
fi

# Get current timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Test event details
TRACKED_AIRCRAFT=5
THRESHOLD=10
REASON="TEST EVENT: Simulated low aircraft count for dashboard testing"
DRY_RUN=1  # Mark as test
UPTIME_HOURS=24.5
ENDPOINT="test-endpoint"

echo "📊 Test Event Details:"
echo "   Timestamp: $TIMESTAMP"
echo "   Tracked Aircraft: $TRACKED_AIRCRAFT"
echo "   Threshold: $THRESHOLD" 
echo "   Reason: $REASON"
echo "   Type: Test Event (dry run)"
echo "   Uptime Hours: $UPTIME_HOURS"
echo ""

# Insert test event into database
sqlite3 "$DB_FILE" "INSERT INTO reboot_events (timestamp, tracked_aircraft, threshold, reason, dry_run, uptime_hours, endpoint) VALUES ('$TIMESTAMP', $TRACKED_AIRCRAFT, $THRESHOLD, '$REASON', $DRY_RUN, $UPTIME_HOURS, '$ENDPOINT');"

if [[ $? -eq 0 ]]; then
    echo "✅ Test reboot event added successfully!"
    echo ""
    echo "📈 Updated Statistics:"
    
    # Show current stats
    TOTAL_REBOOTS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM reboot_events;")
    REBOOTS_TODAY=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM reboot_events WHERE DATE(timestamp) = DATE('now');")
    REBOOTS_THIS_MONTH=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y-%m', timestamp) = strftime('%Y-%m', 'now');")
    REBOOTS_THIS_YEAR=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y', timestamp) = strftime('%Y', 'now');")
    
    echo "   Total Reboots: $TOTAL_REBOOTS"
    echo "   Reboots Today: $REBOOTS_TODAY"
    echo "   Reboots This Month: $REBOOTS_THIS_MONTH"
    echo "   Reboots This Year: $REBOOTS_THIS_YEAR"
    echo ""
    echo "🌐 Refresh your web dashboard to see the test event!"
    echo "   Dashboard URL: http://$(hostname -I | awk '{print $1}'):6869"
    echo ""
    echo "💡 Use ./remove_test_event.sh to remove this test event"
else
    echo "❌ Failed to add test event to database"
    exit 1
fi
