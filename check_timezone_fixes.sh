#!/bin/bash

# Check if timezone fixes are present in web files

echo "🕐 Checking timezone fixes in web files..."
echo "==========================================="
echo

# Check index.php for timezone fixes
echo "📄 Checking index.php..."

if grep -q "formatDbTimestamp" web/index.php; then
    echo "✅ formatDbTimestamp function found"
else
    echo "❌ formatDbTimestamp function missing"
fi

if grep -q "formatDbTimestamp(\$latestMonitoring\['timestamp'\])" web/index.php; then
    echo "✅ Last Check uses formatDbTimestamp (timezone-aware)"
else
    echo "❌ Last Check still uses old date() function"
fi

if grep -q "formatDbTimestamp(\$lastReboot\['timestamp'\])" web/index.php; then
    echo "✅ Last Reboot uses formatDbTimestamp (timezone-aware)"
else
    echo "❌ Last Reboot still uses old date() function"
fi

if grep -q "formatDbTimestamp(\$reboot\['timestamp'\])" web/index.php; then
    echo "✅ Recent Reboot table uses formatDbTimestamp (timezone-aware)"
else
    echo "❌ Recent Reboot table still uses old date() function"
fi

echo

# Check logs.php for timezone fixes
echo "📄 Checking logs.php..."

if grep -q "formatDbTimestamp" web/logs.php; then
    echo "✅ formatDbTimestamp function found"
else
    echo "❌ formatDbTimestamp function missing"
fi

if grep -q "formatDbTimestamp(\$log\['timestamp'\])" web/logs.php; then
    echo "✅ Log timestamps use formatDbTimestamp (timezone-aware)"
else
    echo "❌ Log timestamps still use old date() function"
fi

echo

# Count old vs new timestamp functions
echo "📊 Timestamp function usage analysis..."
old_count=$(grep -ch "date.*strtotime" web/*.php 2>/dev/null | awk '{sum += $1} END {print sum+0}')
new_count=$(grep -ch "formatDbTimestamp" web/*.php 2>/dev/null | awk '{sum += $1} END {print sum+0}')

echo "Old date(strtotime()) usage: $old_count"
echo "New formatDbTimestamp() usage: $new_count"

echo

if [[ $old_count -eq 0 ]] && [[ $new_count -gt 0 ]]; then
    echo "🎉 All timestamp functions updated! Times should now display in BST/local timezone."
elif [[ $old_count -gt 0 ]]; then
    echo "⚠️  Some old timestamp functions remain. Times may still show in UTC/GMT."
else
    echo "❓ No timestamp functions found."
fi

echo
echo "📋 To copy updated files to Raspberry Pi:"
echo "scp web/*.php pi@your-pi-ip:/path/to/fr24-mon/web/"
