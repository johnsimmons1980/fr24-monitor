# FR24 Monitor Configuration System

## Overview

The FR24 Monitor system now uses a unified configuration system that consolidates all settings into a single `config.json` file. This configuration can be managed through the web interface, making it easy to adjust monitoring parameters, thresholds, and system behavior without editing scripts directly.

## Configuration File

The main configuration file is located at `/home/john/fr24-mon/config.json` and contains all system settings organized into logical sections:

### Configuration Sections

1. **Monitoring Settings** - Core monitoring parameters
2. **Endpoint Settings** - FR24 feeder endpoint configuration
3. **Reboot Settings** - Automatic reboot behavior
4. **Logging Settings** - Log management and retention
5. **Web Settings** - Dashboard configuration
6. **System Settings** - Service and system monitoring
7. **Notification Settings** - Alert configuration
8. **Email Settings** - SMTP and email alert settings

## Web Interface

### Settings Page

Access the settings page at `http://localhost:6869/settings.php` to:

- View and edit all configuration parameters
- See real-time configuration file status
- Reset settings to defaults
- Get contextual help for each setting

### Navigation

- **Dashboard** (`/`) - Main monitoring dashboard
- **Settings** (`/settings.php`) - Unified configuration page
- **Email Configuration** (`/config.php`) - Legacy email settings (deprecated)
- **Logs** (`/logs.php`) - Detailed log viewer

## Key Features

### Real-time Updates

- Changes made through the web interface take effect on the next monitoring cycle
- No need to restart services for most settings
- Configuration file is automatically validated and backed up

### Comprehensive Settings

The new configuration system includes settings for:

- **Aircraft Threshold** - Minimum aircraft count before triggering actions
- **Uptime Limits** - Maximum and minimum uptime before reboots
- **Endpoint Configuration** - Primary and fallback FR24 endpoints
- **Retry Logic** - Timeout, retry attempts, and delays
- **Logging** - Log levels, file sizes, and retention
- **Email Alerts** - Complete SMTP configuration
- **Web Dashboard** - Port, refresh rates, and display settings

### Backward Compatibility

The system maintains backward compatibility with existing configurations while providing enhanced functionality.

## Technical Implementation

### Configuration Loading

The `load_config.sh` script handles:

- JSON parsing using `jq`
- Environment variable export
- Default value fallbacks
- Error handling for missing dependencies

### Script Integration

Both `fr24_monitor.sh` and `fr24_manager.sh` automatically:

- Load configuration on startup
- Use config values with sensible defaults
- Handle missing or invalid configuration gracefully

### Web Interface

The PHP-based web interface provides:

- Form-based configuration editing
- Real-time validation
- Success/error feedback
- Configuration file status information

## Usage Examples

### Updating Aircraft Threshold

1. Navigate to `http://localhost:6869/settings.php`
2. Find "Aircraft Threshold" under "Monitoring Settings"
3. Change the value (e.g., from 30 to 25)
4. Click "Save Settings"
5. Changes take effect on the next monitoring cycle

### Configuring Email Alerts

1. Open the Settings page
2. Scroll to "Email Settings"
3. Configure SMTP settings:
   - SMTP Host (e.g., smtp.gmail.com)
   - SMTP Port (usually 587 for TLS)
   - Username and password
   - From/To email addresses
4. Save settings
5. Test email functionality

### Command Line Configuration

View current configuration:
```bash
./load_config.sh
```

Check specific values:
```bash
cat config.json | jq '.monitoring.aircraft_threshold'
```

## Configuration Parameters

### Monitoring Settings

- `check_interval_minutes` - How often to check FR24 status (default: 10)
- `aircraft_threshold` - Minimum aircraft count (default: 30)
- `uptime_limit_hours` - Maximum uptime before reboot (default: 48)
- `minimum_uptime_hours` - Minimum uptime before allowing reboot (default: 2)
- `endpoint_timeout_seconds` - HTTP timeout (default: 10)
- `retry_attempts` - Number of retries (default: 3)
- `retry_delay_seconds` - Delay between retries (default: 5)

### Reboot Settings

- `enabled` - Enable automatic reboots (default: true)
- `dry_run_mode` - Test mode without actual reboot (default: false)
- `reboot_delay_seconds` - Delay before reboot (default: 300)
- `force_reboot_after_hours` - Force reboot after time limit (default: 72)

### Logging Settings

- `log_level` - Minimum log level (default: INFO)
- `max_log_size_mb` - Maximum log file size (default: 2)
- `keep_log_files` - Number of rotated logs to keep (default: 2)
- `database_retention_days` - Database record retention (default: 365)

### Web Settings

- `port` - Web server port (default: 6869)
- `auto_refresh_seconds` - Dashboard refresh interval (default: 60)
- `max_reboot_history` - Maximum reboot events to display (default: 50)
- `timezone` - Display timezone (default: Europe/London)

## Troubleshooting

### Configuration Not Loading

1. Ensure `jq` is installed: `sudo apt-get install jq`
2. Check configuration file exists: `ls -la config.json`
3. Validate JSON syntax: `cat config.json | jq .`
4. Check file permissions: `ls -la config.json`

### Web Interface Issues

1. Ensure web server is running: `./fr24_manager.sh status`
2. Check file permissions on config.json
3. Verify PHP has write access to the config file
4. Check web server logs: `tail -f lighttpd_error.log`

### Settings Not Taking Effect

1. Settings take effect on the next monitoring cycle (usually within 10 minutes)
2. Some settings (like web port) require service restart
3. Check if configuration file was actually updated
4. Verify scripts are loading the configuration correctly

## Migration from Old Configuration

The system automatically migrates from the old configuration format:

1. Existing `email_config.json` settings are integrated
2. Hard-coded script values are replaced with config file values
3. Default values are applied for missing settings
4. Backward compatibility is maintained

## Security Considerations

- Configuration file contains sensitive information (SMTP passwords)
- Ensure proper file permissions (readable by monitoring user only)
- Consider using environment variables for sensitive data in production
- Web interface validates all input before saving

## Future Enhancements

Planned improvements include:

- Environment variable override support
- Configuration validation and schema checking
- Import/export functionality
- Configuration templates for different scenarios
- API endpoints for programmatic configuration
