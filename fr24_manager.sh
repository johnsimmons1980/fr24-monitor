#!/bin/bash

# FR24 Monitor Management Script with Web Dashboard
# Usage: ./fr24_manager.sh [install|uninstall|status|edit|test|preview|help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_FILE="$SCRIPT_DIR/fr24_monitor.cron"
MONITOR_SCRIPT="$SCRIPT_DIR/fr24_monitor.sh"
LOGROTATE_FILE="$SCRIPT_DIR/fr24_logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/fr24_monitor"

# Web dashboard configuration
WEB_DIR="$SCRIPT_DIR/web"
DATABASE_FILE="$SCRIPT_DIR/fr24_monitor.db"
LIGHTTPD_CONFIG="$SCRIPT_DIR/lighttpd.conf"
WEB_PORT=6869

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local level="$1"
    local message="$2"
    case "$level" in
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
    esac
}

# Function to get the log file path from the monitor script
get_log_file_path() {
    # Extract the LOG_FILE value from the monitor script
    local log_line=$(grep "^LOG_FILE=" "$MONITOR_SCRIPT" | head -1)
    
    # Check if it uses $SCRIPT_DIR variable
    if [[ "$log_line" == *'$SCRIPT_DIR'* ]]; then
        # Extract the filename part and combine with our script directory
        local filename=$(echo "$log_line" | sed 's/.*\$SCRIPT_DIR\///; s/".*$//')
        echo "$SCRIPT_DIR/$filename"
    else
        # Extract the full path (handles quoted paths)
        local log_path=$(echo "$log_line" | cut -d'"' -f2)
        
        # If we can't find it or it's empty, fall back to script directory
        if [[ -z "$log_path" ]]; then
            log_path="$SCRIPT_DIR/fr24_monitor.log"
        fi
        
        echo "$log_path"
    fi
}

# Function to check if script exists and is executable
check_script() {
    if [[ ! -f "$MONITOR_SCRIPT" ]]; then
        print_status "ERROR" "Monitor script not found: $MONITOR_SCRIPT"
        return 1
    fi
    
    if [[ ! -x "$MONITOR_SCRIPT" ]]; then
        print_status "WARN" "Monitor script is not executable, making it executable..."
        chmod +x "$MONITOR_SCRIPT"
        print_status "SUCCESS" "Made script executable"
    fi
    
    return 0
}

# Function to install crontab
install_cron() {
    print_status "INFO" "Installing FR24 monitor crontab..."
    
    if ! check_script; then
        return 1
    fi
    
    if [[ ! -f "$CRON_FILE" ]]; then
        print_status "ERROR" "Cron file not found: $CRON_FILE"
        return 1
    fi
    
    # Backup existing crontab
    if crontab -l >/dev/null 2>&1; then
        print_status "INFO" "Backing up existing crontab to crontab.backup"
        crontab -l > "$SCRIPT_DIR/crontab.backup"
    fi
    
    # Check if FR24 monitor is already in crontab
    if crontab -l 2>/dev/null | grep -q "fr24_monitor.sh"; then
        print_status "WARN" "FR24 monitor appears to already be in crontab"
        print_status "INFO" "Current FR24 entries:"
        crontab -l 2>/dev/null | grep "fr24_monitor.sh"
        
        read -p "Do you want to replace the existing entries? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "INFO" "Installation cancelled"
            return 0
        fi
        
        # Remove existing FR24 entries
        crontab -l 2>/dev/null | grep -v "fr24_monitor.sh" | crontab -
        print_status "INFO" "Removed existing FR24 monitor entries"
    fi
    
    # Create a temporary cron file with updated paths
    local temp_cron=$(mktemp)
    local log_file=$(get_log_file_path)
    
    # Process the cron file and replace placeholders with actual paths
    sed "s|__MONITOR_SCRIPT_PATH__|$MONITOR_SCRIPT|g; s|__LOG_FILE_PATH__|$log_file|g" "$CRON_FILE" > "$temp_cron"
    
    # Add new cron entries with updated paths
    (crontab -l 2>/dev/null; grep -v "^#" "$temp_cron" | grep -v "^$") | crontab -
    
    # Clean up temporary file
    rm -f "$temp_cron"
    
    if [[ $? -eq 0 ]]; then
        local log_file=$(get_log_file_path)
        print_status "SUCCESS" "FR24 monitor crontab installed successfully"
        print_status "INFO" "The monitor will run every 10 minutes"
        print_status "INFO" "Check logs at: $log_file"
        
        # Create the log file if it doesn't exist
        if [[ ! -f "$log_file" ]]; then
            touch "$log_file"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] FR24 monitoring system installed" >> "$log_file"
            print_status "INFO" "Created log file: $log_file"
        fi
        
        # Also install logrotate configuration
        print_status "INFO" "Installing logrotate configuration..."
        if install_logrotate; then
            print_status "SUCCESS" "Complete installation finished successfully"
        else
            print_status "WARN" "Cron installed but logrotate installation failed"
        fi
        
        # Run the monitor script once to populate the log immediately
        print_status "INFO" "Running monitor script once to populate log file..."
        if bash "$MONITOR_SCRIPT" --dry-run >/dev/null 2>&1; then
            print_status "SUCCESS" "Monitor script executed successfully - log file populated"
            print_status "INFO" "You can check the initial log entry with: tail -f $log_file"
        else
            print_status "WARN" "Monitor script execution failed, but installation is complete"
            print_status "INFO" "The monitor will start working on its next scheduled run"
        fi
    else
        print_status "ERROR" "Failed to install crontab"
        return 1
    fi
}

# Function to uninstall crontab
uninstall_cron() {
    print_status "INFO" "Uninstalling FR24 monitor from crontab..."
    
    if ! crontab -l >/dev/null 2>&1; then
        print_status "WARN" "No crontab found for current user"
        return 0
    fi
    
    if ! crontab -l 2>/dev/null | grep -q "fr24_monitor.sh"; then
        print_status "WARN" "FR24 monitor not found in current crontab"
        return 0
    fi
    
    # Remove FR24 entries
    crontab -l 2>/dev/null | grep -v "fr24_monitor.sh" | crontab -
    
    if [[ $? -eq 0 ]]; then
        print_status "SUCCESS" "FR24 monitor removed from crontab"
        
        # Also remove logrotate configuration
        print_status "INFO" "Removing logrotate configuration..."
        if uninstall_logrotate; then
            print_status "SUCCESS" "Complete uninstallation finished successfully"
        else
            print_status "WARN" "Cron removed but logrotate removal failed"
        fi
    else
        print_status "ERROR" "Failed to remove FR24 monitor from crontab"
        return 1
    fi
}

# Function to show crontab status
show_status() {
    print_status "INFO" "FR24 Monitor Crontab Status"
    echo "================================"
    
    if ! crontab -l >/dev/null 2>&1; then
        print_status "WARN" "No crontab found for current user"
        return 0
    fi
    
    local fr24_entries=$(crontab -l 2>/dev/null | grep "fr24_monitor.sh" | wc -l)
    
    if [[ $fr24_entries -eq 0 ]]; then
        print_status "WARN" "FR24 monitor not found in crontab"
    else
        print_status "SUCCESS" "Found $fr24_entries FR24 monitor entries in crontab:"
        crontab -l 2>/dev/null | grep "fr24_monitor.sh"
    fi
    
    echo
    print_status "INFO" "Current cron service status:"
    if systemctl is-active --quiet cron; then
        print_status "SUCCESS" "Cron service is running"
    else
        print_status "ERROR" "Cron service is not running"
        print_status "INFO" "Start with: sudo systemctl start cron"
    fi
    
    echo
    local log_file_path=$(get_log_file_path)
    print_status "INFO" "Log file location: $log_file_path"
    if [[ -f "$log_file_path" ]]; then
        local log_size=$(du -h "$log_file_path" | cut -f1)
        print_status "INFO" "Log file size: $log_size"
        print_status "INFO" "Last 3 entries:"
        tail -3 "$log_file_path" 2>/dev/null || echo "  (Log file is empty or unreadable)"
    else
        print_status "WARN" "Log file does not exist yet"
    fi
    
    echo
    print_status "INFO" "Logrotate configuration status:"
    if [[ -f "$LOGROTATE_DEST" ]]; then
        print_status "SUCCESS" "Logrotate configuration installed at: $LOGROTATE_DEST"
        if sudo logrotate -d "$LOGROTATE_DEST" >/dev/null 2>&1; then
            print_status "SUCCESS" "Logrotate configuration is valid"
        else
            print_status "WARN" "Logrotate configuration has issues"
        fi
    else
        print_status "WARN" "Logrotate configuration not installed"
    fi
    
    echo
    print_status "INFO" "Database status:"
    if [[ -f "$DATABASE_FILE" ]]; then
        local db_size=$(du -h "$DATABASE_FILE" | cut -f1)
        print_status "SUCCESS" "Database file exists: $DATABASE_FILE ($db_size)"
        
        # Get database statistics
        if command -v sqlite3 >/dev/null 2>&1; then
            local reboot_count=$(sqlite3 "$DATABASE_FILE" "SELECT COUNT(*) FROM reboot_events;" 2>/dev/null || echo "0")
            local monitoring_count=$(sqlite3 "$DATABASE_FILE" "SELECT COUNT(*) FROM monitoring_stats;" 2>/dev/null || echo "0")
            print_status "INFO" "Reboot events logged: $reboot_count"
            print_status "INFO" "Monitoring records: $monitoring_count"
        fi
    else
        print_status "WARN" "Database file not found: $DATABASE_FILE"
    fi
    
    echo
    print_status "INFO" "Web dashboard status:"
    local pid_file="$SCRIPT_DIR/lighttpd.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "SUCCESS" "Web server running (PID: $pid)"
            print_status "INFO" "Dashboard URL: http://localhost:$WEB_PORT"
            
            # Test if the web server is responsive
            if curl -s --connect-timeout 2 "http://localhost:$WEB_PORT" >/dev/null 2>&1; then
                print_status "SUCCESS" "Dashboard is accessible"
            else
                print_status "WARN" "Dashboard may not be responding"
            fi
        else
            print_status "WARN" "Web server PID file exists but process is not running"
            rm -f "$pid_file"
        fi
    else
        print_status "WARN" "Web server not running"
        print_status "INFO" "Start with: ./fr24_manager.sh start-web"
    fi
}

# Function to edit crontab
edit_cron() {
    print_status "INFO" "Opening crontab for editing..."
    crontab -e
}

# Function to preview the cron entries that would be installed
preview_cron() {
    print_status "INFO" "Previewing cron entries that would be installed..."
    
    if ! check_script; then
        return 1
    fi
    
    if [[ ! -f "$CRON_FILE" ]]; then
        print_status "ERROR" "Cron file not found: $CRON_FILE"
        return 1
    fi
    
    local log_file=$(get_log_file_path)
    
    echo "================================"
    echo "Cron entries that would be added:"
    echo "================================"
    
    # Show the processed cron entries
    sed "s|__MONITOR_SCRIPT_PATH__|$MONITOR_SCRIPT|g; s|__LOG_FILE_PATH__|$log_file|g" "$CRON_FILE" | grep -v "^#" | grep -v "^$"
    
    echo "================================"
    print_status "INFO" "Monitor script: $MONITOR_SCRIPT"
    print_status "INFO" "Log file: $log_file"
    
    echo
    echo "================================"
    echo "Logrotate configuration that would be installed:"
    echo "================================"
    
    if [[ -f "$LOGROTATE_FILE" ]]; then
        # Show the processed logrotate configuration
        sed "s|__LOG_FILE_PATH__|$log_file|g" "$LOGROTATE_FILE"
        echo "================================"
        print_status "INFO" "Logrotate destination: $LOGROTATE_DEST"
    else
        print_status "WARN" "Logrotate file not found: $LOGROTATE_FILE"
    fi
}

# Function to test the monitor script
test_monitor() {
    print_status "INFO" "Testing FR24 monitor script..."
    
    if ! check_script; then
        return 1
    fi
    
    print_status "INFO" "Running monitor in dry-run mode..."
    "$MONITOR_SCRIPT" --dry-run --verbose
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        print_status "SUCCESS" "Monitor script test completed successfully"
    else
        print_status "ERROR" "Monitor script test failed with exit code: $exit_code"
    fi
}

# Function to install logrotate configuration
install_logrotate() {
    if [[ ! -f "$LOGROTATE_FILE" ]]; then
        print_status "WARN" "Logrotate file not found: $LOGROTATE_FILE"
        return 1
    fi
    
    # Check if we can write to /etc/logrotate.d/
    if [[ ! -w "/etc/logrotate.d/" ]]; then
        print_status "WARN" "Cannot write to /etc/logrotate.d/ - need sudo privileges"
        print_status "INFO" "Attempting to install logrotate config with sudo..."
    fi
    
    local log_file=$(get_log_file_path)
    local temp_logrotate=$(mktemp)
    
    # Process the logrotate file and replace placeholders
    sed "s|__LOG_FILE_PATH__|$log_file|g" "$LOGROTATE_FILE" > "$temp_logrotate"
    
    # Install the logrotate configuration
    if sudo cp "$temp_logrotate" "$LOGROTATE_DEST"; then
        print_status "SUCCESS" "Logrotate configuration installed to $LOGROTATE_DEST"
        
        # Test the logrotate configuration
        if sudo logrotate -d "$LOGROTATE_DEST" >/dev/null 2>&1; then
            print_status "SUCCESS" "Logrotate configuration is valid"
        else
            print_status "WARN" "Logrotate configuration may have issues - check with: sudo logrotate -d $LOGROTATE_DEST"
        fi
    else
        print_status "ERROR" "Failed to install logrotate configuration"
        rm -f "$temp_logrotate"
        return 1
    fi
    
    rm -f "$temp_logrotate"
    return 0
}

# Function to uninstall logrotate configuration
uninstall_logrotate() {
    if [[ -f "$LOGROTATE_DEST" ]]; then
        if sudo rm -f "$LOGROTATE_DEST"; then
            print_status "SUCCESS" "Removed logrotate configuration: $LOGROTATE_DEST"
        else
            print_status "ERROR" "Failed to remove logrotate configuration: $LOGROTATE_DEST"
            return 1
        fi
    else
        print_status "INFO" "Logrotate configuration not found: $LOGROTATE_DEST"
    fi
    return 0
}

# Function to migrate database schema if needed
migrate_database() {
    if [[ ! -f "$DATABASE_FILE" ]]; then
        return 0  # No database to migrate
    fi
    
    print_status "INFO" "Checking database schema for updates..."
    
    # Check if we need to migrate system_status table (old version had different columns)
    local old_columns
    old_columns=$(sqlite3 "$DATABASE_FILE" "PRAGMA table_info(system_status);" 2>/dev/null | grep -c "system_load\|memory_usage\|disk_usage")
    
    if [[ "$old_columns" -gt 0 ]]; then
        print_status "INFO" "Migrating system_status table to new schema..."
        
        # Backup old table and create new one
        sqlite3 "$DATABASE_FILE" << 'EOF'
-- Rename old table
ALTER TABLE system_status RENAME TO system_status_old;

-- Create new table with simplified schema
CREATE TABLE system_status (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    check_status TEXT,
    tracked_aircraft INTEGER,
    threshold INTEGER,
    uptime_hours INTEGER
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_system_timestamp ON system_status(timestamp);

-- Optionally copy some data from old table (basic info only)
INSERT INTO system_status (timestamp, check_status, tracked_aircraft, threshold, uptime_hours)
SELECT timestamp, 'MIGRATED', 0, 0, uptime_hours 
FROM system_status_old 
ORDER BY timestamp DESC 
LIMIT 10;

-- Drop old table
DROP TABLE system_status_old;
EOF
        
        if [[ $? -eq 0 ]]; then
            print_status "SUCCESS" "Database schema migrated successfully"
        else
            print_status "WARN" "Database migration had issues, but continuing..."
        fi
    else
        print_status "SUCCESS" "Database schema is up to date"
    fi
}

# Function to install database and create schema
install_database() {
    print_status "INFO" "Installing database components..."
    
    # Check if SQLite is available
    if ! command -v sqlite3 &> /dev/null; then
        print_status "INFO" "Installing SQLite3..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y sqlite3
        elif command -v yum &> /dev/null; then
            sudo yum install -y sqlite3
        else
            print_status "ERROR" "Could not install SQLite3. Please install it manually."
            return 1
        fi
    fi
    
    # Migrate existing database if needed
    migrate_database
    
    # Create database and schema
    print_status "INFO" "Creating database schema at: $DATABASE_FILE"
    
    sqlite3 "$DATABASE_FILE" << 'EOF'
CREATE TABLE IF NOT EXISTS reboot_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    tracked_aircraft INTEGER,
    threshold INTEGER,
    uptime_hours INTEGER,
    reason TEXT,
    dry_run BOOLEAN DEFAULT 0,
    service_restart_attempted BOOLEAN DEFAULT 0,
    service_restart_successful BOOLEAN DEFAULT 0,
    endpoint TEXT,
    system_info TEXT
);

CREATE TABLE IF NOT EXISTS monitoring_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    tracked_aircraft INTEGER,
    uploaded_aircraft INTEGER,
    endpoint TEXT,
    response_time_ms INTEGER,
    feed_status TEXT,
    feed_server TEXT
);

CREATE TABLE IF NOT EXISTS system_status (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    check_status TEXT,
    tracked_aircraft INTEGER,
    threshold INTEGER,
    uptime_hours INTEGER
);

CREATE INDEX IF NOT EXISTS idx_reboot_timestamp ON reboot_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_monitoring_timestamp ON monitoring_stats(timestamp);
CREATE INDEX IF NOT EXISTS idx_system_timestamp ON system_status(timestamp);
EOF

    if [[ $? -eq 0 ]]; then
        print_status "SUCCESS" "Database schema created successfully"
        
        # Set proper permissions
        chmod 664 "$DATABASE_FILE"
        
        return 0
    else
        print_status "ERROR" "Failed to create database schema"
        return 1
    fi
}

# Function to install web server and PHP
install_webserver() {
    print_status "INFO" "Installing web server components..."
    
    # Install lighttpd and PHP
    if command -v apt-get &> /dev/null; then
        print_status "INFO" "Installing lighttpd and PHP via apt-get..."
        sudo apt-get update
        sudo apt-get install -y lighttpd php-cli php-fpm php-sqlite3
    elif command -v yum &> /dev/null; then
        print_status "INFO" "Installing lighttpd and PHP via yum..."
        sudo yum install -y lighttpd php php-pdo
    else
        print_status "ERROR" "Could not install web server. Please install lighttpd and PHP manually."
        return 1
    fi
    
    # Create web directory
    mkdir -p "$WEB_DIR"
    
    # Create lighttpd configuration
    print_status "INFO" "Creating lighttpd configuration..."
    
    cat > "$LIGHTTPD_CONFIG" << EOF
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_compress",
    "mod_redirect",
    "mod_fastcgi",
)

server.document-root        = "$WEB_DIR"
server.errorlog             = "$SCRIPT_DIR/lighttpd_error.log"
server.pid-file             = "$SCRIPT_DIR/lighttpd.pid"
server.username             = "$(whoami)"
server.groupname            = "$(whoami)"
server.port                 = $WEB_PORT

index-file.names            = ( "index.php", "index.html" )
url.access-deny             = ( "~", ".inc" )
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )

# Basic MIME types
mimetype.assign = (
    ".html" => "text/html",
    ".htm"  => "text/html",
    ".css"  => "text/css",
    ".js"   => "application/x-javascript",
    ".php"  => "application/x-httpd-php",
    ".png"  => "image/png",
    ".jpg"  => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif"  => "image/gif",
    ".ico"  => "image/x-icon",
    ".txt"  => "text/plain"
)

    # Detect available PHP method and create appropriate configuration
    local php_config=""
    
    if command -v php-cgi >/dev/null 2>&1; then
        print_status "INFO" "Using PHP-CGI for FastCGI"
        php_config='
# PHP FastCGI configuration using CGI
fastcgi.server = ( ".php" => ((
    "bin-path" => "/usr/bin/php-cgi",
    "socket" => "/tmp/php.socket.fr24",
    "max-procs" => 2,
    "idle-timeout" => 20,
    "bin-environment" => (
        "PHP_FCGI_CHILDREN" => "4",
        "PHP_FCGI_MAX_REQUESTS" => "10000"
    ),
    "bin-copy-environment" => (
        "PATH", "SHELL", "USER"
    )
)))'
    elif [[ -S "/run/php/php8.2-fpm.sock" ]] || [[ -S "/run/php/php-fpm.sock" ]]; then
        local php_socket="/run/php/php8.2-fpm.sock"
        if [[ ! -S "$php_socket" ]]; then
            php_socket="/run/php/php-fpm.sock"
        fi
        print_status "INFO" "Using PHP-FPM socket: $php_socket"
        php_config="
# PHP FastCGI configuration using PHP-FPM
fastcgi.server = ( \".php\" => ((
    \"socket\" => \"$php_socket\",
    \"broken-scriptfilename\" => \"enable\"
)))"
    else
        print_status "WARN" "No suitable PHP FastCGI method found"
        print_status "INFO" "Install php-cgi with: sudo apt-get install php-cgi"
        php_config='
# PHP FastCGI configuration - DISABLED (no php-cgi found)
# Install php-cgi with: sudo apt-get install php-cgi
# fastcgi.server = ( ".php" => (( "disabled" => "true" )))'
    fi

    # Add PHP configuration to the lighttpd config
    echo "$php_config" >> "$LIGHTTPD_CONFIG"

    if [[ $? -eq 0 ]]; then
        print_status "SUCCESS" "Web server configuration created"
        return 0
    else
        print_status "ERROR" "Failed to create web server configuration"
        return 1
    fi
}

# Function to create web dashboard files
create_web_dashboard() {
    print_status "INFO" "Creating web dashboard files..."
    
    # Create CSS file
    cat > "$WEB_DIR/style.css" << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background-color: #f5f5f5;
    color: #333;
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

.header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 2rem;
    border-radius: 10px;
    margin-bottom: 2rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.header h1 {
    font-size: 2.5rem;
    margin-bottom: 0.5rem;
}

.header p {
    font-size: 1.1rem;
    opacity: 0.9;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1.5rem;
    margin-bottom: 2rem;
}

.stat-card {
    background: white;
    padding: 1.5rem;
    border-radius: 10px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    border-left: 4px solid #667eea;
}

.stat-card.error {
    border-left-color: #e53e3e;
}

.stat-card.warning {
    border-left-color: #dd6b20;
}

.stat-card.success {
    border-left-color: #38a169;
}

.stat-value {
    font-size: 2rem;
    font-weight: bold;
    color: #2d3748;
}

.stat-label {
    color: #718096;
    font-size: 0.9rem;
    margin-top: 0.5rem;
}

.table-container {
    background: white;
    border-radius: 10px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    overflow: hidden;
    margin-bottom: 2rem;
}

.table-header {
    background: #f7fafc;
    padding: 1rem;
    border-bottom: 1px solid #e2e8f0;
}

.table-header h3 {
    color: #2d3748;
    font-size: 1.2rem;
}

table {
    width: 100%;
    border-collapse: collapse;
}

th, td {
    padding: 0.75rem;
    text-align: left;
    border-bottom: 1px solid #e2e8f0;
}

th {
    background: #f7fafc;
    font-weight: 600;
    color: #4a5568;
}

tr:hover {
    background: #f7fafc;
}

.status-indicator {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    margin-right: 0.5rem;
}

.status-success {
    background: #38a169;
}

.status-error {
    background: #e53e3e;
}

.status-warning {
    background: #dd6b20;
}

.refresh-info {
    text-align: center;
    color: #718096;
    font-size: 0.9rem;
    margin-top: 2rem;
}

.btn {
    display: inline-block;
    padding: 0.5rem 1rem;
    background: #667eea;
    color: white;
    text-decoration: none;
    border-radius: 5px;
    border: none;
    cursor: pointer;
    font-size: 0.9rem;
}

.btn:hover {
    background: #5a67d8;
}

.alert {
    padding: 1rem;
    border-radius: 5px;
    margin-bottom: 1rem;
}

.alert-error {
    background: #fed7d7;
    color: #c53030;
    border: 1px solid #feb2b2;
}

.alert-warning {
    background: #feebc8;
    color: #c05621;
    border: 1px solid #fbd38d;
}

.alert-success {
    background: #c6f6d5;
    color: #2f855a;
    border: 1px solid #9ae6b4;
}
EOF

    # Create main dashboard PHP file
    cat > "$WEB_DIR/index.php" << 'EOF'
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

$dbFile = dirname(__DIR__) . '/fr24_monitor.db';

// Check if database exists
if (!file_exists($dbFile)) {
    die('<div class="alert alert-error">Database not found. Please run the installer first.</div>');
}

try {
    $pdo = new PDO('sqlite:' . $dbFile);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die('<div class="alert alert-error">Database connection failed: ' . htmlspecialchars($e->getMessage()) . '</div>');
}

// Get statistics
$totalReboots = $pdo->query("SELECT COUNT(*) FROM reboot_events")->fetchColumn();
$lastReboot = $pdo->query("SELECT timestamp, reason FROM reboot_events ORDER BY timestamp DESC LIMIT 1")->fetch();
$rebootsToday = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE DATE(timestamp) = DATE('now')")->fetchColumn();
$rebootsThisWeek = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE timestamp >= DATE('now', '-7 days')")->fetchColumn();

// Get latest monitoring data
$latestMonitoring = $pdo->query("
    SELECT tracked_aircraft, uploaded_aircraft, endpoint, timestamp, feed_status, feed_server 
    FROM monitoring_stats 
    ORDER BY timestamp DESC 
    LIMIT 1
")->fetch();

// Get recent reboot events
$recentReboots = $pdo->query("
    SELECT timestamp, tracked_aircraft, threshold, reason, dry_run, uptime_hours, endpoint
    FROM reboot_events 
    ORDER BY timestamp DESC 
    LIMIT 10
")->fetchAll();

// Get system health trend (last 24 hours)
$monitoringTrend = $pdo->query("
    SELECT timestamp, tracked_aircraft, uploaded_aircraft
    FROM monitoring_stats 
    WHERE timestamp >= DATETIME('now', '-24 hours')
    ORDER BY timestamp DESC
    LIMIT 50
")->fetchAll();

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Dashboard</title>
    <link rel="stylesheet" href="style.css">
    <meta http-equiv="refresh" content="60">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛩️ FR24 Monitor Dashboard</h1>
            <p>Real-time monitoring and analytics for FlightRadar24 feeder status</p>
        </div>

        <?php if ($latestMonitoring): ?>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value"><?= $latestMonitoring['tracked_aircraft'] ?? 'N/A' ?></div>
                    <div class="stat-label">Aircraft Currently Tracked</div>
                </div>
                
                <div class="stat-card">
                    <div class="stat-value"><?= $totalReboots ?></div>
                    <div class="stat-label">Total System Reboots</div>
                </div>
                
                <div class="stat-card <?= $rebootsToday > 0 ? 'warning' : 'success' ?>">
                    <div class="stat-value"><?= $rebootsToday ?></div>
                    <div class="stat-label">Reboots Today</div>
                </div>
                
                <div class="stat-card">
                    <div class="stat-value"><?= $rebootsThisWeek ?></div>
                    <div class="stat-label">Reboots This Week</div>
                </div>
            </div>
        <?php endif; ?>

        <?php if ($latestMonitoring): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>📊 Current System Status</h3>
                </div>
                <table>
                    <tr>
                        <td><strong>Last Check:</strong></td>
                        <td><?= date('d/m/Y H:i:s', strtotime($latestMonitoring['timestamp'])) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Aircraft Tracked:</strong></td>
                        <td>
                            <span class="status-indicator <?= $latestMonitoring['tracked_aircraft'] > 0 ? 'status-success' : 'status-error' ?>"></span>
                            <?= $latestMonitoring['tracked_aircraft'] ?>
                        </td>
                    </tr>
                    <tr>
                        <td><strong>Aircraft Uploaded:</strong></td>
                        <td><?= $latestMonitoring['uploaded_aircraft'] ?? 'N/A' ?></td>
                    </tr>
                    <tr>
                        <td><strong>Feed Status:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['feed_status'] ?? 'Unknown') ?></td>
                    </tr>
                    <tr>
                        <td><strong>Feed Server:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['feed_server'] ?? 'Unknown') ?></td>
                    </tr>
                    <tr>
                        <td><strong>Endpoint:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['endpoint']) ?></td>
                    </tr>
                </table>
            </div>
        <?php endif; ?>

        <?php if ($lastReboot): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>⚠️ Last Reboot Event</h3>
                </div>
                <table>
                    <tr>
                        <td><strong>Time:</strong></td>
                        <td><?= date('d/m/Y H:i:s', strtotime($lastReboot['timestamp'])) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Reason:</strong></td>
                        <td><?= htmlspecialchars($lastReboot['reason']) ?></td>
                    </tr>
                </table>
            </div>
        <?php endif; ?>

        <?php if (!empty($recentReboots)): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>📋 Recent Reboot History</h3>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th>Date/Time</th>
                            <th>Tracked</th>
                            <th>Threshold</th>
                            <th>Uptime (hrs)</th>
                            <th>Type</th>
                            <th>Reason</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($recentReboots as $reboot): ?>
                            <tr>
                                <td><?= date('d/m/Y H:i:s', strtotime($reboot['timestamp'])) ?></td>
                                <td><?= $reboot['tracked_aircraft'] ?></td>
                                <td><?= $reboot['threshold'] ?></td>
                                <td><?= $reboot['uptime_hours'] ?></td>
                                <td>
                                    <?php if ($reboot['dry_run']): ?>
                                        <span class="status-indicator status-warning"></span>Test
                                    <?php else: ?>
                                        <span class="status-indicator status-error"></span>Real
                                    <?php endif; ?>
                                </td>
                                <td><?= htmlspecialchars(substr($reboot['reason'], 0, 60)) ?><?= strlen($reboot['reason']) > 60 ? '...' : '' ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>

        <div class="refresh-info">
            <p>🔄 Page automatically refreshes every 60 seconds | Last updated: <?= date('d/m/Y H:i:s') ?></p>
            <p><a href="logs.php" class="btn">View Detailed Logs</a></p>
        </div>
    </div>
</body>
</html>
EOF

    # Create logs viewer PHP file
    cat > "$WEB_DIR/logs.php" << 'EOF'
<?php
$logFile = dirname(__DIR__) . '/fr24_monitor.log';
$dbFile = dirname(__DIR__) . '/fr24_monitor.db';

// Read log file
$logs = [];
if (file_exists($logFile)) {
    $logs = array_reverse(array_slice(file($logFile, FILE_IGNORE_NEW_LINES), -100));
}

// Get database logs
$dbLogs = [];
if (file_exists($dbFile)) {
    try {
        $pdo = new PDO('sqlite:' . $dbFile);
        $dbLogs = $pdo->query("
            SELECT timestamp, tracked_aircraft, uploaded_aircraft, endpoint, feed_status
            FROM monitoring_stats 
            ORDER BY timestamp DESC 
            LIMIT 50
        ")->fetchAll();
    } catch (PDOException $e) {
        // Ignore database errors in logs view
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Logs</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📄 FR24 Monitor Logs</h1>
            <p><a href="index.php" class="btn">← Back to Dashboard</a></p>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>💾 Database Monitoring History</h3>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Tracked</th>
                        <th>Uploaded</th>
                        <th>Feed Status</th>
                        <th>Endpoint</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($dbLogs as $log): ?>
                        <tr>
                            <td><?= date('d/m/Y H:i:s', strtotime($log['timestamp'])) ?></td>
                            <td><?= $log['tracked_aircraft'] ?></td>
                            <td><?= $log['uploaded_aircraft'] ?? 'N/A' ?></td>
                            <td><?= htmlspecialchars($log['feed_status'] ?? 'Unknown') ?></td>
                            <td><?= htmlspecialchars(parse_url($log['endpoint'], PHP_URL_HOST) . ':' . parse_url($log['endpoint'], PHP_URL_PORT)) ?></td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>📝 File-based Logs (Latest 100 entries)</h3>
            </div>
            <div style="background: #1a202c; color: #e2e8f0; padding: 1rem; font-family: monospace; font-size: 0.9rem; max-height: 500px; overflow-y: auto;">
                <?php foreach ($logs as $log): ?>
                    <div style="margin-bottom: 0.25rem;"><?= htmlspecialchars($log) ?></div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</body>
</html>
EOF

    print_status "SUCCESS" "Web dashboard files created successfully"
    return 0
}

# Function to start web server
start_webserver() {
    print_status "INFO" "Starting web server on port $WEB_PORT..."
    
    # Check if configuration exists
    if [[ ! -f "$LIGHTTPD_CONFIG" ]]; then
        print_status "ERROR" "Web server configuration not found. Run install first."
        return 1
    fi
    
    # Check if web directory exists
    if [[ ! -d "$WEB_DIR" ]]; then
        print_status "ERROR" "Web directory not found. Run install first."
        return 1
    fi
    
    # Check if port is already in use
    if netstat -tlnp 2>/dev/null | grep -q ":$WEB_PORT "; then
        print_status "WARN" "Port $WEB_PORT is already in use"
        
        # Check if it's our lighttpd instance
        local pid_file="$SCRIPT_DIR/lighttpd.pid"
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            if ps -p "$pid" > /dev/null 2>&1; then
                print_status "INFO" "Web server already running (PID: $pid)"
                print_status "SUCCESS" "Dashboard available at: http://localhost:$WEB_PORT"
                return 0
            else
                # Remove stale PID file
                rm -f "$pid_file"
            fi
        fi
    fi
    
    # Start lighttpd in background
    if lighttpd -f "$LIGHTTPD_CONFIG" 2>/dev/null & then
        local pid=$!
        echo "$pid" > "$SCRIPT_DIR/lighttpd.pid"
        
        # Wait a moment and check if it started successfully
        sleep 3
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "SUCCESS" "Web server started successfully (PID: $pid)"
            print_status "INFO" "Dashboard available at: http://localhost:$WEB_PORT"
            return 0
        else
            print_status "ERROR" "Web server failed to start"
            if [[ -f "$SCRIPT_DIR/lighttpd_error.log" ]]; then
                print_status "ERROR" "Check error log: $SCRIPT_DIR/lighttpd_error.log"
            fi
            return 1
        fi
    else
        print_status "ERROR" "Failed to start web server"
        return 1
    fi
}

# Function to stop web server
stop_webserver() {
    local pid_file="$SCRIPT_DIR/lighttpd.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "INFO" "Stopping web server (PID: $pid)..."
            kill "$pid"
            rm -f "$pid_file"
            print_status "SUCCESS" "Web server stopped"
        else
            print_status "INFO" "Web server not running"
            rm -f "$pid_file"
        fi
    else
        print_status "INFO" "Web server PID file not found"
    fi
}

# Function to uninstall web components
uninstall_web_components() {
    print_status "INFO" "Removing web dashboard components..."
    
    # Stop web server
    stop_webserver
    
    # Remove web files
    if [[ -d "$WEB_DIR" ]]; then
        rm -rf "$WEB_DIR"
        print_status "INFO" "Removed web directory"
    fi
    
    # Remove configuration files
    rm -f "$LIGHTTPD_CONFIG"
    rm -f "$SCRIPT_DIR/lighttpd_error.log"
    
    # Ask about database
    read -p "Do you want to remove the database file? This will delete all monitoring history. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$DATABASE_FILE"
        print_status "INFO" "Database file removed"
    fi
    
    print_status "SUCCESS" "Web components uninstalled"
}

# Main function
main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            install_cron
            install_logrotate
            install_database
            install_webserver
            create_web_dashboard
            start_webserver
            ;;
        "uninstall")
            uninstall_cron
            uninstall_logrotate
            uninstall_web_components
            ;;
        "status")
            show_status
            ;;
        "edit")
            edit_cron
            ;;
        "test")
            test_monitor
            ;;
        "preview")
            preview_cron
            ;;
        "start-web")
            start_webserver
            ;;
        "stop-web")
            stop_webserver
            ;;
        "help"|*)
            local log_file=$(get_log_file_path)
            cat << EOF
FR24 Monitor Management Tool with Web Dashboard

Usage: $0 [command]

DESCRIPTION:
    Complete management tool for the FR24 monitoring system with web dashboard.
    Handles installation, configuration, testing, monitoring, database logging,
    and web dashboard for all components.

COMMANDS:
    install     Install FR24 monitor with cron, logrotate, database, and web dashboard
    uninstall   Remove FR24 monitor and all components (cron, logrotate, web, database)
    status      Show current system status, cron jobs, logs, and web server status
    edit        Edit crontab manually
    test        Test the monitor script in dry-run mode
    preview     Show the cron and logrotate entries that would be installed
    start-web   Start the web dashboard server
    stop-web    Stop the web dashboard server
    test        Test the monitor script in dry-run mode
    preview     Show the cron and logrotate entries that would be installed
    help        Show this help message

EXAMPLES:
    $0 preview      # Preview what will be installed
    $0 install      # Install complete monitoring system with web dashboard
    $0 status       # Check if monitoring is running
    $0 test         # Test the monitoring script safely
    $0 start-web    # Start the web dashboard server
    $0 stop-web     # Stop the web dashboard server
    $0 uninstall    # Remove complete monitoring system

FILES:
    Monitor script: $MONITOR_SCRIPT
    Cron template:  $CRON_FILE
    Logrotate template: $LOGROTATE_FILE
    Log file:       $log_file

INSTALLATION LOCATIONS:
    Cron entries: User's crontab
    Logrotate config: $LOGROTATE_DEST
    Web directory: $WEB_DIR
    Database file: $DATABASE_FILE

WEB DASHBOARD:
    URL: http://localhost:$WEB_PORT
    Features:
    - Real-time aircraft tracking statistics
    - Reboot event history and analytics
    - System performance monitoring
    - Detailed logs viewer
    - Automatic refresh every 60 seconds
    
    The dashboard provides a comprehensive view of your FR24 monitoring system
    including current status, historical events, and system health metrics.

EOF
            ;;
    esac
}

# Execute main function
main "$@"
