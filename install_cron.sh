#!/bin/bash

# FR24 Monitor Crontab Management Script
# Usage: ./install_cron.sh [install|uninstall|status|edit]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_FILE="$SCRIPT_DIR/fr24_monitor.cron"
MONITOR_SCRIPT="$SCRIPT_DIR/fr24_monitor.sh"

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
    
    # Add new cron entries
    (crontab -l 2>/dev/null; grep -v "^#" "$CRON_FILE" | grep -v "^$") | crontab -
    
    if [[ $? -eq 0 ]]; then
        local log_file=$(get_log_file_path)
        print_status "SUCCESS" "FR24 monitor crontab installed successfully"
        print_status "INFO" "The monitor will run every 10 minutes"
        print_status "INFO" "Check logs at: $log_file"
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
}

# Function to edit crontab
edit_cron() {
    print_status "INFO" "Opening crontab for editing..."
    crontab -e
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

# Main function
main() {
    local action="${1:-help}"
    
    case "$action" in
        "install")
            install_cron
            ;;
        "uninstall")
            uninstall_cron
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
        "help"|*)
            local log_file=$(get_log_file_path)
            cat << EOF
FR24 Monitor Crontab Management

Usage: $0 [command]

Commands:
    install     Install FR24 monitor crontab (runs every 10 minutes)
    uninstall   Remove FR24 monitor from crontab
    status      Show current crontab status and log info
    edit        Edit crontab manually
    test        Test the monitor script in dry-run mode
    help        Show this help message

Examples:
    $0 install      # Install the cron job
    $0 status       # Check if it's running
    $0 test         # Test the script
    $0 uninstall    # Remove the cron job

Files:
    Monitor script: $MONITOR_SCRIPT
    Cron template:  $CRON_FILE
    Log file:       $log_file

EOF
            ;;
    esac
}

# Execute main function
main "$@"
