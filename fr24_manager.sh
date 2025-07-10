#!/bin/bash

# FR24 Monitor Management Script with Web Dashboard
# Usage: ./fr24_manager.sh [install|uninstall|status|edit|test|preview|help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config file
if [[ -f "$SCRIPT_DIR/load_config.sh" ]]; then
    source "$SCRIPT_DIR/load_config.sh"
    if load_config; then
        WEB_PORT="${FR24_WEB_PORT:-6869}"
        DEFAULT_ENDPOINT="${FR24_ENDPOINT_URL:-http://localhost:8754/monitor.json}"
    else
        echo "Warning: Could not load configuration file, using defaults"
    fi
else
    echo "Warning: Configuration loader not found, using defaults"
fi

# Default configuration (fallback if config loading fails)
CRON_FILE="$SCRIPT_DIR/fr24_monitor.cron"
MONITOR_SCRIPT="$SCRIPT_DIR/fr24_monitor.sh"
LOGROTATE_FILE="$SCRIPT_DIR/fr24_logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/fr24_monitor"

# Web dashboard configuration
WEB_DIR="$SCRIPT_DIR/web"
DATABASE_FILE="$SCRIPT_DIR/fr24_monitor.db"
LIGHTTPD_CONFIG="$SCRIPT_DIR/lighttpd.conf"
WEB_PORT="${WEB_PORT:-6869}"

# FR24 monitoring configuration
DEFAULT_ENDPOINT="${DEFAULT_ENDPOINT:-http://localhost:8754/monitor.json}"

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
        
        # Check if FR24 feeder is available before running the monitor
        if curl -s --connect-timeout 5 "$DEFAULT_ENDPOINT" >/dev/null 2>&1; then
            if bash "$MONITOR_SCRIPT" >/dev/null 2>&1; then
                print_status "SUCCESS" "Monitor script executed successfully - log file populated"
                print_status "INFO" "You can check the initial log entry with: tail -f $log_file"
            else
                print_status "WARN" "Monitor script execution failed, but installation is complete"
                print_status "INFO" "The monitor will start working on its next scheduled run"
            fi
        else
            print_status "INFO" "FR24 feeder not detected - skipping initial monitor run"
            print_status "INFO" "The monitor will start working when FR24 feeder is available"
            print_status "INFO" "Check status with: tail -f $log_file"
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
        sudo apt-get install -y lighttpd php-cli php-cgi php-sqlite3
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
    
    # Detect available PHP method
    local php_config=""
    local current_user=$(whoami)
    if command -v php-cgi >/dev/null 2>&1; then
        print_status "INFO" "Using PHP-CGI for FastCGI"
        php_config='# PHP FastCGI configuration using CGI
fastcgi.server = ( ".php" => ((
    "bin-path" => "/usr/bin/php-cgi",
    "socket" => "/tmp/php.socket.'$current_user'",
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
        php_config="# PHP FastCGI configuration using PHP-FPM
fastcgi.server = ( \".php\" => ((
    \"socket\" => \"$php_socket\",
    \"broken-scriptfilename\" => \"enable\"
)))"
    else
        print_status "ERROR" "No PHP FastCGI support found. Install php-cgi with: sudo apt-get install php-cgi"
        return 1
    fi

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

$php_config
EOF

    if [[ $? -eq 0 ]]; then
        print_status "SUCCESS" "Web server configuration created"
        return 0
    else
        print_status "ERROR" "Failed to create web server configuration"
        return 1
    fi
}

# Function to create systemd service for auto-starting web server after reboot
install_systemd_service() {
    print_status "INFO" "Installing systemd service for auto-start after reboot..."
    
    local service_name="fr24-monitor-web"
    local service_file="/etc/systemd/system/${service_name}.service"
    local current_user=$(whoami)
    
    # Create the systemd service file
    cat > "/tmp/${service_name}.service" << EOF
[Unit]
Description=FR24 Monitor Web Dashboard
After=network.target

[Service]
Type=simple
User=$current_user
Group=$current_user
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/start_web_service.sh
ExecStop=$SCRIPT_DIR/fr24_manager.sh stop-web
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Copy to systemd directory with sudo
    if sudo cp "/tmp/${service_name}.service" "$service_file" 2>/dev/null; then
        sudo chown root:root "$service_file"
        sudo chmod 644 "$service_file"
        
        # Reload systemd and enable the service
        if sudo systemctl daemon-reload && sudo systemctl enable "$service_name"; then
            print_status "SUCCESS" "Systemd service installed and enabled"
            print_status "INFO" "Web server will auto-start after system reboot"
            print_status "INFO" "Service commands:"
            print_status "INFO" "  Start:   sudo systemctl start $service_name"
            print_status "INFO" "  Stop:    sudo systemctl stop $service_name" 
            print_status "INFO" "  Status:  sudo systemctl status $service_name"
            print_status "INFO" "  Disable: sudo systemctl disable $service_name"
        else
            print_status "WARN" "Failed to enable systemd service"
            return 1
        fi
    else
        print_status "WARN" "Could not install systemd service (no sudo access or systemd not available)"
        print_status "INFO" "Web server will need to be started manually after reboot"
        return 1
    fi
    
    # Clean up temp file
    rm -f "/tmp/${service_name}.service"
    
    return 0
}

# Function to start systemd service
start_systemd_service() {
    print_status "INFO" "Starting systemd service..."
    
    local service_name="fr24-monitor-web"
    
    # Check if systemd service exists
    if ! systemctl list-unit-files | grep -q "$service_name"; then
        print_status "ERROR" "Systemd service not installed. Run install first."
        return 1
    fi
    
    # Stop any manually running web server first
    stop_webserver
    
    # Start the systemd service
    if sudo systemctl start "$service_name"; then
        print_status "SUCCESS" "Systemd service started successfully"
        print_status "SUCCESS" "Dashboard available at: http://localhost:$WEB_PORT"
        print_status "INFO" "Web server will auto-start after system reboot"
        
        # Wait a moment for the service to fully start
        sleep 2
        
        # Run the monitor script once to populate the log immediately
        print_status "INFO" "Running monitor script once to populate log file..."
        local log_file=$(get_log_file_path)
        
        # Check if FR24 feeder is available before running the monitor
        if curl -s --connect-timeout 5 "$DEFAULT_ENDPOINT" >/dev/null 2>&1; then
            if bash "$MONITOR_SCRIPT" >/dev/null 2>&1; then
                print_status "SUCCESS" "Monitor script executed successfully - log file populated"
                print_status "INFO" "You can check the initial log entry with: tail -f $log_file"
            else
                print_status "WARN" "Monitor script execution failed, but installation is complete"
                print_status "INFO" "The monitor will start working on its next scheduled run"
            fi
        else
            print_status "INFO" "FR24 feeder not detected - skipping initial monitor run"
            print_status "INFO" "The monitor will start working when FR24 feeder is available"
            print_status "INFO" "Check status with: tail -f $log_file"
        fi
        
        return 0
    else
        print_status "ERROR" "Failed to start systemd service"
        print_status "INFO" "Check service status: sudo systemctl status $service_name"
        return 1
    fi
}

# Function to start web server manually
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
        
        # Check if there's any lighttpd process using our config
        if ps aux | grep -q "[l]ighttpd.*$SCRIPT_DIR"; then
            print_status "INFO" "Web server already running (detected by process check)"
            print_status "SUCCESS" "Dashboard available at: http://localhost:$WEB_PORT"
            
            # Try to recreate PID file if possible
            local running_pid=$(ps aux | grep "[l]ighttpd.*$SCRIPT_DIR" | awk '{print $2}' | head -1)
            if [[ -n "$running_pid" ]]; then
                echo "$running_pid" > "$SCRIPT_DIR/lighttpd.pid"
                print_status "INFO" "Recreated PID file with PID: $running_pid"
            fi
            return 0
        fi
        
        # Port is in use by something else
        print_status "ERROR" "Port $WEB_PORT is in use by another process"
        print_status "INFO" "Use 'netstat -tlnp | grep :$WEB_PORT' to check what's using the port"
        return 1
    fi
    
    # Start lighttpd in background
    print_status "INFO" "Attempting to start lighttpd..."
    if lighttpd -f "$LIGHTTPD_CONFIG" 2>"$SCRIPT_DIR/lighttpd_error.log" & then
        local pid=$!
        echo "$pid" > "$SCRIPT_DIR/lighttpd.pid"
        
        # Wait a moment for startup
        sleep 2
        
        # Check if it's still running
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "SUCCESS" "Web server started (PID: $pid)"
            print_status "SUCCESS" "Dashboard available at: http://localhost:$WEB_PORT"
            return 0
        else
            print_status "ERROR" "Web server failed to start"
            print_status "INFO" "Check error log: $SCRIPT_DIR/lighttpd_error.log"
            return 1
        fi
    else
        print_status "ERROR" "Failed to start web server"
        print_status "INFO" "Check if lighttpd is installed and configuration is valid"
        return 1
    fi
}

# Function to stop web server manually
stop_webserver() {
    print_status "INFO" "Stopping web server..."
    
    local pid_file="$SCRIPT_DIR/lighttpd.pid"
    local stopped=false
    
    # Try to stop via PID file first
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "INFO" "Stopping web server (PID: $pid)..."
            kill "$pid" 2>/dev/null
            
            # Wait for graceful shutdown
            local count=0
            while ps -p "$pid" > /dev/null 2>&1 && [[ $count -lt 10 ]]; do
                sleep 1
                ((count++))
            done
            
            if ps -p "$pid" > /dev/null 2>&1; then
                print_status "WARN" "Graceful shutdown failed, using SIGKILL..."
                kill -9 "$pid" 2>/dev/null
                sleep 1
            fi
            
            if ! ps -p "$pid" > /dev/null 2>&1; then
                print_status "SUCCESS" "Web server stopped"
                stopped=true
            fi
        fi
        
        # Remove PID file
        rm -f "$pid_file"
    fi
    
    # If PID file method didn't work, try to find and kill any remaining processes
    if ! $stopped; then
        local pids=$(ps aux | grep "[l]ighttpd.*$SCRIPT_DIR" | awk '{print $2}')
        if [[ -n "$pids" ]]; then
            print_status "INFO" "Found running lighttpd processes, stopping them..."
            for pid in $pids; do
                kill "$pid" 2>/dev/null
            done
            sleep 2
            stopped=true
            print_status "SUCCESS" "Web server processes stopped"
        else
            print_status "INFO" "No web server processes found running"
        fi
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

.stat-card.primary {
    border-left-color: #667eea;
}

.stat-card.secondary {
    border-left-color: #9f7aea;
}

.stat-card.info {
    border-left-color: #3182ce;
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

.delete-btn {
    background: none;
    border: none;
    cursor: pointer;
    font-size: 1.2rem;
    padding: 0.25rem;
    border-radius: 3px;
    transition: background-color 0.2s;
    line-height: 1;
}

.delete-btn:hover {
    background: #fed7d7;
}

.delete-btn:active {
    background: #feb2b2;
}
EOF

    # Create main dashboard PHP file
    cat > "$WEB_DIR/index.php" << 'EOF'
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Set timezone to match system timezone
$systemTimezone = trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC"'));
if ($systemTimezone && $systemTimezone !== 'UTC' && $systemTimezone !== '') {
    try {
        date_default_timezone_set($systemTimezone);
    } catch (Exception $e) {
        // Fallback if timezone is invalid
        date_default_timezone_set('Europe/London');
    }
} else {
    // Force Europe/London for UK systems
    date_default_timezone_set('Europe/London');
}

// Function to properly format timestamps from database
function formatDbTimestamp($timestamp) {
    if (empty($timestamp)) return 'N/A';
    
    // Create DateTime object in UTC (SQLite CURRENT_TIMESTAMP is always UTC)
    $dt = new DateTime($timestamp, new DateTimeZone('UTC'));
    // Convert to local timezone
    $dt->setTimezone(new DateTimeZone(date_default_timezone_get()));
    
    return $dt->format('d/m/Y H:i:s');
}

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

// Handle delete requests
if ($_POST && isset($_POST['delete_reboot_id'])) {
    $deleteId = intval($_POST['delete_reboot_id']);
    try {
        $stmt = $pdo->prepare("DELETE FROM reboot_events WHERE id = ?");
        if ($stmt->execute([$deleteId])) {
            $deleteMessage = "Reboot entry deleted successfully.";
            $deleteMessageType = "success";
        } else {
            $deleteMessage = "Failed to delete reboot entry.";
            $deleteMessageType = "error";
        }
    } catch (PDOException $e) {
        $deleteMessage = "Error deleting entry: " . htmlspecialchars($e->getMessage());
        $deleteMessageType = "error";
    }
    
    // Redirect to avoid resubmission on refresh
    header('Location: ' . $_SERVER['PHP_SELF'] . '?deleted=' . ($deleteMessageType === 'success' ? '1' : '0'));
    exit;
}

// Show delete message if redirected
$deleteMessage = '';
$deleteMessageType = '';
if (isset($_GET['deleted'])) {
    if ($_GET['deleted'] === '1') {
        $deleteMessage = "Reboot entry deleted successfully.";
        $deleteMessageType = "success";
    } else {
        $deleteMessage = "Failed to delete reboot entry.";
        $deleteMessageType = "error";
    }
}

// Get statistics
$totalReboots = $pdo->query("SELECT COUNT(*) FROM reboot_events")->fetchColumn();
$lastReboot = $pdo->query("SELECT timestamp, reason FROM reboot_events ORDER BY timestamp DESC LIMIT 1")->fetch();
$rebootsToday = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE DATE(timestamp) = DATE('now')")->fetchColumn();
$rebootsThisWeek = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE timestamp >= DATE('now', '-7 days')")->fetchColumn();
$rebootsThisMonth = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y-%m', timestamp) = strftime('%Y-%m', 'now')")->fetchColumn();
$rebootsThisYear = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y', timestamp) = strftime('%Y', 'now')")->fetchColumn();

// Get latest monitoring data
$latestMonitoring = $pdo->query("
    SELECT tracked_aircraft, uploaded_aircraft, endpoint, timestamp, feed_status, feed_server 
    FROM monitoring_stats 
    ORDER BY timestamp DESC 
    LIMIT 1
")->fetch();

// Get recent reboot events
$recentReboots = $pdo->query("
    SELECT id, timestamp, tracked_aircraft, threshold, reason, dry_run, uptime_hours, endpoint
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

        <?php if ($deleteMessage): ?>
            <div class="alert alert-<?= $deleteMessageType ?>">
                <?= htmlspecialchars($deleteMessage) ?>
            </div>
        <?php endif; ?>

        <?php if ($latestMonitoring): ?>
            <div class="stats-grid">
                <div class="stat-card primary">
                    <div class="stat-value"><?= $latestMonitoring['tracked_aircraft'] ?? 'N/A' ?></div>
                    <div class="stat-label">Aircraft Currently Tracked</div>
                </div>
                
                <div class="stat-card <?= $rebootsToday > 0 ? 'warning' : 'success' ?>">
                    <div class="stat-value"><?= $rebootsToday ?></div>
                    <div class="stat-label">Reboots Today</div>
                </div>
                
                <div class="stat-card info">
                    <div class="stat-value"><?= $rebootsThisWeek ?></div>
                    <div class="stat-label">Reboots This Week</div>
                </div>
                
                <div class="stat-card <?= $rebootsThisMonth > 3 ? 'warning' : 'info' ?>">
                    <div class="stat-value"><?= $rebootsThisMonth ?? '0' ?></div>
                    <div class="stat-label">Reboots This Month</div>
                </div>
                
                <div class="stat-card <?= $rebootsThisYear > 20 ? 'warning' : 'info' ?>">
                    <div class="stat-value"><?= $rebootsThisYear ?? '0' ?></div>
                    <div class="stat-label">Reboots This Year</div>
                </div>
                
                <div class="stat-card secondary">
                    <div class="stat-value"><?= $totalReboots ?></div>
                    <div class="stat-label">Total System Reboots</div>
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
                        <td><?= formatDbTimestamp($latestMonitoring['timestamp']) ?></td>
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
                        <td><?= formatDbTimestamp($lastReboot['timestamp']) ?></td>
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
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($recentReboots as $reboot): ?>
                            <tr>
                                <td><?= formatDbTimestamp($reboot['timestamp']) ?></td>
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
                                <td style="word-wrap: break-word; white-space: normal; max-width: 200px;"><?= htmlspecialchars($reboot['reason']) ?></td>
                                <td>
                                    <form method="POST" style="display: inline-block; margin: 0;" onsubmit="return confirm('Are you sure you want to delete this reboot entry?');">
                                        <input type="hidden" name="delete_reboot_id" value="<?= $reboot['id'] ?>">
                                        <button type="submit" class="delete-btn" title="Delete this entry">
                                            🗑️
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>

        <div class="refresh-info">
            <p>🔄 Page automatically refreshes every 60 seconds | Last updated: <?= date('d/m/Y H:i:s T') ?></p>
            <p>
                <a href="logs.php" class="btn">View Detailed Logs</a>
                <a href="config.php" class="btn" style="background: #9f7aea; margin-left: 0.5rem;">Email Configuration</a>
            </p>
            <p style="font-size: 0.8rem; color: #718096;">PHP Timezone: <?= date_default_timezone_get() ?> | System TZ: <?= $systemTimezone ?? 'Unknown' ?></p>
        </div>
    </div>
</body>
</html>
EOF

    # Create logs viewer PHP file
    cat > "$WEB_DIR/logs.php" << 'EOF'
<?php
// Set timezone to match system timezone
$systemTimezone = trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC"'));
if ($systemTimezone && $systemTimezone !== 'UTC' && $systemTimezone !== '') {
    try {
        date_default_timezone_set($systemTimezone);
    } catch (Exception $e) {
        // Fallback if timezone is invalid
        date_default_timezone_set('Europe/London');
    }
} else {
    date_default_timezone_set('Europe/London');
}

// Function to properly format timestamps from database
function formatDbTimestamp($timestamp) {
    if (empty($timestamp)) return 'N/A';
    
    // Create DateTime object in UTC (SQLite CURRENT_TIMESTAMP is always UTC)
    $dt = new DateTime($timestamp, new DateTimeZone('UTC'));
    // Convert to local timezone
    $dt->setTimezone(new DateTimeZone(date_default_timezone_get()));
    
    return $dt->format('d/m/Y H:i:s');
}

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
            LIMIT 100
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
                <h3>💾 Database Monitoring History (Showing <?= count($dbLogs) ?> entries - scroll for more)</h3>
            </div>
            <div style="max-height: 400px; overflow-y: auto;">
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
                                <td><?= formatDbTimestamp($log['timestamp']) ?></td>
                                <td><?= $log['tracked_aircraft'] ?></td>
                                <td><?= $log['uploaded_aircraft'] ?? 'N/A' ?></td>
                                <td><?= htmlspecialchars($log['feed_status'] ?? 'Unknown') ?></td>
                                <td><?= htmlspecialchars(parse_url($log['endpoint'], PHP_URL_HOST) . ':' . parse_url($log['endpoint'], PHP_URL_PORT)) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
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

    # Create configuration page PHP file
    cat > "$WEB_DIR/config.php" << 'EOF'
<?php
// Set timezone to match system timezone
$systemTimezone = trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC"'));
if ($systemTimezone && $systemTimezone !== 'UTC' && $systemTimezone !== '') {
    try {
        date_default_timezone_set($systemTimezone);
    } catch (Exception $e) {
        date_default_timezone_set('Europe/London');
    }
} else {
    date_default_timezone_set('Europe/London');
}

$configFile = dirname(__DIR__) . '/email_config.json';
$message = '';
$messageType = '';

// Handle form submission
if ($_POST) {
    $config = [
        'enabled' => isset($_POST['enabled']) ? true : false,
        'smtp_host' => $_POST['smtp_host'] ?? '',
        'smtp_port' => intval($_POST['smtp_port'] ?? 587),
        'use_tls' => $_POST['smtp_security'] === 'tls',
        'use_starttls' => $_POST['smtp_security'] === 'tls',
        'smtp_user' => $_POST['smtp_username'] ?? '',
        'smtp_password' => $_POST['smtp_password'] ?? '',
        'from_email' => $_POST['from_email'] ?? '',
        'from_name' => $_POST['from_name'] ?? 'FR24 Monitor',
        'to_email' => $_POST['to_email'] ?? '',
        'subject' => $_POST['subject'] ?? 'FR24 Monitor Alert: System Reboot Required',
        'smtp_security' => $_POST['smtp_security'] ?? 'tls'
    ];
    
    if (file_put_contents($configFile, json_encode($config, JSON_PRETTY_PRINT))) {
        $message = 'Configuration saved successfully!';
        $messageType = 'success';
    } else {
        $message = 'Failed to save configuration. Check file permissions.';
        $messageType = 'error';
    }
}

// Load existing configuration
$config = [];
if (file_exists($configFile)) {
    $configData = file_get_contents($configFile);
    if ($configData) {
        $config = json_decode($configData, true) ?? [];
    }
}

// Default values
$config = array_merge([
    'enabled' => false,
    'smtp_host' => '',
    'smtp_port' => 587,
    'smtp_security' => 'tls',
    'use_tls' => true,
    'use_starttls' => true,
    'smtp_user' => '',
    'smtp_username' => '',
    'smtp_password' => '',
    'from_email' => '',
    'from_name' => 'FR24 Monitor',
    'to_email' => '',
    'subject' => 'FR24 Monitor Alert: System Reboot Required'
], $config);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Configuration</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ FR24 Monitor Configuration</h1>
            <p>Configure email alerts for system reboot notifications</p>
            <p><a href="index.php" class="btn">← Back to Dashboard</a></p>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-<?= $messageType ?>">
                <?= htmlspecialchars($message) ?>
            </div>
        <?php endif; ?>

        <div class="table-container">
            <div class="table-header">
                <h3>📧 Email Alert Configuration</h3>
            </div>
            <form method="POST" style="padding: 2rem;">
                <div style="margin-bottom: 1.5rem;">
                    <label style="display: flex; align-items: center; font-weight: 600; margin-bottom: 0.5rem;">
                        <input type="checkbox" name="enabled" value="1" <?= $config['enabled'] ? 'checked' : '' ?> style="margin-right: 0.5rem;">
                        Enable Email Alerts
                    </label>
                    <small style="color: #718096;">Send email notifications when the system requires a reboot</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Server Host:</label>
                    <input type="text" name="smtp_host" value="<?= htmlspecialchars($config['smtp_host']) ?>" 
                           placeholder="e.g., smtp.gmail.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">SMTP server hostname or IP address</small>
                </div>

                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1.5rem;">
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Port:</label>
                        <input type="number" name="smtp_port" value="<?= $config['smtp_port'] ?>" 
                               placeholder="587" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                        <small style="color: #718096;">Usually 587 for TLS or 465 for SSL</small>
                    </div>
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">Security:</label>
                        <select name="smtp_security" style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                            <option value="tls" <?= $config['smtp_security'] === 'tls' ? 'selected' : '' ?>>TLS</option>
                            <option value="ssl" <?= $config['smtp_security'] === 'ssl' ? 'selected' : '' ?>>SSL</option>
                            <option value="none" <?= $config['smtp_security'] === 'none' ? 'selected' : '' ?>>None</option>
                        </select>
                    </div>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Username:</label>
                    <input type="text" name="smtp_username" value="<?= htmlspecialchars($config['smtp_username']) ?>" 
                           placeholder="your.email@example.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">Usually your email address</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Password:</label>
                    <input type="password" name="smtp_password" value="<?= htmlspecialchars($config['smtp_password']) ?>" 
                           placeholder="Your email password or app password" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">For Gmail, use an App Password instead of your regular password</small>
                </div>

                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1.5rem;">
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">From Email:</label>
                        <input type="email" name="from_email" value="<?= htmlspecialchars($config['from_email']) ?>" 
                               placeholder="monitor@example.com" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    </div>
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">From Name:</label>
                        <input type="text" name="from_name" value="<?= htmlspecialchars($config['from_name']) ?>" 
                               placeholder="FR24 Monitor" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    </div>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">To Email:</label>
                    <input type="email" name="to_email" value="<?= htmlspecialchars($config['to_email']) ?>" 
                           placeholder="admin@example.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">Email address to receive alerts</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">Email Subject:</label>
                    <input type="text" name="subject" value="<?= htmlspecialchars($config['subject']) ?>" 
                           placeholder="FR24 Monitor Alert: System Reboot Required" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                </div>

                <div style="display: flex; gap: 1rem;">
                    <button type="submit" class="btn" style="background: #38a169;">Save Configuration</button>
                    <a href="test_email.php" class="btn" style="background: #3182ce;">Test Email</a>
                </div>
            </form>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>📝 Configuration Help</h3>
            </div>
            <div style="padding: 1.5rem;">
                <h4 style="margin-bottom: 1rem; color: #2d3748;">Common SMTP Settings:</h4>
                <ul style="margin-left: 1.5rem; margin-bottom: 1.5rem;">
                    <li><strong>Gmail:</strong> smtp.gmail.com, Port 587, TLS (requires App Password)</li>
                    <li><strong>Outlook/Hotmail:</strong> smtp-mail.outlook.com, Port 587, TLS</li>
                    <li><strong>Yahoo:</strong> smtp.mail.yahoo.com, Port 587, TLS</li>
                    <li><strong>ISP SMTP:</strong> Check with your internet provider</li>
                </ul>
                
                <h4 style="margin-bottom: 1rem; color: #2d3748;">Gmail Setup:</h4>
                <ol style="margin-left: 1.5rem;">
                    <li>Enable 2-factor authentication on your Google account</li>
                    <li>Go to Google Account settings → Security → App passwords</li>
                    <li>Generate an App Password for "Mail"</li>
                    <li>Use this App Password instead of your regular password</li>
                </ol>
            </div>
        </div>
    </div>
</body>
</html>
EOF

    # Create test email page
    cat > "$WEB_DIR/test_email.php" << 'EOF'
<?php
// Set timezone to match system timezone
$systemTimezone = trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC"'));
if ($systemTimezone && $systemTimezone !== 'UTC' && $systemTimezone !== '') {
    try {
        date_default_timezone_set($systemTimezone);
    } catch (Exception $e) {
        date_default_timezone_set('Europe/London');
    }
} else {
    date_default_timezone_set('Europe/London');
}

$configFile = dirname(__DIR__) . '/email_config.json';
$message = '';
$messageType = '';

if ($_POST && isset($_POST['test_email'])) {
    // Load configuration
    if (file_exists($configFile)) {
        $configData = file_get_contents($configFile);
        if ($configData) {
            $config = json_decode($configData, true);
            if ($config && $config['enabled']) {
                // Use the send_email.sh script to send test email
                $emailScript = dirname(__DIR__) . '/send_email.sh';
                
                if (file_exists($emailScript)) {
                    $testSubject = "FR24 Monitor Test Email";
                    $testMessage = "This is a test email to verify your FR24 Monitor email configuration is working correctly.

Timestamp: " . date('Y-m-d H:i:s T') . "
System: " . gethostname() . "
Timezone: $systemTimezone

If you received this email, your FR24 Monitor email alerts are configured properly and will be sent when the system requires a reboot.

Configuration tested:
- SMTP Server: " . $config['smtp_host'] . ":" . $config['smtp_port'] . "
- From: " . $config['from_email'] . "
- To: " . $config['to_email'] . "
- Security: " . strtoupper($config['smtp_security'] ?? 'TLS') . "

This is an automated test email from the FR24 Monitor system.";

                    # Execute the email script and capture both stdout and stderr
                    $command = 'cd ' . escapeshellarg(dirname($emailScript)) . ' && ' . 
                              escapeshellarg($emailScript) . ' ' . 
                              escapeshellarg($testSubject) . ' ' . 
                              escapeshellarg($testMessage) . ' 2>&1';
                    
                    $output = shell_exec($command);
                    $exitCode = shell_exec('echo $?');
                    
                    # Also capture msmtp log if it exists
                    $msmtpLog = '';
                    if (file_exists('/tmp/msmtp.log')) {
                        $msmtpLog = file_get_contents('/tmp/msmtp.log');
                    }
                    
                    if (trim($exitCode) === "0") {
                        $message = "Test email sent successfully! Check your inbox at " . htmlspecialchars($config['to_email']);
                        if (!empty($output)) {
                            $message .= "\n\nScript output:\n" . htmlspecialchars($output);
                        }
                        $messageType = 'success';
                    } else {
                        $message = "Failed to send test email (exit code: " . trim($exitCode) . ")";
                        if (!empty($output)) {
                            $message .= "\n\nScript output:\n" . htmlspecialchars($output);
                        }
                        if (!empty($msmtpLog)) {
                            $message .= "\n\nmsmtp log:\n" . htmlspecialchars($msmtpLog);
                        }
                        $messageType = 'error';
                    }
                } else {
                    $message = "Email helper script not found. Please reinstall the system.";
                    $messageType = 'error';
                }
            } else {
                $message = "Email alerts are not enabled. Please enable them in the configuration.";
                $messageType = 'error';
            }
        } else {
            $message = "Failed to load email configuration.";
            $messageType = 'error';
        }
    } else {
        $message = "No email configuration found. Please configure email settings first.";
        $messageType = 'error';
    }
}

// Load existing configuration for display
$config = [];
if (file_exists($configFile)) {
    $configData = file_get_contents($configFile);
    if ($configData) {
        $config = json_decode($configData, true) ?? [];
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Email - FR24 Monitor</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📧 Test Email Configuration</h1>
            <p>Send a test email to verify your configuration</p>
            <p><a href="config.php" class="btn">← Back to Configuration</a></p>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-<?= $messageType ?>">
                <pre style="white-space: pre-wrap; margin: 0; font-family: inherit;"><?= htmlspecialchars($message) ?></pre>
            </div>
        <?php endif; ?>

        <div class="table-container">
            <div class="table-header">
                <h3>✉️ Send Test Email</h3>
            </div>
            <div style="padding: 2rem;">
                <?php if (!empty($config) && $config['enabled']): ?>
                    <p style="margin-bottom: 1.5rem;">Current configuration:</p>
                    <ul style="margin-left: 1.5rem; margin-bottom: 2rem; color: #4a5568;">
                        <li><strong>SMTP Server:</strong> <?= htmlspecialchars($config['smtp_host']) ?>:<?= $config['smtp_port'] ?></li>
                        <li><strong>From:</strong> <?= htmlspecialchars($config['from_name']) ?> &lt;<?= htmlspecialchars($config['from_email']) ?>&gt;</li>
                        <li><strong>To:</strong> <?= htmlspecialchars($config['to_email']) ?></li>
                        <li><strong>Security:</strong> <?= strtoupper($config['smtp_security']) ?></li>
                    </ul>
                    
                    <form method="POST">
                        <button type="submit" name="test_email" value="1" class="btn" style="background: #3182ce;">
                            Send Test Email
                        </button>
                    </form>
                    
                    <div style="margin-top: 2rem; padding: 1rem; background: #f7fafc; border-radius: 5px;">
                        <h4 style="margin-bottom: 0.5rem; color: #2d3748;">Debug Information:</h4>
                        <small style="color: #718096;">
                            • The email script will show detailed logs above if there are any issues<br>
                            • Check that your SMTP credentials are correct<br>
                            • For Gmail, make sure you're using an App Password, not your regular password<br>
                            • Check your spam/junk folder if the test email doesn't arrive<br>
                            • You can also check /tmp/msmtp.log for more detailed SMTP logs
                        </small>
                    </div>
                <?php else: ?>
                    <div class="alert alert-warning">
                        Email alerts are not configured or enabled. Please <a href="config.php">configure email settings</a> first.
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</body>
</html>
EOF

    # Create email helper script
    cat > "$SCRIPT_DIR/send_email.sh" << 'EOF'
#!/bin/bash

# Email notification helper script for FR24 Monitor
# Usage: ./send_email.sh "subject" "message"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/email_config.json"

# Function to send email alert
send_email_alert() {
    local subject="$1"
    local message="$2"
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Email configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        echo "jq not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        else
            echo "Could not install jq. Please install it manually."
            return 1
        fi
    fi
    
    # Parse configuration
    local enabled=$(jq -r '.enabled // false' "$CONFIG_FILE")
    if [[ "$enabled" != "true" ]]; then
        echo "Email alerts are disabled"
        return 0
    fi
    
    local smtp_host=$(jq -r '.smtp_host // ""' "$CONFIG_FILE")
    local smtp_port=$(jq -r '.smtp_port // 587' "$CONFIG_FILE")
    local smtp_security=$(jq -r '.smtp_security // "tls"' "$CONFIG_FILE")
    local smtp_username=$(jq -r '.smtp_username // ""' "$CONFIG_FILE")
    local smtp_password=$(jq -r '.smtp_password // ""' "$CONFIG_FILE")
    local from_email=$(jq -r '.from_email // ""' "$CONFIG_FILE")
    local from_name=$(jq -r '.from_name // "FR24 Monitor"' "$CONFIG_FILE")
    local to_email=$(jq -r '.to_email // ""' "$CONFIG_FILE")
    
    # Validate required fields
    if [[ -z "$smtp_host" || -z "$from_email" || -z "$to_email" ]]; then
        echo "Missing required email configuration (smtp_host, from_email, or to_email)"
        return 1
    fi
    
    # Check if msmtp is available
    if ! command -v msmtp &> /dev/null; then
        echo "msmtp not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y msmtp msmtp-mta
        elif command -v yum &> /dev/null; then
            sudo yum install -y msmtp
        else
            echo "Could not install msmtp. Please install it manually."
            return 1
        fi
    fi
    
    # Create temporary msmtp configuration
    local msmtp_config=$(mktemp)
    cat > "$msmtp_config" << MSMTP_EOF
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

account        fr24monitor
host           $smtp_host
port           $smtp_port
from           $from_email
user           $smtp_username
password       $smtp_password
MSMTP_EOF

    # Adjust TLS settings based on security type
    if [[ "$smtp_security" == "ssl" ]]; then
        echo "tls_starttls   off" >> "$msmtp_config"
    elif [[ "$smtp_security" == "none" ]]; then
        echo "tls            off" >> "$msmtp_config"
        echo "auth           off" >> "$msmtp_config"
    fi
    
    echo "" >> "$msmtp_config"
    echo "account default : fr24monitor" >> "$msmtp_config"
    
    # Create email message
    local email_content=$(cat << EMAIL_EOF
To: $to_email
From: $from_name <$from_email>
Subject: $subject
Date: $(date -R)
Content-Type: text/plain; charset=UTF-8

$message

---
This message was sent automatically by the FR24 Monitor system.
Hostname: $(hostname)
Timestamp: $(date)
EMAIL_EOF
)
    
    # Send email
    if echo "$email_content" | msmtp -C "$msmtp_config" "$to_email"; then
        echo "Email sent successfully to $to_email"
        rm -f "$msmtp_config"
        return 0
    else
        echo "Failed to send email. Check /tmp/msmtp.log for details."
        rm -f "$msmtp_config"
        return 1
    fi
}

# If script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 \"subject\" \"message\""
        exit 1
    fi
    
    send_email_alert "$1" "$2"
fi
EOF

    chmod +x "$SCRIPT_DIR/send_email.sh"
    
    return 0
}

# Function to uninstall systemd service
uninstall_systemd_service() {
    print_status "INFO" "Removing systemd service..."
    
    local service_name="fr24-monitor-web"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    if systemctl list-unit-files | grep -q "$service_name"; then
        print_status "INFO" "Stopping and disabling systemd service..."
        sudo systemctl stop "$service_name" 2>/dev/null || true
        sudo systemctl disable "$service_name" 2>/dev/null || true
        
        if [[ -f "$service_file" ]]; then
            sudo rm -f "$service_file"
            sudo systemctl daemon-reload
            print_status "SUCCESS" "Removed systemd service"
        fi
    else
        print_status "INFO" "Systemd service not found"
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

# Function to show systemd service status
show_systemd_service_status() {
    local service_name="fr24-monitor-web"
    
    print_status "INFO" "FR24 Monitor Web Service Status"
    echo "================================"
    
    # Check if systemd service exists
    if systemctl list-unit-files | grep -q "$service_name"; then
        print_status "SUCCESS" "Systemd service is installed: $service_name"
        
        # Show service status
        echo
        print_status "INFO" "Service status:"
        sudo systemctl status "$service_name" --no-pager --lines=10 2>/dev/null || {
            print_status "WARN" "Could not get service status (may need sudo)"
        }
        
        # Show if enabled for auto-start
        echo
        if systemctl is-enabled "$service_name" >/dev/null 2>&1; then
            print_status "SUCCESS" "Service is enabled for auto-start"
        else
            print_status "WARN" "Service is not enabled for auto-start"
            print_status "INFO" "Enable with: sudo systemctl enable $service_name"
        fi
        
        # Show if currently active
        echo
        if systemctl is-active "$service_name" >/dev/null 2>&1; then
            print_status "SUCCESS" "Service is currently running"
        else
            print_status "WARN" "Service is not currently running"
            print_status "INFO" "Start with: sudo systemctl start $service_name"
        fi
        
    else
        print_status "WARN" "Systemd service not found: $service_name"
        print_status "INFO" "Install the service by running: $0 install"
    fi
    
    echo
    print_status "INFO" "Manual web server control:"
    print_status "INFO" "  Start:   $0 start-web"
    print_status "INFO" "  Stop:    $0 stop-web"
    print_status "INFO" "  Restart: $0 restart-web"
}

# Function to test email alert system
test_email_alert() {
    print_status "INFO" "Testing FR24 Monitor Email Alert System"
    echo "================================"
    
    local email_script="$SCRIPT_DIR/send_email.sh"
    local config_file="$SCRIPT_DIR/email_config.json"
    
    # Check if email script exists
    if [[ ! -f "$email_script" ]]; then
        print_status "ERROR" "Email helper script not found: $email_script"
        print_status "INFO" "Please run: $0 install"
        return 1
    fi
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "Email configuration not found: $config_file"
        print_status "INFO" "Please configure email settings via the web interface: http://localhost:$WEB_PORT/config.php"
        return 1
    fi
    
    # Test email content similar to what would be sent during a reboot
    local test_subject="FR24 Monitor Test: Reboot Alert System Test"
    local test_message="This is a test of the FR24 Monitor reboot alert system.

SIMULATED REBOOT EVENT DETAILS:
=====================================
Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
Reason: Testing reboot alert email system
Aircraft Tracked: 0 (simulated)
Alert Threshold: 0
System Uptime: $(uptime -p)
Monitoring Endpoint: http://localhost:8754/monitor.json

SYSTEM INFORMATION:
=====================================
System Load: $(uptime | awk -F'load average:' '{print $2}' | xargs)
Memory Usage: $(free -h | awk 'NR==2{printf "%.1f%%", $3/$2*100}')
Disk Usage: $(df -h / | awk 'NR==2{print $5}')
Network: $(ip route get 1.1.1.1 | head -1 | awk '{print $7}' | head -1)

=====================================

*** THIS IS A TEST EMAIL ***
No actual reboot has occurred. This is a test to verify that reboot alerts 
will be delivered successfully when the FR24 Monitor system detects a need 
to restart the server.

If you received this email, your FR24 Monitor email configuration is working 
correctly and you will receive notifications when the system requires a reboot.

To disable these test emails, avoid running the 'test-email' command.
To configure email settings, visit: http://localhost:$WEB_PORT/config.php

This is an automated test email from the FR24 Monitor system."

    print_status "INFO" "Sending test reboot alert email..."
    print_status "INFO" "Subject: $test_subject"
    
    # Execute the email script and capture both stdout and stderr
    local output
    local exit_code
    
    if output=$(bash "$email_script" "$test_subject" "$test_message" 2>&1); then
        exit_code=$?
        print_status "SUCCESS" "Test email sent successfully!"
        print_status "INFO" "Check your email inbox for the test reboot alert."
        echo
        print_status "INFO" "Email script output:"
        echo "$output"
    else
        exit_code=$?
        print_status "ERROR" "Failed to send test email (exit code: $exit_code)"
        echo
        print_status "ERROR" "Email script output:"
        echo "$output"
        echo
        print_status "INFO" "Troubleshooting steps:"
        print_status "INFO" "1. Check email configuration: http://localhost:$WEB_PORT/config.php"
        print_status "INFO" "2. Verify SMTP settings are correct"
        print_status "INFO" "3. Check if email service requires app passwords (e.g., Gmail)"
        print_status "INFO" "4. Ensure network connectivity to SMTP server"
        return 1
    fi
    
    echo
    print_status "INFO" "Test complete. If you received the email, reboot alerts will work correctly."
}

# Function to create git templates
create_git_templates() {
    print_status "INFO" "Creating git templates..."
    
    # Create email config template
    cat > "$SCRIPT_DIR/email_config.template.json" << 'EOF'
{
  "enabled": false,
  "smtp_host": "smtp.gmail.com",
  "smtp_port": 587,
  "smtp_security": "tls",
  "use_tls": true,
  "use_starttls": true,
  "smtp_username": "your.email@example.com",
  "smtp_password": "your-app-password-here",
  "from_email": "your.email@example.com",
  "from_name": "FR24 Monitor",
  "to_email": "admin@example.com",
  "subject": "FR24 Monitor Alert: System Reboot Required"
}
EOF

    # Create README for email configuration
    cat > "$SCRIPT_DIR/EMAIL_SETUP.md" << 'EOF'
# FR24 Monitor Email Configuration

## Quick Setup

1. Copy the email template:
   ```bash
   cp email_config.template.json email_config.json
   ```

2. Edit `email_config.json` with your email settings, or use the web interface:
   - Visit: http://localhost:6869/config.php
   - Configure your SMTP settings
   - Test the email configuration

## Email Provider Settings

### Gmail
- SMTP Host: `smtp.gmail.com`
- Port: `587`
- Security: `TLS`
- Username: Your Gmail address
- Password: **Use an App Password, not your regular password**
- Setup App Password: Google Account → Security → 2-Step Verification → App passwords

### Outlook/Hotmail
- SMTP Host: `smtp-mail.outlook.com`
- Port: `587`
- Security: `TLS`
- Username: Your Outlook/Hotmail address
- Password: Your regular password (or app password if 2FA enabled)

### Yahoo
- SMTP Host: `smtp.mail.yahoo.com`
- Port: `587`
- Security: `TLS`
- Username: Your Yahoo address
- Password: **Use an App Password**

## Security Notes

- The `email_config.json` file is ignored by git to prevent password exposure
- Never commit email passwords to version control
- Use app passwords when available (more secure than regular passwords)
- The web interface at `/config.php` provides a user-friendly setup experience

## Testing

Test your email configuration:
```bash
./fr24_manager.sh test-email
```

This will send a simulated reboot alert to verify your settings work correctly.
EOF
    
    if [[ -f "$SCRIPT_DIR/email_config.template.json" ]]; then
        print_status "SUCCESS" "Created email configuration template"
    fi
    
    if [[ -f "$SCRIPT_DIR/EMAIL_SETUP.md" ]]; then
        print_status "SUCCESS" "Created email setup documentation"
    fi
    
    # Check if this is a git repository and give advice
    if [[ -d "$SCRIPT_DIR/.git" ]]; then
        print_status "INFO" "Git repository detected"
        print_status "INFO" "To ensure sensitive data is not committed:"
        print_status "INFO" "1. Copy email template: cp email_config.template.json email_config.json"
        print_status "INFO" "2. Configure via web interface: http://localhost:$WEB_PORT/config.php"
        print_status "INFO" "3. Ensure .gitignore file prevents sensitive files from being committed"
    else
        print_status "INFO" "To initialize git repository:"
        print_status "INFO" "  git init"
        print_status "INFO" "  git add ."
        print_status "INFO" "  git commit -m 'Initial FR24 Monitor setup'"
    fi
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
            install_systemd_service
            start_systemd_service
            create_git_templates
            ;;
        "uninstall")
            uninstall_systemd_service
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
        "restart-web")
            stop_webserver
            sleep 2
            start_webserver
            ;;
        "service-status")
            show_systemd_service_status
            ;;
        "test-email")
            test_email_alert
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
    install       Install FR24 monitor with cron, logrotate, database, web dashboard, and systemd service
    uninstall     Remove FR24 monitor and all components (cron, logrotate, web, database, systemd service)
    status        Show current system status, cron jobs, logs, and web server status
    edit          Edit crontab manually
    test          Test the monitor script in dry-run mode
    test-email    Send a test reboot alert email to verify email configuration
    preview       Show the cron and logrotate entries that would be installed
    start-web     Start the web dashboard server
    stop-web      Stop the web dashboard server
    restart-web   Restart the web dashboard server
    service-status Show systemd service status and auto-start configuration
    help          Show this help message

EXAMPLES:
    $0 preview          # Preview what will be installed
    $0 install          # Install complete monitoring system with web dashboard and auto-start
    $0 status           # Check if monitoring is running
    $0 test             # Test the monitoring script safely
    $0 test-email       # Send a test reboot alert email
    $0 start-web        # Start the web dashboard server
    $0 stop-web         # Stop the web dashboard server
    $0 restart-web      # Restart the web dashboard server
    $0 service-status   # Check systemd service status and auto-start configuration
    $0 uninstall        # Remove complete monitoring system

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
