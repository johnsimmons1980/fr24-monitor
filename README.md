# FR24 Monitor - FlightRadar24 Feeder Monitoring and Auto-Restart

A robust monitoring system for FlightRadar24 feeders that automatically restarts services or reboots your system when aircraft tracking drops to critical levels.

## 🚀 TL;DR - Quick Setup (5 minutes)

**For beginners who just want to get it working:**

1. **Download the scripts to your Raspberry Pi:**
   ```bash
   cd ~
   git clone https://github.com/johnsimmons1980/fr24-monitor.git
   cd fr24-monitor
   ```

2. **Make sure you have the required tools:**
   ```bash
   sudo apt-get update
   sudo apt-get install curl jq
   ```

3. **Test that it works:**
   ```bash
   chmod +x fr24_manager.sh
   ./fr24_manager.sh test
   ```

4. **Install the monitoring (runs every 10 minutes):**
   ```bash
   ./fr24_manager.sh install
   ```

5. **Check it's working:**
   ```bash
   ./fr24_manager.sh status
   ```

**That's it!** Your FR24 feeder will now be monitored automatically. If aircraft tracking drops to 0, the system will:
- Try to restart the FR24 service first
- If that fails, reboot the server (but only if it's been running for 2+ hours)

Skip to the [Troubleshooting](#troubleshooting) section if you have issues.

---

## 📋 Table of Contents

- [What Does This Do?](#what-does-this-do)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration Options](#configuration-options)
- [Usage](#usage)
- [File Structure](#file-structure)
- [Monitoring and Logs](#monitoring-and-logs)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Uninstalling](#uninstalling)

---

## 🎯 What Does This Do?

This monitoring system keeps your FlightRadar24 feeder running smoothly by:

1. **Checking every 10 minutes** if your feeder is tracking aircraft
2. **If tracking drops to 0**, it tries to restart the FR24 service
3. **If the service restart fails**, it reboots your system
4. **Prevents restart loops** by only rebooting if the system has been up for 2+ hours
5. **Logs everything** so you can see what happened
6. **Automatically rotates logs** to prevent disk space issues

Think of it as a "watchdog" that makes sure your FR24 feeder never stays broken for long.

---

## ✨ Features

- **🔄 Automatic Service Recovery**: Tries restarting FR24 service before rebooting
- **⏰ Smart Timing**: Configurable monitoring intervals and uptime checks
- **📊 Intelligent Monitoring**: Checks actual aircraft tracking numbers, not just service status
- **🛡️ Safety Features**: Prevents restart loops with minimum uptime requirements
- **📝 Comprehensive Logging**: Detailed logs with automatic rotation
- **🎛️ Flexible Configuration**: Customizable thresholds, endpoints, and service names
- **🧪 Testing Tools**: Dry-run mode and validation commands
- **👥 User-Friendly**: Simple installation with helpful status reporting
- **🔧 Self-Contained**: All files in one directory, easily portable

---

## 📋 Requirements

- **Operating System**: Linux (tested on Raspberry Pi OS)
- **FlightRadar24 Feeder**: Running and accessible via HTTP
- **Required Tools**: `curl`, `jq`, `systemd` (usually pre-installed)
- **Permissions**: `sudo` access for service management and reboots

### Installing Required Tools

On Debian/Ubuntu/Raspberry Pi OS:
```bash
sudo apt-get update
sudo apt-get install curl jq
```

---

## 🚀 Installation

### Step 1: Download the Scripts

```bash
# Go to your home directory
cd ~

# Download from GitHub
git clone https://github.com/johnsimmons1980/fr24-monitor.git
cd fr24-monitor

# OR download as ZIP and extract
wget https://github.com/johnsimmons1980/fr24-monitor/archive/main.zip
unzip main.zip
cd fr24-monitor-main
```

### Step 2: Make Scripts Executable

```bash
chmod +x fr24_manager.sh fr24_monitor.sh
```

### Step 3: Test the Setup

```bash
# Preview what will be installed
./fr24_manager.sh preview

# Test the monitoring script
./fr24_manager.sh test
```

### Step 4: Install

```bash
# Install both cron job and log rotation
./fr24_manager.sh install
```

### Step 5: Verify Installation

```bash
# Check status
./fr24_manager.sh status

# View recent logs
tail -f fr24_monitor.log
```

---

## ⚙️ Configuration Options

### Main Script Options (`fr24_monitor.sh`)

| Option | Default | Description |
|--------|---------|-------------|
| `--endpoint URL` | `http://localhost:8754/monitor.json` | FR24 feeder monitoring endpoint |
| `--threshold NUM` | `0` | Reboot when tracked aircraft ≤ this number |
| `--min-uptime HOURS` | `2` | Minimum uptime before allowing reboot |
| `--service-name NAME` | `fr24feed` | Name of the FR24 service to restart |
| `--log-file FILE` | `./fr24_monitor.log` | Path to log file |
| `--max-log-size MB` | `2` | Max log file size before rotation |
| `--max-log-files NUM` | `2` | Number of rotated log files to keep |
| `--dry-run` | - | Test mode (don't actually reboot/restart) |
| `--verbose` | - | Show detailed output |

### Example Configurations

**Basic monitoring (default settings):**
```bash
./fr24_monitor.sh
```

**More sensitive monitoring (reboot if tracking ≤ 5):**
```bash
./fr24_monitor.sh --threshold 5
```

**Custom endpoint and service:**
```bash
./fr24_monitor.sh --endpoint http://192.168.1.100:8754/monitor.json --service-name piaware
```

**Verbose logging with larger log files:**
```bash
./fr24_monitor.sh --verbose --max-log-size 10 --max-log-files 5
```

---

## 🎮 Usage

### Management Commands

```bash
# Install monitoring
./fr24_manager.sh install

# Check status
./fr24_manager.sh status

# Test the monitor script
./fr24_manager.sh test

# Preview what would be installed
./fr24_manager.sh preview

# Validate log rotation setup
./fr24_manager.sh validate

# Remove monitoring
./fr24_manager.sh uninstall

# Get help
./fr24_manager.sh help
```

### Manual Testing

```bash
# Test with dry-run (safe testing)
./fr24_monitor.sh --dry-run --verbose

# Test with custom threshold
./fr24_monitor.sh --threshold 100 --dry-run

# Force immediate check
./fr24_monitor.sh --verbose
```

### Viewing Logs

```bash
# View recent activity
tail -20 fr24_monitor.log

# Watch logs in real-time
tail -f fr24_monitor.log

# View logs with timestamps
cat fr24_monitor.log | grep "$(date '+%Y-%m-%d')"
```

---

## 📁 File Structure

```
fr24-monitor/
├── fr24_monitor.sh           # Main monitoring script
├── fr24_monitor.cron         # Cron job template
├── fr24_logrotate.conf       # Log rotation template
├── fr24_manager.sh           # Installation and management script
├── README.md                 # This file
├── fr24_monitor.log          # Log file (created after first run)
└── crontab.backup           # Backup of your crontab (created during install)
```

### Generated Files

After installation, these files are created:
- **`/etc/logrotate.d/fr24_monitor`**: System log rotation config
- **User's crontab**: Contains the monitoring schedule
- **`fr24_monitor.log`**: Main log file in the script directory

---

## 📊 Monitoring and Logs

### Log File Format

```
[2025-07-08 15:30:00] [INFO] Starting FR24 monitoring check
[2025-07-08 15:30:01] [INFO] Aircraft tracked: 45, uploaded: 42
[2025-07-08 15:30:01] [SUCCESS] Aircraft tracking healthy (45 aircraft tracked)
```

### Log Levels

- **`SUCCESS`**: Everything working normally
- **`INFO`**: General information
- **`WARN`**: Warnings (but not critical)
- **`ERROR`**: Errors that need attention
- **`REBOOT`**: System reboot actions

### Monitoring Schedule

By default, the system checks every 10 minutes:
- `:00, :10, :20, :30, :40, :50` past each hour
- 144 checks per day
- Logs all activity for troubleshooting

### Log Rotation

Logs are automatically rotated when they reach 2MB:
- Keeps 2 old log files
- Compresses old logs to save space
- Prevents disk space issues

---

## 🔧 Troubleshooting

### Common Issues

**❌ "Missing required tools: curl jq"**
```bash
sudo apt-get update
sudo apt-get install curl jq
```

**❌ "Failed to fetch data from endpoint"**
- Check if FR24 feeder is running: `systemctl status fr24feed`
- Verify endpoint URL: `curl http://localhost:8754/monitor.json`
- Check firewall settings

**❌ "No permission to reboot"**
```bash
# Add sudo permissions for reboot
echo "$USER ALL=(ALL) NOPASSWD: /sbin/reboot" | sudo tee /etc/sudoers.d/fr24-monitor
```

**❌ Cron job not running**
```bash
# Check cron service
sudo systemctl status cron

# Check your crontab
crontab -l | grep fr24
```

**❌ System time issues (especially on Raspberry Pi)**
```bash
# Check current time and timezone
timedatectl status

# Enable NTP synchronization
sudo timedatectl set-ntp true

# Force immediate time sync
sudo systemctl restart systemd-timesyncd

# Check NTP sync status
timedatectl show-timesync --all

# For persistent time issues, install chrony
sudo apt-get install chrony
sudo systemctl enable chrony
sudo systemctl start chrony
```

### Debug Commands

```bash
# Test endpoint manually
curl http://localhost:8754/monitor.json | jq .

# Run monitor with full debug output
./fr24_monitor.sh --dry-run --verbose

# Check system logs
journalctl -u cron -f

# Validate configuration
./fr24_manager.sh validate
```

### Getting Help

1. **Check the logs**: `tail -50 fr24_monitor.log`
2. **Test manually**: `./fr24_monitor.sh --dry-run --verbose`
3. **Check status**: `./fr24_manager.sh status`
4. **Validate setup**: `./fr24_manager.sh validate`

---

## 🔬 Advanced Usage

### Custom Monitoring Schedules

Edit the cron schedule by modifying `fr24_monitor.cron` before installation:

```bash
# Every 5 minutes
*/5 * * * * __MONITOR_SCRIPT_PATH__ --log-file __LOG_FILE_PATH__

# Every 30 minutes
*/30 * * * * __MONITOR_SCRIPT_PATH__ --log-file __LOG_FILE_PATH__

# Only during daylight hours (6 AM - 11 PM)
*/10 6-23 * * * __MONITOR_SCRIPT_PATH__ --log-file __LOG_FILE_PATH__
```

### Multiple Feeders

Monitor multiple feeders by creating separate installations:

```bash
# Copy for second feeder
cp -r fr24-monitor fr24-monitor-feeder2
cd fr24-monitor-feeder2

# Install with custom settings
./fr24_monitor.sh --endpoint http://192.168.1.101:8754/monitor.json --service-name fr24feed2
```

### Integration with Other Services

The scripts can be adapted for other ADS-B feeders:
- **FlightAware**: Change service name to `piaware`
- **ADS-B Exchange**: Modify endpoint and service name
- **RadarBox**: Adjust for RadarBox monitoring endpoints

---

## 🗑️ Uninstalling

### Complete Removal

```bash
# Remove cron job and logrotate config
./fr24_manager.sh uninstall

# Remove the files
cd ..
rm -rf fr24-monitor

# Remove sudo permissions (if added)
sudo rm -f /etc/sudoers.d/fr24-monitor
```

### Keeping Logs

If you want to keep your logs for reference:
```bash
# Copy logs before uninstalling
cp fr24_monitor.log* ~/fr24_logs_backup/

# Then uninstall normally
./fr24_manager.sh uninstall
```

---

## 📝 Notes

- **Dry-run mode**: Always test with `--dry-run` first
- **Minimum uptime**: Prevents boot loops by waiting 2 hours before allowing reboots
- **Service restart**: Tries service restart before rebooting for gentler recovery
- **Portable**: All files in one directory, easy to move or backup
- **Logs**: Keep an eye on logs to understand your feeder's behavior patterns

---

## 🤝 Contributing

Feel free to submit issues, feature requests, or improvements via GitHub!

---

## 📄 License

This project is open source. Use at your own risk and always test in dry-run mode first!