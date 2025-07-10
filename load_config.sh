#!/bin/bash

# Configuration loader for FR24 Monitor
# This script loads configuration values from config.json and makes them available as environment variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Function to load configuration from JSON file
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Warning: Config file not found: $CONFIG_FILE" >&2
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required to parse configuration file" >&2
        echo "Install with: sudo apt-get install jq" >&2
        return 1
    fi
    
    # Read and parse JSON configuration
    local config_data=$(cat "$CONFIG_FILE")
    
    # Export monitoring settings
    export FR24_CHECK_INTERVAL=$(echo "$config_data" | jq -r '.monitoring.check_interval_minutes // 10')
    export FR24_AIRCRAFT_THRESHOLD=$(echo "$config_data" | jq -r '.monitoring.aircraft_threshold // 30')
    export FR24_MINIMUM_UPTIME_HOURS=$(echo "$config_data" | jq -r '.monitoring.minimum_uptime_hours // 2')
    export FR24_ENDPOINT_TIMEOUT=$(echo "$config_data" | jq -r '.monitoring.endpoint_timeout_seconds // 10')
    export FR24_RETRY_ATTEMPTS=$(echo "$config_data" | jq -r '.monitoring.retry_attempts // 3')
    export FR24_RETRY_DELAY=$(echo "$config_data" | jq -r '.monitoring.retry_delay_seconds // 5')
    export FR24_ENDPOINT_URL=$(echo "$config_data" | jq -r '.monitoring.endpoint_url // "http://localhost:8754/monitor.json"')
    
    # Export reboot settings
    export FR24_REBOOT_ENABLED=$(echo "$config_data" | jq -r '.reboot.enabled // true')
    export FR24_DRY_RUN_MODE=$(echo "$config_data" | jq -r '.reboot.dry_run_mode // false')
    export FR24_REBOOT_DELAY=$(echo "$config_data" | jq -r '.reboot.reboot_delay_seconds // 300')
    export FR24_SEND_EMAIL_ALERTS=$(echo "$config_data" | jq -r '.reboot.send_email_alerts // true')
    
    # Export logging settings
    export FR24_LOG_LEVEL=$(echo "$config_data" | jq -r '.logging.log_level // "INFO"')
    export FR24_MAX_LOG_SIZE_MB=$(echo "$config_data" | jq -r '.logging.max_log_size_mb // 2')
    export FR24_KEEP_LOG_FILES=$(echo "$config_data" | jq -r '.logging.keep_log_files // 2')
    export FR24_DATABASE_RETENTION_DAYS=$(echo "$config_data" | jq -r '.logging.database_retention_days // 365')
    export FR24_VERBOSE_OUTPUT=$(echo "$config_data" | jq -r '.logging.verbose_output // false')
    
    # Export web settings
    export FR24_WEB_PORT=$(echo "$config_data" | jq -r '.web.port // 6869')
    export FR24_AUTO_REFRESH_SECONDS=$(echo "$config_data" | jq -r '.web.auto_refresh_seconds // 60')
    export FR24_MAX_REBOOT_HISTORY=$(echo "$config_data" | jq -r '.web.max_reboot_history // 50')
    export FR24_TIMEZONE=$(echo "$config_data" | jq -r '.web.timezone // "Europe/London"')
    
    # Export system settings
    export FR24_SERVICE_NAME=$(echo "$config_data" | jq -r '.system.service_name // "fr24feed"')
    export FR24_SERVICE_RESTART_ENABLED=$(echo "$config_data" | jq -r '.system.service_restart_enabled // true')
    export FR24_SERVICE_RESTART_DELAY=$(echo "$config_data" | jq -r '.system.service_restart_delay_seconds // 30')
    export FR24_CHECK_DISK_SPACE=$(echo "$config_data" | jq -r '.system.check_disk_space // true')
    export FR24_MIN_DISK_SPACE_GB=$(echo "$config_data" | jq -r '.system.min_disk_space_gb // 1')
    
    # Export notification settings
    export FR24_EMAIL_ENABLED=$(echo "$config_data" | jq -r '.notifications.email_enabled // false')
    export FR24_WEBHOOK_ENABLED=$(echo "$config_data" | jq -r '.notifications.webhook_enabled // false')
    export FR24_WEBHOOK_URL=$(echo "$config_data" | jq -r '.notifications.webhook_url // ""')
    export FR24_NOTIFICATION_COOLDOWN_MINUTES=$(echo "$config_data" | jq -r '.notifications.notification_cooldown_minutes // 60')
    
    # Export email settings
    export FR24_EMAIL_SMTP_HOST=$(echo "$config_data" | jq -r '.email.smtp_host // ""')
    export FR24_EMAIL_SMTP_PORT=$(echo "$config_data" | jq -r '.email.smtp_port // 587')
    export FR24_EMAIL_SMTP_SECURITY=$(echo "$config_data" | jq -r '.email.smtp_security // "tls"')
    export FR24_EMAIL_SMTP_USERNAME=$(echo "$config_data" | jq -r '.email.smtp_username // ""')
    export FR24_EMAIL_SMTP_PASSWORD=$(echo "$config_data" | jq -r '.email.smtp_password // ""')
    export FR24_EMAIL_FROM_EMAIL=$(echo "$config_data" | jq -r '.email.from_email // ""')
    export FR24_EMAIL_FROM_NAME=$(echo "$config_data" | jq -r '.email.from_name // "FR24 Monitor"')
    export FR24_EMAIL_TO_EMAIL=$(echo "$config_data" | jq -r '.email.to_email // ""')
    export FR24_EMAIL_SUBJECT=$(echo "$config_data" | jq -r '.email.subject // "FR24 Monitor Alert: System Reboot Required"')
    
    return 0
}

# Function to get a specific config value
get_config_value() {
    local key="$1"
    local default_value="$2"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default_value"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "$default_value"
        return 1
    fi
    
    local value=$(cat "$CONFIG_FILE" | jq -r ".$key // \"$default_value\"")
    echo "$value"
}

# Function to update a config value
update_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Config file not found: $CONFIG_FILE" >&2
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required to update configuration" >&2
        return 1
    fi
    
    # Create a backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    
    # Update the value
    local temp_file=$(mktemp)
    cat "$CONFIG_FILE" | jq ".$key = \"$value\"" > "$temp_file"
    
    if [[ $? -eq 0 ]]; then
        mv "$temp_file" "$CONFIG_FILE"
        echo "Updated $key to $value"
        return 0
    else
        echo "Error: Failed to update configuration" >&2
        rm -f "$temp_file"
        return 1
    fi
}

# Function to check if jq is available and install if needed
ensure_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "Installing jq for JSON parsing..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y jq
        else
            echo "Error: Cannot install jq automatically. Please install it manually." >&2
            return 1
        fi
    fi
    return 0
}

# If this script is run directly, load the config
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Loading FR24 Monitor configuration..."
    if ensure_jq && load_config; then
        echo "Configuration loaded successfully!"
        echo "Available environment variables:"
        env | grep "^FR24_" | sort
    else
        echo "Failed to load configuration" >&2
        exit 1
    fi
fi
