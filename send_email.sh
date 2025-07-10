#!/bin/bash

# Email notification helper script for FR24 Monitor
# Usage: ./send_email.sh "subject" "message"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

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
    local enabled=$(jq -r '.email.enabled // false' "$CONFIG_FILE")
    if [[ "$enabled" != "true" ]]; then
        echo "Email alerts are disabled"
        return 0
    fi
    
    local smtp_host=$(jq -r '.email.smtp_host // ""' "$CONFIG_FILE")
    local smtp_port=$(jq -r '.email.smtp_port // 587' "$CONFIG_FILE")
    local smtp_security=$(jq -r '.email.smtp_security // "tls"' "$CONFIG_FILE")
    local smtp_username=$(jq -r '.email.smtp_username // ""' "$CONFIG_FILE")
    local smtp_password=$(jq -r '.email.smtp_password // ""' "$CONFIG_FILE")
    local from_email=$(jq -r '.email.from_email // ""' "$CONFIG_FILE")
    local from_name=$(jq -r '.email.from_name // "FR24 Monitor"' "$CONFIG_FILE")
    local to_email=$(jq -r '.email.to_email // ""' "$CONFIG_FILE")
    
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
    echo "Attempting to send email to: $to_email"
    echo "Using SMTP server: $smtp_host:$smtp_port"
    echo "From: $from_email"
    
    if echo "$email_content" | msmtp -C "$msmtp_config" "$to_email"; then
        echo "Email sent successfully to $to_email"
        
        # Check msmtp log for additional details
        if [[ -f "/tmp/msmtp.log" ]]; then
            echo "MSMTP Log (last 3 lines):"
            tail -3 /tmp/msmtp.log
        fi
        
        rm -f "$msmtp_config"
        return 0
    else
        echo "Failed to send email. Check /tmp/msmtp.log for details."
        
        # Show msmtp log for debugging
        if [[ -f "/tmp/msmtp.log" ]]; then
            echo "MSMTP Log contents:"
            cat /tmp/msmtp.log
        fi
        
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
