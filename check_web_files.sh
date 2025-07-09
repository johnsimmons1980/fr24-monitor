#!/bin/bash

# Script to verify and update the web dashboard files
echo "🔍 Checking Web Dashboard File Versions"
echo "======================================="

# Check if files exist
echo "1. Checking file existence..."
for file in "web/index.php" "web/style.css" "web/logs.php"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
    fi
done

echo ""

# Check for the 6-card layout in index.php
echo "2. Checking for 6-card layout..."
CARD_COUNT=$(grep -c "stat-card" web/index.php 2>/dev/null || echo "0")
echo "📊 Found $CARD_COUNT stat-card entries"

if grep -q "Reboots This Month" web/index.php 2>/dev/null; then
    echo "✅ 'Reboots This Month' card found"
else
    echo "❌ 'Reboots This Month' card missing"
fi

if grep -q "Reboots This Year" web/index.php 2>/dev/null; then
    echo "✅ 'Reboots This Year' card found"
else
    echo "❌ 'Reboots This Year' card missing"
fi

echo ""

# Check for reason-cell class
echo "3. Checking for table fix..."
if grep -q "reason-cell" web/index.php 2>/dev/null; then
    echo "✅ Reason cell class found in PHP"
else
    echo "❌ Reason cell class missing in PHP"
fi

if grep -q "reason-cell" web/style.css 2>/dev/null; then
    echo "✅ Reason cell styling found in CSS"
else
    echo "❌ Reason cell styling missing in CSS"
fi

echo ""

# Check for timezone fixes
echo "4. Checking timezone configuration..."
if grep -q "date_default_timezone_set" web/index.php 2>/dev/null; then
    echo "✅ Timezone configuration found"
else
    echo "❌ Timezone configuration missing"
fi

echo ""

# Check PHP variable definitions
echo "5. Checking PHP variables..."
if grep -q "rebootsThisMonth" web/index.php 2>/dev/null; then
    echo "✅ Monthly reboot variable found"
else
    echo "❌ Monthly reboot variable missing"
fi

if grep -q "rebootsThisYear" web/index.php 2>/dev/null; then
    echo "✅ Yearly reboot variable found"
else
    echo "❌ Yearly reboot variable missing"
fi

echo ""
echo "💡 Recommendations:"
echo "If any items are missing, you need to copy the updated files from the development system."
echo "Files to copy: web/index.php, web/style.css, web/logs.php"
echo ""
echo "🔄 After copying files, restart the web server:"
echo "   ./fr24_manager.sh restart-web"
