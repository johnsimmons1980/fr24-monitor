#!/bin/bash

# Diagnostic script for web server connection issues
echo "🔍 FR24 Web Server Diagnostic"
echo "=============================="

# Check if the process is actually running
echo "1. Checking if lighttpd process is running..."
if ps aux | grep -q "[l]ighttpd.*fr24"; then
    echo "✅ Lighttpd process found:"
    ps aux | grep "[l]ighttpd.*fr24"
else
    echo "❌ No lighttpd process found running"
fi

echo ""

# Check PID file
echo "2. Checking PID file..."
if [[ -f "lighttpd.pid" ]]; then
    PID=$(cat lighttpd.pid)
    echo "📄 PID file exists with PID: $PID"
    
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "✅ Process $PID is running"
    else
        echo "❌ Process $PID is NOT running (stale PID file)"
    fi
else
    echo "❌ No PID file found"
fi

echo ""

# Check port binding
echo "3. Checking port 6869..."
if netstat -tlnp 2>/dev/null | grep -q ":6869 "; then
    echo "✅ Port 6869 is in use:"
    netstat -tlnp 2>/dev/null | grep ":6869 "
else
    echo "❌ Port 6869 is NOT in use"
fi

echo ""

# Check error log
echo "4. Checking error log..."
if [[ -f "lighttpd_error.log" ]]; then
    echo "📄 Error log exists. Recent entries:"
    tail -10 lighttpd_error.log
else
    echo "❌ No error log found"
fi

echo ""

# Check if php-cgi is available
echo "5. Checking PHP CGI availability..."
if command -v php-cgi >/dev/null 2>&1; then
    echo "✅ php-cgi found: $(which php-cgi)"
    echo "   Version: $(php-cgi -v | head -1)"
else
    echo "❌ php-cgi NOT found"
    echo "   Available PHP binaries:"
    ls -la /usr/bin/php* 2>/dev/null || echo "   No PHP binaries found in /usr/bin/"
fi

echo ""

# Check lighttpd configuration syntax
echo "6. Testing lighttpd configuration..."
if [[ -f "lighttpd.conf" ]]; then
    echo "📄 Configuration file exists"
    if lighttpd -tt -f lighttpd.conf 2>/dev/null; then
        echo "✅ Configuration syntax is valid"
    else
        echo "❌ Configuration has errors:"
        lighttpd -tt -f lighttpd.conf 2>&1
    fi
else
    echo "❌ No configuration file found"
fi

echo ""

# Check web directory
echo "7. Checking web directory..."
if [[ -d "web" ]]; then
    echo "✅ Web directory exists:"
    ls -la web/
else
    echo "❌ Web directory missing"
fi

echo ""
echo "🔧 Suggested fixes:"
echo "1. If php-cgi is missing: sudo apt-get install php-cgi"
echo "2. If config has errors: Check the lighttpd.conf file"
echo "3. If process died: Check lighttpd_error.log for details"
echo "4. Try manual start: lighttpd -D -f lighttpd.conf"
