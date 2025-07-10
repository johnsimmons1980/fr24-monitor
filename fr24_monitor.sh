#!/bin/bash

# FR24 Server Monitor Script
# Monitors aircraft tracking status and reboots server if tracking drops to 0
# Usage: ./fr24_monitor.sh [--dry-run] [--endpoint URL] [--help]

set -euo pipefail

# Get script directory for portable paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from config file
if [[ -f "$SCRIPT_DIR/load_config.sh" ]]; then
    source "$SCRIPT_DIR/load_config.sh"
    if load_config; then
        # Use config values with fallback to defaults
        DEFAULT_ENDPOINT="${FR24_ENDPOINT_URL:-http://localhost:8754/monitor.json}"
        TRACKED_THRESHOLD="${FR24_AIRCRAFT_THRESHOLD:-0}"

        DRY_RUN="${FR24_DRY_RUN_MODE:-false}"
        VERBOSE="${FR24_VERBOSE_OUTPUT:-false}"
        LOG_FILE="$SCRIPT_DIR/fr24_monitor.log"
        MAX_LOG_SIZE_MB="${FR24_MAX_LOG_SIZE_MB:-2}"
        MAX_LOG_FILES="${FR24_KEEP_LOG_FILES:-2}"
        FR24_SERVICE_NAME="${FR24_SERVICE_NAME:-fr24feed}"
        ENDPOINT_TIMEOUT="${FR24_ENDPOINT_TIMEOUT:-10}"
        RETRY_ATTEMPTS="${FR24_RETRY_ATTEMPTS:-3}"
        RETRY_DELAY="${FR24_RETRY_DELAY:-5}"
        REBOOT_DELAY_SECONDS="${FR24_REBOOT_DELAY:-300}"
        SEND_EMAIL_ALERTS="${FR24_SEND_EMAIL_ALERTS:-true}"
        REBOOT_ENABLED="${FR24_REBOOT_ENABLED:-true}"
    else
        echo "Warning: Could not load configuration file, using defaults"
    fi
else
    echo "Warning: Configuration loader not found, using defaults"
fi

# Default configuration (fallback if config loading fails)
DEFAULT_ENDPOINT="${DEFAULT_ENDPOINT:-http://localhost:8754/monitor.json}"
TRACKED_THRESHOLD="${TRACKED_THRESHOLD:-0}"

DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/fr24_monitor.log}"
CONFIG_FILE="$SCRIPT_DIR/.fr24_monitor_config"
MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-2}"
MAX_LOG_FILES="${MAX_LOG_FILES:-2}"
FR24_SERVICE_NAME="${FR24_SERVICE_NAME:-fr24feed}"
ENDPOINT_TIMEOUT="${ENDPOINT_TIMEOUT:-10}"
RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"
REBOOT_DELAY_SECONDS="${REBOOT_DELAY_SECONDS:-300}"
SEND_EMAIL_ALERTS="${SEND_EMAIL_ALERTS:-true}"
REBOOT_ENABLED="${REBOOT_ENABLED:-true}"

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
    --endpoint URL           FR24 monitoring endpoint URL
                             (default: $DEFAULT_ENDPOINT)
    --dry-run                Run in dry-run mode (don't actually reboot)
    --verbose                Enable verbose output
    --log-file FILE          Log file path (default: $LOG_FILE)
    --threshold NUM          Reboot threshold - reboot if tracked <= NUM (default: $TRACKED_THRESHOLD)
    --max-log-size MB        Maximum log file size in MB before rotation (default: $MAX_LOG_SIZE_MB)
    --max-log-files N        Maximum number of rotated log files to keep (default: $MAX_LOG_FILES)
    --service-name NAME      FR24 service name to restart if endpoint fails (default: fr24feed)
    --help                   Show this help message

CONFIGURATION:
    Default endpoint: $DEFAULT_ENDPOINT
    Default log file: $LOG_FILE
    Default config file: $CONFIG_FILE
    Default reboot threshold: tracked <= $TRACKED_THRESHOLD
    Default max log size: $MAX_LOG_SIZE_MB MB
    Default max log files: $MAX_LOG_FILES files
    Default service name: $FR24_SERVICE_NAME

Examples:
    $0 --dry-run                                    # Test with default endpoint
    $0 --endpoint http://192.168.1.100:8754/monitor.json --dry-run  # Test with custom endpoint
    $0 --verbose                                    # Production mode with verbose output
    $0 --threshold 50 --dry-run                    # Test reboot logic when tracked <= 50
    $0 --threshold 200 --dry-run --verbose         # Test with high threshold to trigger reboot
    $0 --max-log-size 5 --max-log-files 3          # Rotate logs at 5MB, keep 3 files
    $0 --service-name piaware --dry-run            # Monitor PiAware feeder service

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
    local start_time=$(date +%s%3N)  # milliseconds
    
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
            start_time=$(date +%s%3N)  # Reset timer for retry
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
    
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    log_message "INFO" "Successfully fetched data from FR24 endpoint (${response_time}ms)" >&2
    
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
    
    echo "$tracked,$uploaded,$response_time,$feed_status,$feed_server"
    return 0
}

# Function to reboot the server
reboot_server() {
    local reason="$1"
    local tracked="${2:-0}"
    local endpoint="${3:-unknown}"
    
    # Get current uptime for logging purposes only
    local uptime_hours=$(get_uptime_hours)
    log_message "INFO" "Current system uptime: $uptime_hours hours"
    
    # Log reboot event to database
    log_reboot_event "$tracked" "$TRACKED_THRESHOLD" "$uptime_hours" "$reason" "$DRY_RUN" "false" "false" "$endpoint"
    
    log_message "REBOOT" "$reason"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "DRY RUN: Would reboot server now"
        log_message "INFO" "DRY RUN: Command that would be executed: sudo reboot"
        
        # Test email alert in dry run mode
        local email_subject="FR24 Monitor Alert: System Reboot Would Be Initiated (DRY RUN)"
        local email_message=$(create_reboot_email_message "DRY RUN - $reason" "$tracked" "$TRACKED_THRESHOLD" "$uptime_hours" "$endpoint")
        email_message="*** THIS IS A DRY RUN TEST - NO ACTUAL REBOOT WILL OCCUR ***

$email_message

This is a test of the email alert system. In a real scenario, the system would be rebooted now."
        
        log_message "INFO" "Testing email alert system..."
        if send_email_alert "$email_subject" "$email_message"; then
            log_message "SUCCESS" "DRY RUN: Email alert test completed successfully"
        else
            log_message "WARN" "DRY RUN: Email alert test failed"
        fi
        
        return 0
    fi
    
    log_message "REBOOT" "Initiating server reboot..."
    
    # Send email alert before rebooting (only if not dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        local email_subject="FR24 Monitor Alert: System Reboot Initiated"
        local email_message=$(create_reboot_email_message "$reason" "$tracked" "$TRACKED_THRESHOLD" "$uptime_hours" "$endpoint")
        
        log_message "INFO" "Sending reboot alert email..."
        local email_sent=false
        local email_attempts=0
        local max_email_attempts=3
        
        # Try to send email with retries
        while [[ "$email_attempts" -lt "$max_email_attempts" ]] && [[ "$email_sent" == "false" ]]; do
            email_attempts=$((email_attempts + 1))
            log_message "INFO" "Email attempt $email_attempts of $max_email_attempts..."
            
            if send_email_alert "$email_subject" "$email_message"; then
                log_message "SUCCESS" "Email alert sent successfully on attempt $email_attempts"
                email_sent=true
                
                # Wait additional time to ensure email is fully processed
                log_message "INFO" "Waiting 10 seconds to ensure email delivery completes..."
                sleep 10
            else
                log_message "WARN" "Email attempt $email_attempts failed"
                if [[ "$email_attempts" -lt "$max_email_attempts" ]]; then
                    log_message "INFO" "Retrying email in 5 seconds..."
                    sleep 5
                fi
            fi
        done
        
        if [[ "$email_sent" == "false" ]]; then
            log_message "ERROR" "Failed to send email alert after $max_email_attempts attempts"
            log_message "WARN" "Consider checking email configuration before proceeding with reboot"
            
            # Still proceed with reboot, but log the failure prominently
            log_message "REBOOT" "Proceeding with reboot despite email failure - manual notification may be required"
        fi
    fi
    
    # Check if we have reboot permissions
    if ! sudo -n reboot &>/dev/null; then
        log_message "ERROR" "No permission to reboot. Please run with sudo or configure passwordless sudo for reboot command"
        return 1
    fi
    
    # Final delay for any remaining processes to complete
    log_message "INFO" "Final system preparation before reboot..."
    sleep 5
    
    # Log the actual reboot command being executed
    log_message "REBOOT" "Executing: sudo reboot"
    sudo reboot
}

# Database logging configuration
DATABASE_FILE="$SCRIPT_DIR/fr24_monitor.db"

# Function to log monitoring data to database
log_to_database() {
    local table="$1"
    local data="$2"
    
    # Only log to database if it exists
    if [[ ! -f "$DATABASE_FILE" ]]; then
        return 0
    fi
    
    # Check if sqlite3 is available
    if ! command -v sqlite3 &> /dev/null; then
        return 0
    fi
    
    # Execute the SQL safely
    echo "$data" | sqlite3 "$DATABASE_FILE" 2>/dev/null || true
}

# Function to log reboot event to database
log_reboot_event() {
    local tracked="$1"
    local threshold="$2"
    local uptime_hours="$3"
    local reason="$4"
    local dry_run="$5"
    local service_restart_attempted="$6"
    local service_restart_successful="$7"
    local endpoint="$8"
    
    local system_info="$(uname -a)"
    local dry_run_flag=$([ "$dry_run" == "true" ] && echo 1 || echo 0)
    local restart_attempted_flag=$([ "$service_restart_attempted" == "true" ] && echo 1 || echo 0)
    local restart_successful_flag=$([ "$service_restart_successful" == "true" ] && echo 1 || echo 0)
    
    local sql="INSERT INTO reboot_events (tracked_aircraft, threshold, uptime_hours, reason, dry_run, service_restart_attempted, service_restart_successful, endpoint, system_info) VALUES ($tracked, $threshold, $uptime_hours, '$reason', $dry_run_flag, $restart_attempted_flag, $restart_successful_flag, '$endpoint', '$system_info');"
    
    log_to_database "reboot_events" "$sql"
}

# Function to log monitoring stats to database
log_monitoring_stats() {
    local tracked="$1"
    local uploaded="$2"
    local endpoint="$3"
    local response_time="$4"
    local feed_status="$5"
    local feed_server="$6"
    
    # Replace N/A with NULL for database
    uploaded=$([ "$uploaded" == "N/A" ] && echo "NULL" || echo "$uploaded")
    
    local sql="INSERT INTO monitoring_stats (tracked_aircraft, uploaded_aircraft, endpoint, response_time_ms, feed_status, feed_server) VALUES ($tracked, $uploaded, '$endpoint', $response_time, '$feed_status', '$feed_server');"
    
    log_to_database "monitoring_stats" "$sql"
}

# Function to log monitoring result to database
log_monitoring_result() {
    local check_status="$1"
    local tracked="$2"
    local threshold="$3"
    local uptime_hours="$4"
    
    local sql="INSERT INTO system_status (check_status, tracked_aircraft, threshold, uptime_hours) VALUES ('$check_status', $tracked, $threshold, $uptime_hours);"
    
    log_to_database "system_status" "$sql"
}

# Email configuration and helper functions
EMAIL_CONFIG_FILE="$SCRIPT_DIR/email_config.json"
EMAIL_HELPER_SCRIPT="$SCRIPT_DIR/send_email.sh"

# Function to send email alert for reboot events
send_email_alert() {
    local subject="$1"
    local message="$2"
    
    # Check if email helper script exists
    if [[ ! -f "$EMAIL_HELPER_SCRIPT" ]]; then
        log_message "WARN" "Email helper script not found: $EMAIL_HELPER_SCRIPT"
        return 1
    fi
    
    # Check if email helper script is executable
    if [[ ! -x "$EMAIL_HELPER_SCRIPT" ]]; then
        log_message "INFO" "Making email helper script executable..."
        chmod +x "$EMAIL_HELPER_SCRIPT" 2>/dev/null || {
            log_message "WARN" "Could not make email helper script executable"
            return 1
        }
    fi
    
    # Try to send email using the helper script
    log_message "INFO" "Attempting to send email alert..."
    local email_output
    if email_output=$(bash "$EMAIL_HELPER_SCRIPT" "$subject" "$message" 2>&1); then
        log_message "SUCCESS" "Email alert sent successfully"
        return 0
    else
        log_message "WARN" "Failed to send email alert: $email_output"
        return 1
    fi
}

# Function to create a detailed reboot email message
create_reboot_email_message() {
    local reason="$1"
    local tracked="${2:-0}"
    local threshold="${3:-0}"
    local uptime_hours="${4:-0}"
    local endpoint="${5:-unknown}"
    
    local hostname=$(hostname)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local system_load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    cat << EOF
FR24 Monitor System Alert

SYSTEM REBOOT INITIATED

Timestamp: $timestamp
Hostname: $hostname
Reason: $reason

MONITORING DETAILS:
- Aircraft Tracked: $tracked
- Alert Threshold: $threshold
- System Uptime: $uptime_hours hours
- Monitoring Endpoint: $endpoint

SYSTEM INFORMATION:
- System Load: $system_load
- Timezone: $(date '+%Z %z')

The FR24 monitoring system has detected that aircraft tracking has dropped below the configured threshold and has initiated a system reboot to restore service.

This is an automated alert from the FR24 Monitor system.
EOF
}

# Main monitoring function
monitor_fr24() {
    local endpoint="$1"
    
    log_message "INFO" "Starting FR24 monitoring check"
    
    # Get current uptime for system status logging
    local current_uptime=$(get_uptime_hours)
    
    # Show current uptime in verbose mode only
    if [[ "$VERBOSE" == "true" ]]; then
        log_message "INFO" "Current system uptime: $current_uptime hours"
    fi
    
    # Log monitoring result to database periodically (only if not dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        # We'll log the result after we know if it's successful or not
        local temp_log_status="UNKNOWN"
    fi
    
    # Get current stats
    local stats_result
    if ! stats_result=$(get_fr24_stats "$endpoint"); then
        log_message "ERROR" "Failed to get FR24 statistics - monitoring check failed"
        
        # Log failure to database (only if not dry run)
        if [[ "$DRY_RUN" == "false" ]]; then
            log_monitoring_result "FAILED" "0" "$TRACKED_THRESHOLD" "$current_uptime"
        fi
        
        exit 1
    fi
    
    # Parse the extended stats format: tracked,uploaded,response_time,feed_status,feed_server
    IFS=',' read -r tracked uploaded response_time feed_status feed_server <<< "$stats_result"
    
    log_message "INFO" "Aircraft tracked: $tracked, uploaded: $uploaded"
    
    # Log monitoring stats to database (only if not dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        log_monitoring_stats "$tracked" "$uploaded" "$endpoint" "$response_time" "$feed_status" "$feed_server"
    fi
    
    # Check if we need to reboot
    if [[ "$tracked" -le "$TRACKED_THRESHOLD" ]]; then
        log_message "WARN" "ALERT: Aircraft tracking has dropped to critical level!"
        log_message "WARN" "Current tracked: $tracked (threshold: $TRACKED_THRESHOLD)"
        
        # Log critical status to database (only if not dry run)
        if [[ "$DRY_RUN" == "false" ]]; then
            log_monitoring_result "CRITICAL" "$tracked" "$TRACKED_THRESHOLD" "$current_uptime"
        fi
        
        local reason="Aircraft tracking has dropped to $tracked (threshold: $TRACKED_THRESHOLD). Rebooting server."
        if reboot_server "$reason" "$tracked" "$endpoint"; then
            log_message "INFO" "Reboot action completed successfully"
            exit 0  # Successful reboot or dry-run
        else
            log_message "WARN" "Reboot failed or was not permitted"
            log_message "INFO" "Will continue monitoring - next check may attempt reboot again"
        fi
    else
        log_message "SUCCESS" "Aircraft tracking healthy ($tracked aircraft tracked)"
        
        # Log success status to database (only if not dry run)
        if [[ "$DRY_RUN" == "false" ]]; then
            log_monitoring_result "SUCCESS" "$tracked" "$TRACKED_THRESHOLD" "$current_uptime"
        fi
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_message "INFO" "Monitoring check completed at $(date)"
    fi
}

# Parse command line arguments
ENDPOINT=""

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

# Use configured endpoint or default
if [[ -z "$ENDPOINT" ]]; then
    FINAL_ENDPOINT="$DEFAULT_ENDPOINT"
else
    FINAL_ENDPOINT="$ENDPOINT"
fi

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
