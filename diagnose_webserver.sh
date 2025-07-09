#!/bin/bash

# Diagnostic script for web server connection issues
echo "🔍 FR24 Web Server Diagnostic"
echo "=============================="

# Check system time and timezone
echo "0. System Time & Timezone..."
echo "📅 Current system time: $(date)"
echo "🌍 Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'Unknown')"
echo "🕐 UTC time: $(date -u)"

echo ""

# Check if the process is actually running
echo "1. Checking if lighttpd process is running..."
if ps aux | grep -q "[l]ighttpd.*lighttpd.conf"; then
    echo "✅ Lighttpd process found:"
    ps aux | grep "[l]ighttpd.*lighttpd.conf"
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

# Check PHP FastCGI socket
echo "8. Checking PHP FastCGI socket..."
CURRENT_USER=$(whoami)
SOCKET_PATH="/tmp/php.socket.$CURRENT_USER"

# Show what socket path the config expects
EXPECTED_SOCKET=$(grep -o '"/tmp/php\.socket\.[^"]*"' lighttpd.conf 2>/dev/null | tr -d '"')
if [[ -n "$EXPECTED_SOCKET" ]]; then
    echo "📋 Config expects socket: $EXPECTED_SOCKET"
    if [[ -S "$EXPECTED_SOCKET" ]]; then
        echo "✅ Expected PHP socket exists: $EXPECTED_SOCKET"
    else
        echo "❌ Expected PHP socket missing: $EXPECTED_SOCKET"
    fi
else
    echo "⚠️  Could not find socket path in config"
fi

# Show all existing PHP sockets
echo "📁 All PHP sockets in /tmp:"
ls -la /tmp/php.socket.* 2>/dev/null || echo "   No PHP sockets found"

# Check if php-cgi processes are running
echo "🔍 PHP-CGI processes:"
ps aux | grep -v grep | grep php-cgi || echo "   No php-cgi processes found"

echo ""

# Test if web dashboard is actually accessible
echo "9. Testing web dashboard access..."
if command -v curl >/dev/null 2>&1; then
    echo "🌐 Testing HTTP access to dashboard..."
    if curl -s -f "http://localhost:6869" >/dev/null 2>&1; then
        echo "✅ Dashboard is accessible via HTTP"
        
        # Test if PHP is working
        if curl -s "http://localhost:6869" | grep -q "FR24 Monitor Dashboard" 2>/dev/null; then
            echo "✅ PHP is working - dashboard content loaded"
        else
            echo "⚠️  HTTP works but PHP may not be processing correctly"
        fi
    else
        echo "❌ Cannot access dashboard via HTTP"
    fi
else
    echo "⚠️  curl not available for testing"
fi

echo ""

# Check PHP timezone configuration
echo "10. Checking PHP timezone configuration..."
if command -v php >/dev/null 2>&1; then
    echo "🕐 System timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'Unknown')"
    echo "🕐 System time zone abbreviation: $(date +%Z)"
    echo "🕐 PHP default timezone: $(php -r 'echo date_default_timezone_get();')"
    echo "🕐 PHP current time: $(php -r 'echo date("d/m/Y H:i:s T");')"
else
    echo "⚠️  PHP CLI not available for testing"
fi

echo ""
echo "🔧 Suggested fixes:"
echo "1. If php-cgi is missing: sudo apt-get install php-cgi"
echo "2. If config has errors: Check the lighttpd.conf file"
echo "3. If process died: Check lighttpd_error.log for details"
echo "4. If socket path is wrong: Regenerate config with correct username"
echo "5. Try manual start: lighttpd -D -f lighttpd.conf"
