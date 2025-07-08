#!/bin/bash

# FR24 Monitor Management Script
# Usage: ./fr24_manager.sh [install|uninstall|status|edit|test|preview|help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_FILE="$SCRIPT_DIR/fr24_monitor.cron"
MONITOR_SCRIPT="$SCRIPT_DIR/fr24_monitor.sh"
LOGROTATE_FILE="$SCRIPT_DIR/fr24_logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/fr24_monitor"

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

# Main function
main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            install_cron
            install_logrotate
            ;;
        "uninstall")
            uninstall_cron
            uninstall_logrotate
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
        "help"|*)
            local log_file=$(get_log_file_path)
            cat << EOF
FR24 Monitor Management Tool

Usage: $0 [command]

DESCRIPTION:
    Complete management tool for the FR24 monitoring system. Handles installation,
    configuration, testing, monitoring, and removal of all components.

COMMANDS:
    install     Install FR24 monitor crontab and logrotate configuration
    uninstall   Remove FR24 monitor from crontab and remove logrotate config
    status      Show current system status, cron jobs, logs, and logrotate config
    edit        Edit crontab manually
    test        Test the monitor script in dry-run mode
    preview     Show the cron and logrotate entries that would be installed
    help        Show this help message

EXAMPLES:
    $0 preview      # Preview what will be installed
    $0 install      # Install complete monitoring system
    $0 status       # Check if monitoring is running
    $0 test         # Test the monitoring script safely
    $0 uninstall    # Remove complete monitoring system

FILES:
    Monitor script: $MONITOR_SCRIPT
    Cron template:  $CRON_FILE
    Logrotate template: $LOGROTATE_FILE
    Log file:       $log_file

INSTALLATION LOCATIONS:
    Cron entries: User's crontab
    Logrotate config: $LOGROTATE_DEST

EOF
            ;;
    esac
}

# Execute main function
main "$@"
