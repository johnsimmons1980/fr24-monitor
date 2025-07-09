#!/bin/bash

# Script to remove test reboot events from the FR24 monitoring database
# This cleans up any test events added for dashboard testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="$SCRIPT_DIR/fr24_monitor.db"

echo "🧹 Removing Test Events from FR24 Monitor Database"
echo "================================================="

# Check if database exists
if [[ ! -f "$DB_FILE" ]]; then
    echo "❌ Database not found: $DB_FILE"
    echo "Please run the FR24 monitor first to create the database"
    exit 1
fi

# Check if there are any test events
TEST_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM reboot_events WHERE dry_run = 1 OR reason LIKE '%TEST EVENT%';" 2>/dev/null)

if [[ $? -ne 0 ]]; then
    echo "❌ Failed to query database"
    exit 1
fi

echo "🔍 Found $TEST_COUNT test event(s) to remove"

if [[ $TEST_COUNT -eq 0 ]]; then
    echo "✅ No test events found - database is already clean"
    exit 0
fi

echo ""
echo "📋 Test events to be removed:"
sqlite3 -header -column "$DB_FILE" "SELECT timestamp, tracked_aircraft, threshold, reason FROM reboot_events WHERE dry_run = 1 OR reason LIKE '%TEST EVENT%' ORDER BY timestamp DESC;"

echo ""
read -p "❓ Are you sure you want to remove these $TEST_COUNT test event(s)? (y/N): " confirm

if [[ $confirm =~ ^[Yy]$ ]]; then
    # Remove test events
    sqlite3 "$DB_FILE" "DELETE FROM reboot_events WHERE dry_run = 1 OR reason LIKE '%TEST EVENT%';"
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Test events removed successfully!"
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
        echo "🌐 Refresh your web dashboard to see the updated statistics!"
        echo "   Dashboard URL: http://$(hostname -I | awk '{print $1}'):6869"
    else
        echo "❌ Failed to remove test events from database"
        exit 1
    fi
else
    echo "❌ Operation cancelled - no test events were removed"
fi
