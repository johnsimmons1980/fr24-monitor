#!/bin/bash

# Script to check logs.php issues
echo "🔍 Checking logs.php Issues"
echo "=========================="

echo "1. Testing if logs.php file exists and is readable..."
if [[ -f "web/logs.php" ]]; then
    echo "✅ logs.php exists"
    echo "📄 File size: $(stat -c%s web/logs.php 2>/dev/null || echo 'unknown') bytes"
    echo "🔐 Permissions: $(ls -la web/logs.php | awk '{print $1,$3,$4}')"
else
    echo "❌ logs.php file not found"
fi

echo ""
echo "2. Testing PHP syntax..."
if command -v php >/dev/null 2>&1; then
    if php -l web/logs.php >/dev/null 2>&1; then
        echo "✅ PHP syntax is valid"
    else
        echo "❌ PHP syntax errors:"
        php -l web/logs.php
    fi
else
    echo "⚠️ PHP CLI not available for testing"
fi

echo ""
echo "3. Testing web access to logs.php..."
if command -v curl >/dev/null 2>&1; then
    echo "🌐 Testing HTTP access to logs.php..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:6869/logs.php" 2>/dev/null)
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo "✅ logs.php returns HTTP 200"
        
        # Test if content loads
        CONTENT=$(curl -s "http://localhost:6869/logs.php" 2>/dev/null)
        if [[ -n "$CONTENT" ]]; then
            echo "✅ Content loaded successfully"
            echo "📊 Content length: ${#CONTENT} characters"
            
            # Check for common error patterns
            if echo "$CONTENT" | grep -q "Fatal error\|Parse error\|Warning\|Notice"; then
                echo "⚠️ PHP errors detected in output:"
                echo "$CONTENT" | grep -E "Fatal error|Parse error|Warning|Notice" | head -5
            fi
        else
            echo "❌ No content received"
        fi
    else
        echo "❌ HTTP error code: $HTTP_CODE"
        
        # Get some response content for debugging
        RESPONSE=$(curl -s "http://localhost:6869/logs.php" 2>/dev/null)
        if [[ -n "$RESPONSE" ]]; then
            echo "📄 Error response preview:"
            echo "$RESPONSE" | head -10
        fi
    fi
else
    echo "⚠️ curl not available for testing"
fi

echo ""
echo "4. Checking required files..."
for file in "../fr24_monitor.log" "../fr24_monitor.db"; do
    if [[ -f "$file" ]]; then
        echo "✅ $file exists"
    else
        echo "⚠️ $file missing (this is okay if no monitoring data exists yet)"
    fi
done

echo ""
echo "5. Checking lighttpd error log for logs.php errors..."
if [[ -f "lighttpd_error.log" ]]; then
    echo "📄 Recent lighttpd errors mentioning logs.php:"
    grep -i "logs.php\|logs\.php" lighttpd_error.log | tail -5 || echo "   No logs.php errors found"
else
    echo "⚠️ No lighttpd error log found"
fi

echo ""
echo "💡 Troubleshooting:"
echo "If logs.php won't load, try:"
echo "1. Check browser developer tools for JavaScript errors"
echo "2. Try accessing directly: http://[your-ip]:6869/logs.php"
echo "3. Check lighttpd_error.log for detailed error messages"
echo "4. Restart web server: ./fr24_manager.sh restart-web"
