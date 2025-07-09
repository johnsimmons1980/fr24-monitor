#!/bin/bash

# Email Helper Script for FR24 Monitor
# Sends email alerts using msmtp with configuration from JSON file
# Usage: ./send_email.sh "subject" "body" [recipient_override]

set -euo pipefail

# Get script directory for portable paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/email_config.json"
MSMTP_CONFIG="$HOME/.msmtprc"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] [EMAIL ERROR] $message${NC}" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [EMAIL WARN] $message${NC}" >&2
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] [EMAIL INFO] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$timestamp] [EMAIL SUCCESS] $message${NC}"
            ;;
        *)
            echo "[$timestamp] [EMAIL $level] $message"
            ;;
    esac
}

# Function to check and install required packages
check_dependencies() {
    local missing_packages=()
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        missing_packages+=("jq")
    fi
    
    # Check for msmtp
    if ! command -v msmtp &> /dev/null; then
        log_message "WARN" "msmtp not found, attempting to install..."
        missing_packages+=("msmtp")
    fi
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_message "WARN" "Missing required packages: ${missing_packages[*]}"
        log_message "INFO" "Attempting to install missing packages..."
        
        # Try to install packages
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            if sudo apt-get update && sudo apt-get install -y "${missing_packages[@]}"; then
                log_message "SUCCESS" "Successfully installed packages: ${missing_packages[*]}"
            else
                log_message "ERROR" "Failed to install packages. Please install manually: ${missing_packages[*]}"
                return 1
            fi
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS
            if sudo yum install -y "${missing_packages[@]}"; then
                log_message "SUCCESS" "Successfully installed packages: ${missing_packages[*]}"
            else
                log_message "ERROR" "Failed to install packages. Please install manually: ${missing_packages[*]}"
                return 1
            fi
        elif command -v dnf &> /dev/null; then
            # Fedora
            if sudo dnf install -y "${missing_packages[@]}"; then
                log_message "SUCCESS" "Successfully installed packages: ${missing_packages[*]}"
            else
                log_message "ERROR" "Failed to install packages. Please install manually: ${missing_packages[*]}"
                return 1
            fi
        else
            log_message "ERROR" "Package manager not recognized. Please install manually: ${missing_packages[*]}"
            return 1
        fi
    fi
    
    return 0
}

# Function to validate email configuration
validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_message "ERROR" "Email configuration file not found: $CONFIG_FILE"
        log_message "INFO" "Please configure email settings via the web interface at /config.php"
        return 1
    fi
    
    # Check if config file is valid JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log_message "ERROR" "Invalid JSON in configuration file: $CONFIG_FILE"
        return 1
    fi
    
    # Check required fields
    local required_fields=("smtp_host" "smtp_port" "smtp_user" "smtp_password" "from_email" "to_email" "enabled")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$CONFIG_FILE" >/dev/null 2>&1; then
            log_message "ERROR" "Missing required field '$field' in configuration file"
            return 1
        fi
    done
    
    # Check if email is enabled
    local enabled=$(jq -r '.enabled' "$CONFIG_FILE")
    if [[ "$enabled" != "true" ]]; then
        log_message "INFO" "Email alerts are disabled in configuration"
        return 2  # Special return code for disabled
    fi
    
    return 0
}

# Function to create msmtp configuration
create_msmtp_config() {
    local smtp_host=$(jq -r '.smtp_host' "$CONFIG_FILE")
    local smtp_port=$(jq -r '.smtp_port' "$CONFIG_FILE")
    local smtp_user=$(jq -r '.smtp_user' "$CONFIG_FILE")
    local smtp_password=$(jq -r '.smtp_password' "$CONFIG_FILE")
    local use_tls=$(jq -r '.use_tls // true' "$CONFIG_FILE")
    local use_starttls=$(jq -r '.use_starttls // true' "$CONFIG_FILE")
    
    log_message "INFO" "Creating msmtp configuration..."
    
    # Create msmtp config file
    cat > "$MSMTP_CONFIG" << EOF
# msmtp configuration for FR24 Monitor
defaults
auth           on
tls            $(if [[ "$use_tls" == "true" ]]; then echo "on"; else echo "off"; fi)
tls_starttls   $(if [[ "$use_starttls" == "true" ]]; then echo "on"; else echo "off"; fi)
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /tmp/msmtp.log

# Account for FR24 Monitor
account        fr24
host           $smtp_host
port           $smtp_port
from           $smtp_user
user           $smtp_user
password       $smtp_password

# Set default account
account default : fr24
EOF
    
    # Set proper permissions
    chmod 600 "$MSMTP_CONFIG"
    
    log_message "SUCCESS" "msmtp configuration created at: $MSMTP_CONFIG"
    log_message "INFO" "SMTP settings - Host: $smtp_host, Port: $smtp_port, User: $smtp_user, TLS: $use_tls"
}

# Function to send email
send_email() {
    local subject="$1"
    local body="$2"
    local recipient="${3:-}"
    
    # If no recipient override, get from config
    if [[ -z "$recipient" ]]; then
        recipient=$(jq -r '.to_email' "$CONFIG_FILE")
    fi
    
    local from_email=$(jq -r '.from_email' "$CONFIG_FILE")
    local from_name=$(jq -r '.from_name // "FR24 Monitor"' "$CONFIG_FILE")
    
    log_message "INFO" "Attempting to send email to: $recipient"
    log_message "INFO" "Subject: $subject"
    log_message "INFO" "From: $from_name <$from_email>"
    
    # Create email content
    local email_content
    email_content=$(cat << EOF
To: $recipient
From: $from_name <$from_email>
Subject: $subject
Content-Type: text/plain; charset=UTF-8

$body

--
This email was sent automatically by the FR24 Monitor system.
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Hostname: $(hostname)
EOF
)
    
    # Send email using msmtp
    log_message "INFO" "Executing msmtp command..."
    if echo "$email_content" | msmtp "$recipient" 2>&1; then
        log_message "SUCCESS" "Email sent successfully to $recipient"
        return 0
    else
        local msmtp_exit_code=$?
        log_message "ERROR" "Failed to send email to $recipient (exit code: $msmtp_exit_code)"
        
        # Check msmtp log for more details
        if [[ -f "/tmp/msmtp.log" ]]; then
            log_message "ERROR" "msmtp log contents:"
            cat "/tmp/msmtp.log" >&2
        fi
        
        return 1
    fi
}

# Function to print usage
usage() {
    cat << EOF
Usage: $0 "subject" "body" [recipient_override]

Send email alerts using msmtp with configuration from JSON file.

Arguments:
    subject             Email subject line
    body                Email body content
    recipient_override  Optional: override recipient email (uses config default if not provided)

Examples:
    $0 "FR24 Alert" "Server has been rebooted due to tracking failure"
    $0 "Test Email" "This is a test" "admin@example.com"

Configuration:
    Email settings are read from: $CONFIG_FILE
    Use the web interface (/config.php) to configure email settings.

Dependencies:
    - jq (for JSON parsing)
    - msmtp (for sending emails)
    These will be auto-installed if missing.
EOF
}

# Main script
main() {
    # Check arguments
    if [[ $# -lt 2 ]]; then
        echo "Error: Missing required arguments" >&2
        usage
        exit 1
    fi
    
    local subject="$1"
    local body="$2"
    local recipient="${3:-}"
    
    # Check for help flag
    if [[ "$subject" == "--help" ]] || [[ "$subject" == "-h" ]]; then
        usage
        exit 0
    fi
    
    log_message "INFO" "FR24 Monitor Email Helper starting..."
    
    # Check and install dependencies
    if ! check_dependencies; then
        log_message "ERROR" "Failed to install required dependencies"
        exit 1
    fi
    
    # Validate configuration
    local config_status
    validate_config
    config_status=$?
    
    if [[ $config_status -eq 1 ]]; then
        log_message "ERROR" "Email configuration validation failed"
        exit 1
    elif [[ $config_status -eq 2 ]]; then
        log_message "INFO" "Email alerts are disabled - skipping send"
        exit 0
    fi
    
    # Create msmtp configuration
    if ! create_msmtp_config; then
        log_message "ERROR" "Failed to create msmtp configuration"
        exit 1
    fi
    
    # Send the email
    if send_email "$subject" "$body" "$recipient"; then
        log_message "SUCCESS" "Email alert sent successfully"
        exit 0
    else
        log_message "ERROR" "Failed to send email alert"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
