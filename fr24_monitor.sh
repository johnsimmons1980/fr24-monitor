#!/bin/bash

# FR24 Server Monitor Script
# Monitors aircraft tracking status and reboots server if tracking drops to 0
# Usage: ./fr24_monitor.sh [--dry-run] [--endpoint URL] [--help]

set -euo pipefail

# Get script directory for portable paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_ENDPOINT="http://localhost:8754/monitor.json"  # Common FR24 feeder endpoint
TRACKED_THRESHOLD=0
MINIMUM_UPTIME_HOURS=2  # Minimum uptime before allowing reboot
DRY_RUN=false
VERBOSE=false
LOG_FILE="$SCRIPT_DIR/fr24_monitor.log"  # Use script directory by default
CONFIG_FILE="$SCRIPT_DIR/.fr24_monitor_config"  # Configuration file for cached settings
MAX_LOG_SIZE_MB=2  # Maximum log file size in MB before rotation
MAX_LOG_FILES=2     # Maximum number of rotated log files to keep
FR24_SERVICE_NAME="fr24feed"  # Default FR24 service name

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Monitor FR24 server aircraft tracking status and reboot if tracking drops to 0.

OPTIONS:
    --endpoint URL|PORT|auto  FR24 monitoring endpoint. Can be:
                              - Full URL: http://localhost:8754/monitor.json
                              - Port number: 8754 (will build URL automatically) 
                              - 'auto' to auto-detect port (cached after first detection)
                              - IP/hostname: 192.168.1.100 (will add :8754/monitor.json)
                              (default: auto-detect or $DEFAULT_ENDPOINT)
    --dry-run                Run in dry-run mode (don't actually reboot)
    --verbose                Enable verbose output
    --log-file FILE          Log file path (default: $LOG_FILE)
    --min-uptime HOURS       Minimum uptime hours before allowing reboot (default: $MINIMUM_UPTIME_HOURS)
    --threshold NUM          Reboot threshold - reboot if tracked <= NUM (default: $TRACKED_THRESHOLD)
    --max-log-size MB        Maximum log file size in MB before rotation (default: $MAX_LOG_SIZE_MB)
    --max-log-files N        Maximum number of rotated log files to keep (default: $MAX_LOG_FILES)
    --service-name NAME      FR24 service name to restart if endpoint fails (default: fr24feed)
    --clear-cache            Clear cached endpoint configuration and re-detect
    --show-config            Show current cached configuration
    --help                   Show this help message

CONFIGURATION:
    Default endpoint: auto-detect or $DEFAULT_ENDPOINT
    Default log file: $LOG_FILE
    Default config file: $CONFIG_FILE
    Default reboot threshold: tracked <= $TRACKED_THRESHOLD
    Default minimum uptime: $MINIMUM_UPTIME_HOURS hours
    Default max log size: $MAX_LOG_SIZE_MB MB
    Default max log files: $MAX_LOG_FILES files
    Default service name: $FR24_SERVICE_NAME

Examples:
    $0 --dry-run                                    # Auto-detect port and test (uses cache)
    $0 --endpoint auto --dry-run                    # Explicitly auto-detect port
    $0 --endpoint 8754 --dry-run                    # Use specific port
    $0 --endpoint http://192.168.1.100:8754/monitor.json --dry-run  # Full URL
    $0 --endpoint 192.168.1.100 --dry-run          # Remote host (will use port 8754)
    $0 --clear-cache --dry-run                      # Clear cache and re-detect
    $0 --show-config                                # Show cached configuration
    $0 --verbose                                    # Production mode with verbose output
    $0 --min-uptime 4 --dry-run                    # Test with 4-hour minimum uptime
    $0 --threshold 50 --dry-run                    # Test reboot logic when tracked <= 50
    $0 --threshold 200 --dry-run --verbose         # Test with high threshold to trigger reboot
    $0 --max-log-size 5 --max-log-files 3          # Rotate logs at 5MB, keep 3 files
    $0 --service-name piaware --endpoint auto --dry-run  # Auto-detect for PiAware feeder

CACHE BEHAVIOR:
    - First run with 'auto' will detect and cache the endpoint
    - Subsequent runs will use the cached endpoint (much faster)
    - If cached endpoint becomes unresponsive, automatic re-detection occurs
    - Use --clear-cache to force re-detection
    - Use --show-config to view cached settings

EOF
}

# Function to rotate log files if needed
rotate_logs() {
    # Check if log file exists and is larger than max size
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    # Get file size in MB
    local file_size_bytes=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    local file_size_mb=$((file_size_bytes / 1024 / 1024))
    
    # Check if rotation is needed
    if [[ "$file_size_mb" -ge "$MAX_LOG_SIZE_MB" ]]; then
        echo "Log file size ($file_size_mb MB) exceeds limit ($MAX_LOG_SIZE_MB MB), rotating logs..."
        
        # Rotate existing log files
        for ((i=MAX_LOG_FILES-1; i>=1; i--)); do
            local current_file="${LOG_FILE}.$i"
            local next_file="${LOG_FILE}.$((i+1))"
            
            if [[ -f "$current_file" ]]; then
                if [[ "$i" -eq $((MAX_LOG_FILES-1)) ]]; then
                    # Delete the oldest file
                    rm -f "$current_file"
                    echo "Deleted old log file: $current_file"
                else
                    # Move to next number
                    mv "$current_file" "$next_file"
                    echo "Rotated: $current_file -> $next_file"
                fi
            fi
        done
        
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1"
        echo "Rotated: $LOG_FILE -> ${LOG_FILE}.1"
        
        # Create new empty log file
        touch "$LOG_FILE"
        echo "Created new log file: $LOG_FILE"
    fi
}

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%d/%m/%Y %H:%M:%S')
    
    # Rotate logs if needed (check only once per script run)
    if [[ ! -f "$HOME/.fr24_log_rotated_$$" ]]; then
        rotate_logs
        touch "$HOME/.fr24_log_rotated_$$" 2>/dev/null || true
    fi
    
    # Try to log to file if possible
    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    elif [[ "$level" == "ERROR" ]] && [[ ! -f "$HOME/.fr24_log_warning_shown" ]]; then
        # Show warning once about log file issue
        echo "[$timestamp] [WARN] Cannot write to log file: $LOG_FILE" >&2
        echo "[$timestamp] [WARN] Check permissions or use --log-file to specify a writable location" >&2
        touch "$HOME/.fr24_log_warning_shown" 2>/dev/null || true
    fi
    
    # Also output to console if verbose or if it's an important message
    if [[ "$VERBOSE" == "true" ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "WARN" ]] || [[ "$level" == "REBOOT" ]] || [[ "$level" == "SUCCESS" ]]; then
        case "$level" in
            "ERROR")
                echo -e "${RED}[$timestamp] [ERROR] $message${NC}" >&2
                ;;
            "WARN")
                echo -e "${YELLOW}[$timestamp] [WARN] $message${NC}"
                ;;
            "INFO")
                echo -e "${BLUE}[$timestamp] [INFO] $message${NC}"
                ;;
            "SUCCESS")
                echo -e "${GREEN}[$timestamp] [SUCCESS] $message${NC}"
                ;;
            "REBOOT")
                echo -e "${RED}[$timestamp] [REBOOT] $message${NC}"
                ;;
            *)
                echo "[$timestamp] [$level] $message"
                ;;
        esac
    fi
}

# Function to get system uptime in hours
get_uptime_hours() {
    local uptime_seconds
    
    # Try to get uptime from /proc/uptime (most reliable)
    if [[ -r /proc/uptime ]]; then
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    else
        # Fallback to uptime command
        uptime_seconds=$(uptime -s | xargs -I {} date -d "{}" +%s)
        local current_time=$(date +%s)
        uptime_seconds=$((current_time - uptime_seconds))
    fi
    
    local uptime_hours=$((uptime_seconds / 3600))
    echo "$uptime_hours"
}

# Function to check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    for tool in curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required tools: ${missing_tools[*]}"
        log_message "ERROR" "Please install missing tools. On Ubuntu/Debian: sudo apt-get install curl jq"
        exit 1
    fi
}

# Function to restart FR24 service
restart_fr24_service() {
    local service_name="$1"
    
    log_message "INFO" "Attempting to restart FR24 service: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "DRY RUN: Would restart service now"
        log_message "INFO" "DRY RUN: Command that would be executed: sudo systemctl restart $service_name"
        return 0
    fi
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^$service_name\.service"; then
        log_message "ERROR" "Service '$service_name' not found in systemctl"
        log_message "INFO" "Available services matching 'fr24': $(systemctl list-unit-files | grep fr24 | awk '{print $1}' | tr '\n' ' ')"
        return 1
    fi
    
    # Try to restart the service
    if sudo systemctl restart "$service_name"; then
        log_message "INFO" "Successfully restarted service: $service_name"
        
        # Wait a moment for service to start
        sleep 5
        
        # Check service status
        if systemctl is-active --quiet "$service_name"; then
            log_message "SUCCESS" "Service $service_name is now running"
            return 0
        else
            log_message "WARN" "Service $service_name restarted but may not be fully operational"
            return 1
        fi
    else
        log_message "ERROR" "Failed to restart service: $service_name"
        return 1
    fi
}

# Function to fetch and parse FR24 data
get_fr24_stats() {
    local endpoint="$1"
    local temp_file=$(mktemp)
    
    log_message "INFO" "Fetching data from: $endpoint" >&2
    
    # Fetch data with timeout
    if ! curl -s --connect-timeout 10 --max-time 30 "$endpoint" -o "$temp_file"; then
        log_message "ERROR" "Failed to fetch data from $endpoint" >&2
        rm -f "$temp_file"
        
        # Try to restart FR24 service if endpoint is unavailable
        log_message "WARN" "Endpoint unavailable - attempting to restart FR24 service" >&2
        if restart_fr24_service "$FR24_SERVICE_NAME"; then
            log_message "INFO" "Service restarted, waiting 30 seconds before retry..." >&2
            sleep 30
            
            # Retry the connection after service restart
            log_message "INFO" "Retrying connection after service restart..." >&2
            if curl -s --connect-timeout 10 --max-time 30 "$endpoint" -o "$temp_file"; then
                log_message "SUCCESS" "Successfully reconnected after service restart" >&2
            else
                log_message "ERROR" "Still cannot connect after service restart" >&2
                rm -f "$temp_file"
                return 1
            fi
        else
            log_message "ERROR" "Service restart failed, endpoint still unavailable" >&2
            return 1
        fi
    fi
    
    log_message "INFO" "Successfully fetched data from FR24 endpoint" >&2
    
    # Check if response is valid JSON
    if ! jq . "$temp_file" >/dev/null 2>&1; then
        log_message "ERROR" "Invalid JSON response from $endpoint" >&2
        log_message "ERROR" "Response content: $(cat "$temp_file")" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    log_message "INFO" "JSON response validated successfully" >&2
    
    # Parse the JSON response - using FR24 feeder specific field names
    local tracked=$(jq -r '.feed_num_ac_tracked // .aircraft_tracked // .tracked // empty' "$temp_file" 2>/dev/null)
    local uploaded=$(jq -r '.feed_last_ac_sent_num // .aircraft_uploaded // .uploaded // empty' "$temp_file" 2>/dev/null)
    
    # Also get feed status for additional logging
    local feed_status=$(jq -r '.feed_status // "unknown"' "$temp_file" 2>/dev/null)
    local feed_server=$(jq -r '.feed_current_server // "unknown"' "$temp_file" 2>/dev/null)
    
    rm -f "$temp_file"
    
    log_message "INFO" "Feed status: $feed_status, Server: $feed_server" >&2
    
    # Validate that we got numeric values
    if [[ ! "$tracked" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Could not parse 'feed_num_ac_tracked' value. Got: '$tracked'" >&2
        log_message "INFO" "Available JSON keys: $(curl -s "$endpoint" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')" >&2
        return 1
    fi
    
    if [[ ! "$uploaded" =~ ^[0-9]+$ ]]; then
        log_message "WARN" "Could not parse 'feed_last_ac_sent_num' value. Got: '$uploaded' (continuing anyway)" >&2
        uploaded="N/A"
    fi
    
    log_message "INFO" "Parsed values - Tracked: $tracked, Uploaded: $uploaded" >&2
    
    echo "$tracked,$uploaded"
    return 0
}

# Function to reboot the server
reboot_server() {
    local reason="$1"
    
    # Check uptime before rebooting
    local uptime_hours=$(get_uptime_hours)
    log_message "INFO" "Current system uptime: $uptime_hours hours (minimum required: $MINIMUM_UPTIME_HOURS hours)"
    
    if [[ "$uptime_hours" -lt "$MINIMUM_UPTIME_HOURS" ]]; then
        log_message "WARN" "System uptime ($uptime_hours hours) is less than minimum required ($MINIMUM_UPTIME_HOURS hours)"
        log_message "WARN" "Skipping reboot to prevent restart loops. Will retry monitoring."
        return 1
    fi
    
    log_message "REBOOT" "$reason"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "DRY RUN: Would reboot server now (uptime check passed: $uptime_hours >= $MINIMUM_UPTIME_HOURS hours)"
        log_message "INFO" "DRY RUN: Command that would be executed: sudo reboot"
        return 0
    fi
    
    log_message "REBOOT" "Initiating server reboot..."
    
    # Check if we have reboot permissions
    if ! sudo -n reboot &>/dev/null; then
        log_message "ERROR" "No permission to reboot. Please run with sudo or configure passwordless sudo for reboot command"
        return 1
    fi
    
    # Give a short delay for logging to complete
    sleep 2
    sudo reboot
}

# Function to detect FR24 feeder port dynamically
detect_fr24_port() {
    local detected_port=""
    local service_name="$1"
    
    log_message "INFO" "Attempting to detect FR24 feeder port..." >&2
    
    # Method 1: Check if fr24feed process is running and extract port from command line
    if command -v pgrep >/dev/null 2>&1; then
        local fr24_pids=$(pgrep -f "$service_name" 2>/dev/null || true)
        if [[ -n "$fr24_pids" ]]; then
            log_message "INFO" "Found $service_name process(es): $fr24_pids" >&2
            
            # Check command line arguments for port configuration
            for pid in $fr24_pids; do
                if [[ -r "/proc/$pid/cmdline" ]]; then
                    local cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
                    log_message "INFO" "Process $pid cmdline: $cmdline" >&2
                    
                    # Look for port parameters in various formats
                    if [[ "$cmdline" =~ --http-port[[:space:]]*[=[:space:]]*([0-9]+) ]]; then
                        detected_port="${BASH_REMATCH[1]}"
                        log_message "INFO" "Found port from --http-port parameter: $detected_port" >&2
                        break
                    elif [[ "$cmdline" =~ -p[[:space:]]*([0-9]+) ]]; then
                        detected_port="${BASH_REMATCH[1]}"
                        log_message "INFO" "Found port from -p parameter: $detected_port" >&2
                        break
                    fi
                fi
            done
        fi
    fi
    
    # Method 2: Check netstat/ss for listening ports by the service
    if [[ -z "$detected_port" ]] && command -v ss >/dev/null 2>&1; then
        log_message "INFO" "Checking listening ports with ss command..." >&2
        local listening_ports=$(ss -tulpn 2>/dev/null | grep "$service_name" | grep -o ':[0-9]*' | sed 's/://' | sort -u || true)
        if [[ -n "$listening_ports" ]]; then
            # Look for web ports (typically 8000-9999 range for web interfaces)
            for port in $listening_ports; do
                if [[ "$port" -ge 8000 ]] && [[ "$port" -le 9999 ]]; then
                    detected_port="$port"
                    log_message "INFO" "Found web service port from ss: $detected_port" >&2
                    break
                fi
            done
            
            # If no web port found, take the first listening port
            if [[ -z "$detected_port" ]]; then
                detected_port=$(echo "$listening_ports" | head -1)
                log_message "INFO" "Using first listening port from ss: $detected_port" >&2
            fi
        fi
    fi
    
    # Method 3: Check common FR24 ports by testing HTTP connectivity
    if [[ -z "$detected_port" ]]; then
        log_message "INFO" "Testing common FR24 ports..." >&2
        local common_ports=(8754 8080 8088 9000 9090)
        
        for port in "${common_ports[@]}"; do
            log_message "INFO" "Testing port $port..." >&2
            if curl -s --connect-timeout 2 --max-time 5 "http://localhost:$port/monitor.json" >/dev/null 2>&1; then
                detected_port="$port"
                log_message "INFO" "Found responsive FR24 endpoint on port: $detected_port" >&2
                break
            elif curl -s --connect-timeout 2 --max-time 5 "http://localhost:$port/" >/dev/null 2>&1; then
                # Check if it responds to root path (might be FR24 web interface)
                detected_port="$port"
                log_message "INFO" "Found responsive web service on port: $detected_port (assuming FR24)" >&2
                break
            fi
        done
    fi
    
    # Method 4: Check systemd service configuration if available
    if [[ -z "$detected_port" ]] && command -v systemctl >/dev/null 2>&1; then
        log_message "INFO" "Checking systemd service configuration..." >&2
        local service_status=$(systemctl show "$service_name" --property=ExecStart 2>/dev/null || true)
        if [[ -n "$service_status" ]]; then
            log_message "INFO" "Service ExecStart: $service_status" >&2
            if [[ "$service_status" =~ --http-port[[:space:]]*[=[:space:]]*([0-9]+) ]]; then
                detected_port="${BASH_REMATCH[1]}"
                log_message "INFO" "Found port from systemd service config: $detected_port" >&2
            fi
        fi
    fi
    
    # Method 5: Check configuration files in common locations
    if [[ -z "$detected_port" ]]; then
        log_message "INFO" "Checking configuration files..." >&2
        local config_paths=(
            "/etc/fr24feed.ini"
            "/etc/fr24feed/fr24feed.ini"
            "/usr/local/etc/fr24feed.ini"
            "/opt/fr24feed/fr24feed.ini"
            "$HOME/.fr24feed.ini"
        )
        
        for config_file in "${config_paths[@]}"; do
            if [[ -r "$config_file" ]]; then
                log_message "INFO" "Checking config file: $config_file" >&2
                local port_line=$(grep -i "http.*port" "$config_file" 2>/dev/null | head -1 || true)
                if [[ -n "$port_line" ]]; then
                    # Extract port number from various config formats
                    if [[ "$port_line" =~ [^0-9]([0-9]{4,5})[^0-9] ]]; then
                        detected_port="${BASH_REMATCH[1]}"
                        log_message "INFO" "Found port in config file $config_file: $detected_port" >&2
                        break
                    fi
                fi
            fi
        done
    fi
    
    if [[ -n "$detected_port" ]]; then
        echo "$detected_port"
        return 0
    else
        log_message "WARN" "Could not detect FR24 feeder port, using default: 8754" >&2
        echo "8754"
        return 1
    fi
}

# Function to build endpoint URL with auto-detected port
build_endpoint_url() {
    local provided_endpoint="$1"
    local service_name="$2"
    
    # If user provided a full URL, use it as-is
    if [[ "$provided_endpoint" =~ ^https?:// ]]; then
        echo "$provided_endpoint"
        return 0
    fi
    
    # If user provided just a port number, build URL with it
    if [[ "$provided_endpoint" =~ ^[0-9]+$ ]]; then
        echo "http://localhost:$provided_endpoint/monitor.json"
        return 0
    fi
    
    # If user provided 'auto' or default endpoint, try cached config first
    if [[ "$provided_endpoint" == "auto" ]] || [[ "$provided_endpoint" == "$DEFAULT_ENDPOINT" ]]; then
        
        # Try to load cached endpoint first
        local cached_endpoint
        if cached_endpoint=$(load_endpoint_config); then
            
            # Verify the cached endpoint still works
            log_message "INFO" "Verifying cached endpoint is still responsive..." >&2
            if curl -s --connect-timeout 5 --max-time 10 "$cached_endpoint" >/dev/null 2>&1; then
                log_message "SUCCESS" "Cached endpoint verified and responsive: $cached_endpoint" >&2
                echo "$cached_endpoint"
                return 0
            else
                log_message "WARN" "Cached endpoint no longer responsive, will re-detect" >&2
                clear_endpoint_config
            fi
        fi
        
        # No valid cached config, perform detection
        log_message "INFO" "Performing endpoint auto-detection..." >&2
        local detected_port=$(detect_fr24_port "$service_name")
        local final_url="http://localhost:$detected_port/monitor.json"
        
        log_message "INFO" "Auto-detected FR24 endpoint: $final_url" >&2
        
        # Verify the detected endpoint works
        if curl -s --connect-timeout 5 --max-time 10 "$final_url" >/dev/null 2>&1; then
            log_message "SUCCESS" "Verified auto-detected endpoint is responsive: $final_url" >&2
            # Save successful detection to cache
            save_endpoint_config "$final_url" "$service_name"
        else
            log_message "WARN" "Auto-detected endpoint not responsive, you may need to specify --endpoint manually" >&2
        fi
        
        echo "$final_url"
        return 0
    fi
    
    # Fallback: treat as hostname or IP
    echo "http://$provided_endpoint/monitor.json"
    return 0
}

# Function to save endpoint configuration
save_endpoint_config() {
    local endpoint="$1"
    local service_name="$2"
    local timestamp=$(date '+%d/%m/%Y %H:%M:%S')
    
    log_message "INFO" "Saving endpoint configuration to $CONFIG_FILE" >&2
    
    cat > "$CONFIG_FILE" << EOF
# FR24 Monitor Configuration File
# Auto-generated on $timestamp
# This file caches the detected endpoint to avoid re-detection on every run

FR24_ENDPOINT="$endpoint"
FR24_SERVICE_NAME="$service_name"
DETECTION_DATE="$timestamp"
EOF
    
    log_message "SUCCESS" "Endpoint configuration saved: $endpoint" >&2
}

# Function to load endpoint configuration
load_endpoint_config() {
    if [[ -r "$CONFIG_FILE" ]]; then
        log_message "INFO" "Loading cached endpoint configuration from $CONFIG_FILE" >&2
        
        # Source the config file safely
        local cached_endpoint=""
        local cached_service=""
        local detection_date=""
        
        # Parse config file manually for safety
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove quotes from value
            value=$(echo "$value" | sed 's/^"//; s/"$//')
            
            case "$key" in
                "FR24_ENDPOINT")
                    cached_endpoint="$value"
                    ;;
                "FR24_SERVICE_NAME") 
                    cached_service="$value"
                    ;;
                "DETECTION_DATE")
                    detection_date="$value"
                    ;;
            esac
        done < "$CONFIG_FILE"
        
        if [[ -n "$cached_endpoint" ]] && [[ "$cached_endpoint" =~ ^https?:// ]]; then
            log_message "SUCCESS" "Using cached endpoint: $cached_endpoint (detected: $detection_date)" >&2
            echo "$cached_endpoint"
            return 0
        else
            log_message "WARN" "Invalid cached endpoint configuration, will re-detect" >&2
            return 1
        fi
    else
        log_message "INFO" "No cached endpoint configuration found, will detect" >&2
        return 1
    fi
}

# Function to clear endpoint configuration (for troubleshooting)
clear_endpoint_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_message "INFO" "Cleared cached endpoint configuration" >&2
        return 0
    else
        log_message "INFO" "No cached configuration to clear" >&2
        return 1
    fi
}

# Main monitoring function
monitor_fr24() {
    local endpoint="$1"
    
    log_message "INFO" "Starting FR24 monitoring check"
    
    # Show current uptime in verbose mode only
    if [[ "$VERBOSE" == "true" ]]; then
        local current_uptime=$(get_uptime_hours)
        log_message "INFO" "Current system uptime: $current_uptime hours"
    fi
    
    # Get current stats
    local stats_result
    if ! stats_result=$(get_fr24_stats "$endpoint"); then
        log_message "ERROR" "Failed to get FR24 statistics - monitoring check failed"
        exit 1
    fi
    
    IFS=',' read -r tracked uploaded <<< "$stats_result"
    
    log_message "INFO" "Aircraft tracked: $tracked, uploaded: $uploaded"
    
    # Check if we need to reboot
    if [[ "$tracked" -le "$TRACKED_THRESHOLD" ]]; then
        log_message "WARN" "ALERT: Aircraft tracking has dropped to critical level!"
        log_message "WARN" "Current tracked: $tracked (threshold: $TRACKED_THRESHOLD)"
        
        local reason="Aircraft tracking has dropped to $tracked (threshold: $TRACKED_THRESHOLD). Rebooting server."
        if reboot_server "$reason"; then
            log_message "INFO" "Reboot action completed successfully"
            exit 0  # Successful reboot or dry-run
        else
            log_message "WARN" "Reboot was skipped due to uptime check"
            log_message "INFO" "Will continue monitoring - next check may attempt reboot again"
        fi
    else
        log_message "SUCCESS" "Aircraft tracking healthy ($tracked aircraft tracked)"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_message "INFO" "Monitoring check completed at $(date)"
    fi
}

# Parse command line arguments
ENDPOINT="auto"  # Changed to auto-detect by default
CLEAR_CACHE=false
SHOW_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --min-uptime)
            MINIMUM_UPTIME_HOURS="$2"
            shift 2
            ;;
        --threshold)
            TRACKED_THRESHOLD="$2"
            shift 2
            ;;
        --max-log-size)
            MAX_LOG_SIZE_MB="$2"
            shift 2
            ;;
        --max-log-files)
            MAX_LOG_FILES="$2"
            shift 2
            ;;
        --service-name)
            FR24_SERVICE_NAME="$2"
            shift 2
            ;;
        --clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        --show-config)
            SHOW_CONFIG=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Handle config-only operations first
if [[ "$SHOW_CONFIG" == "true" ]]; then
    echo "FR24 Monitor Configuration"
    echo "=========================="
    echo "Config file: $CONFIG_FILE"
    echo
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Cached configuration:"
        cat "$CONFIG_FILE"
        echo
        echo "Configuration status: Active"
    else
        echo "No cached configuration found."
        echo "Configuration status: Not configured (will auto-detect on first run)"
    fi
    exit 0
fi

if [[ "$CLEAR_CACHE" == "true" ]]; then
    echo "Clearing cached endpoint configuration..."
    if clear_endpoint_config; then
        echo "Cache cleared. Next run will perform fresh endpoint detection."
    fi
    
    # If we're only clearing cache, exit here unless other operations requested
    if [[ "$DRY_RUN" == "false" ]] && [[ "$ENDPOINT" == "auto" ]]; then
        echo "Use --dry-run to test endpoint detection after cache clear."
        exit 0
    fi
fi

# Build the final endpoint URL with auto-detection if needed
FINAL_ENDPOINT=$(build_endpoint_url "$ENDPOINT" "$FR24_SERVICE_NAME")

# Validate endpoint URL
if [[ ! "$FINAL_ENDPOINT" =~ ^https?:// ]]; then
    log_message "ERROR" "Invalid endpoint URL: $FINAL_ENDPOINT"
    log_message "ERROR" "URL must start with http:// or https://"
    exit 1
fi

# Validate threshold is a number
if [[ ! "$TRACKED_THRESHOLD" =~ ^[0-9]+$ ]]; then
    log_message "ERROR" "Invalid threshold value: $TRACKED_THRESHOLD"
    log_message "ERROR" "Threshold must be a non-negative integer"
    exit 1
fi

# Validate log rotation parameters
if [[ ! "$MAX_LOG_SIZE_MB" =~ ^[0-9]+$ ]] || [[ "$MAX_LOG_SIZE_MB" -lt 1 ]]; then
    log_message "ERROR" "Invalid max log size: $MAX_LOG_SIZE_MB"
    log_message "ERROR" "Max log size must be a positive integer (MB)"
    exit 1
fi

if [[ ! "$MAX_LOG_FILES" =~ ^[0-9]+$ ]] || [[ "$MAX_LOG_FILES" -lt 1 ]]; then
    log_message "ERROR" "Invalid max log files: $MAX_LOG_FILES"
    log_message "ERROR" "Max log files must be a positive integer"
    exit 1
fi

# Validate service name
if [[ -z "$FR24_SERVICE_NAME" ]]; then
    log_message "ERROR" "Service name cannot be empty"
    exit 1
fi

# Main execution
main() {
    # Check dependencies
    check_dependencies
    
    # Create log directory if it doesn't exist
    local log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]] && [[ -w "$(dirname "$log_dir")" ]]; then
        mkdir -p "$log_dir"
    fi
    
    # Run monitoring
    monitor_fr24 "$FINAL_ENDPOINT"
    
    # Cleanup temporary files
    rm -f "$HOME/.fr24_log_rotated_$$" 2>/dev/null || true
}

# Execute main function
main "$@"
