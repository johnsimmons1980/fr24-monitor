<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

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

$configFile = dirname(__DIR__) . '/config.json';
$message = '';
$messageType = '';

// Handle form submission
if ($_POST && isset($_POST['save_settings'])) {
    $config = [
        'monitoring' => [
            'check_interval_minutes' => intval($_POST['check_interval_minutes'] ?? 10),
            'aircraft_threshold' => intval($_POST['aircraft_threshold'] ?? 30),
            'minimum_uptime_hours' => floatval($_POST['minimum_uptime_hours'] ?? 2),
            'endpoint_timeout_seconds' => intval($_POST['endpoint_timeout_seconds'] ?? 10),
            'retry_attempts' => intval($_POST['retry_attempts'] ?? 3),
            'retry_delay_seconds' => intval($_POST['retry_delay_seconds'] ?? 5),
            'endpoint_url' => $_POST['endpoint_url'] ?? 'http://localhost:8754/monitor.json'
        ],
        'reboot' => [
            'enabled' => isset($_POST['reboot_enabled']),
            'dry_run_mode' => isset($_POST['dry_run_mode']),
            'reboot_delay_seconds' => intval($_POST['reboot_delay_seconds'] ?? 300),
            'send_email_alerts' => isset($_POST['send_email_alerts'])
        ],
        'logging' => [
            'log_level' => $_POST['log_level'] ?? 'INFO',
            'max_log_size_mb' => intval($_POST['max_log_size_mb'] ?? 2),
            'keep_log_files' => intval($_POST['keep_log_files'] ?? 2),
            'database_retention_days' => intval($_POST['database_retention_days'] ?? 365),
            'verbose_output' => isset($_POST['verbose_output'])
        ],
        'web' => [
            'port' => intval($_POST['web_port'] ?? 6869),
            'auto_refresh_seconds' => intval($_POST['auto_refresh_seconds'] ?? 60),
            'max_reboot_history' => intval($_POST['max_reboot_history'] ?? 50),
            'timezone' => $_POST['web_timezone'] ?? 'Europe/London'
        ],
        'system' => [
            'service_name' => trim($_POST['service_name'] ?? 'fr24feed'),
            'service_restart_enabled' => isset($_POST['service_restart_enabled']),
            'service_restart_delay_seconds' => intval($_POST['service_restart_delay_seconds'] ?? 30),
            'check_disk_space' => isset($_POST['check_disk_space']),
            'min_disk_space_gb' => intval($_POST['min_disk_space_gb'] ?? 1)
        ],
        'notifications' => [
            'email_enabled' => isset($_POST['email_enabled']),
            'webhook_enabled' => isset($_POST['webhook_enabled']),
            'webhook_url' => trim($_POST['webhook_url'] ?? ''),
            'notification_cooldown_minutes' => intval($_POST['notification_cooldown_minutes'] ?? 60)
        ],
        'email' => [
            'enabled' => isset($_POST['email_enabled']),
            'smtp_host' => trim($_POST['smtp_host'] ?? ''),
            'smtp_port' => intval($_POST['smtp_port'] ?? 587),
            'smtp_security' => $_POST['smtp_security'] ?? 'tls',
            'use_tls' => $_POST['smtp_security'] === 'tls',
            'use_starttls' => $_POST['smtp_security'] === 'tls',
            'smtp_username' => trim($_POST['smtp_username'] ?? ''),
            'smtp_password' => $_POST['smtp_password'] ?? '',
            'from_email' => trim($_POST['from_email'] ?? ''),
            'from_name' => trim($_POST['from_name'] ?? 'FR24 Monitor'),
            'to_email' => trim($_POST['to_email'] ?? ''),
            'subject' => trim($_POST['subject'] ?? 'FR24 Monitor Alert: System Reboot Required')
        ]
    ];
    
    if (file_put_contents($configFile, json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES))) {
        $message = 'Settings saved successfully! Changes will take effect on the next monitoring cycle.';
        $messageType = 'success';
    } else {
        $message = 'Failed to save settings. Check file permissions.';
        $messageType = 'error';
    }
}

// Handle reset to defaults
if ($_POST && isset($_POST['reset_defaults'])) {
    $defaultConfig = [
        'monitoring' => [
            'check_interval_minutes' => 10,
            'aircraft_threshold' => 30,
            'minimum_uptime_hours' => 2,
            'endpoint_timeout_seconds' => 10,
            'retry_attempts' => 3,
            'retry_delay_seconds' => 5,
            'endpoint_url' => 'http://localhost:8754/monitor.json'
        ],
        'reboot' => [
            'enabled' => true,
            'dry_run_mode' => false,
            'reboot_delay_seconds' => 300,
            'send_email_alerts' => true
        ],
        'logging' => [
            'log_level' => 'INFO',
            'max_log_size_mb' => 2,
            'keep_log_files' => 2,
            'database_retention_days' => 365,
            'verbose_output' => false
        ],
        'web' => [
            'port' => 6869,
            'auto_refresh_seconds' => 60,
            'max_reboot_history' => 50,
            'timezone' => 'Europe/London'
        ],
        'system' => [
            'service_name' => 'fr24feed',
            'service_restart_enabled' => true,
            'service_restart_delay_seconds' => 30,
            'check_disk_space' => true,
            'min_disk_space_gb' => 1
        ],
        'notifications' => [
            'email_enabled' => false,
            'webhook_enabled' => false,
            'webhook_url' => '',
            'notification_cooldown_minutes' => 60
        ],
        'email' => [
            'enabled' => false,
            'smtp_host' => '',
            'smtp_port' => 587,
            'smtp_security' => 'tls',
            'use_tls' => true,
            'use_starttls' => true,
            'smtp_username' => '',
            'smtp_password' => '',
            'from_email' => '',
            'from_name' => 'FR24 Monitor',
            'to_email' => '',
            'subject' => 'FR24 Monitor Alert: System Reboot Required'
        ]
    ];
    
    if (file_put_contents($configFile, json_encode($defaultConfig, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES))) {
        $message = 'Settings reset to defaults successfully!';
        $messageType = 'success';
        $config = $defaultConfig;
    } else {
        $message = 'Failed to reset settings. Check file permissions.';
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

// Default values if config doesn't exist
if (empty($config)) {
    $config = [
        'monitoring' => [
            'check_interval_minutes' => 10,
            'aircraft_threshold' => 30,
            'minimum_uptime_hours' => 2,
            'endpoint_timeout_seconds' => 10,
            'retry_attempts' => 3,
            'retry_delay_seconds' => 5,
            'endpoint_url' => 'http://localhost:8754/monitor.json'
        ],
        'reboot' => [
            'enabled' => true,
            'dry_run_mode' => false,
            'reboot_delay_seconds' => 300,
            'send_email_alerts' => true
        ],
        'logging' => [
            'log_level' => 'INFO',
            'max_log_size_mb' => 2,
            'keep_log_files' => 2,
            'database_retention_days' => 365,
            'verbose_output' => false
        ],
        'web' => [
            'port' => 6869,
            'auto_refresh_seconds' => 60,
            'max_reboot_history' => 50,
            'timezone' => 'Europe/London'
        ],
        'system' => [
            'service_name' => 'fr24feed',
            'service_restart_enabled' => true,
            'service_restart_delay_seconds' => 30,
            'check_disk_space' => true,
            'min_disk_space_gb' => 1
        ],
        'notifications' => [
            'email_enabled' => false,
            'webhook_enabled' => false,
            'webhook_url' => '',
            'notification_cooldown_minutes' => 60
        ],
        'email' => [
            'enabled' => false,
            'smtp_host' => '',
            'smtp_port' => 587,
            'smtp_security' => 'tls',
            'use_tls' => true,
            'use_starttls' => true,
            'smtp_username' => '',
            'smtp_password' => '',
            'from_email' => '',
            'from_name' => 'FR24 Monitor',
            'to_email' => '',
            'subject' => 'FR24 Monitor Alert: System Reboot Required'
        ]
    ];
}

// Common timezone options
$timezones = [
    'UTC' => 'UTC',
    'Europe/London' => 'Europe/London (UK)',
    'Europe/Berlin' => 'Europe/Berlin (Central Europe)',
    'Europe/Paris' => 'Europe/Paris (France)',
    'America/New_York' => 'America/New_York (US Eastern)',
    'America/Chicago' => 'America/Chicago (US Central)',
    'America/Denver' => 'America/Denver (US Mountain)',
    'America/Los_Angeles' => 'America/Los_Angeles (US Pacific)',
    'Asia/Tokyo' => 'Asia/Tokyo (Japan)',
    'Australia/Sydney' => 'Australia/Sydney'
];

$logLevels = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Settings</title>
    <link rel="stylesheet" href="style.css">
    <style>
        .settings-form {
            padding: 2rem;
        }
        .form-section {
            margin-bottom: 2rem;
            padding-bottom: 1.5rem;
            border-bottom: 1px solid #e2e8f0;
        }
        .form-section:last-child {
            border-bottom: none;
        }
        .form-section h4 {
            color: #2d3748;
            margin-bottom: 1rem;
            font-size: 1.1rem;
            border-left: 4px solid #667eea;
            padding-left: 0.75rem;
        }
        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            margin-bottom: 1rem;
        }
        .form-group {
            margin-bottom: 1rem;
        }
        .form-group label {
            display: block;
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: #4a5568;
        }
        .form-group input, .form-group select {
            width: 100%;
            padding: 0.5rem;
            border: 1px solid #e2e8f0;
            border-radius: 5px;
            font-size: 0.9rem;
        }
        .form-group input:focus, .form-group select:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        .form-group small {
            color: #718096;
            font-size: 0.8rem;
            margin-top: 0.25rem;
            display: block;
        }
        .checkbox-group {
            display: flex;
            align-items: center;
            margin-bottom: 0.75rem;
        }
        .checkbox-group input[type="checkbox"] {
            width: auto;
            margin-right: 0.5rem;
        }
        .checkbox-group label {
            margin-bottom: 0;
            font-weight: normal;
        }
        .form-buttons {
            display: flex;
            gap: 1rem;
            margin-top: 2rem;
            padding-top: 1.5rem;
            border-top: 1px solid #e2e8f0;
        }
        .btn-primary {
            background: #667eea;
            color: white;
            padding: 0.75rem 1.5rem;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 600;
        }
        .btn-primary:hover {
            background: #5a67d8;
        }
        .btn-secondary {
            background: #e2e8f0;
            color: #4a5568;
            padding: 0.75rem 1.5rem;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 600;
        }
        .btn-secondary:hover {
            background: #cbd5e0;
        }
        .btn-danger {
            background: #e53e3e;
            color: white;
            padding: 0.75rem 1.5rem;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 600;
        }
        .btn-danger:hover {
            background: #c53030;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ FR24 Monitor Settings</h1>
            <p>Configure monitoring parameters, endpoints, and system behavior</p>
            <p>
                <a href="index.php" class="btn">← Back to Dashboard</a>
            </p>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-<?= $messageType ?>">
                <?= htmlspecialchars($message) ?>
            </div>
        <?php endif; ?>

        <div class="table-container">
            <div class="table-header">
                <h3>🎛️ System Configuration</h3>
            </div>
            <form method="POST" class="settings-form">
                <!-- Monitoring Settings -->
                <div class="form-section">
                    <h4>📊 Monitoring Settings</h4>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="check_interval_minutes">Check Interval (minutes)</label>
                            <input type="number" id="check_interval_minutes" name="check_interval_minutes" 
                                   value="<?= htmlspecialchars($config['monitoring']['check_interval_minutes'] ?? 10) ?>" 
                                   min="1" max="60" required>
                            <small>How often to check aircraft count (cron schedule)</small>
                        </div>
                        <div class="form-group">
                            <label for="aircraft_threshold">Aircraft Threshold</label>
                            <input type="number" id="aircraft_threshold" name="aircraft_threshold" 
                                   value="<?= htmlspecialchars($config['monitoring']['aircraft_threshold'] ?? 30) ?>" 
                                   min="0" max="1000" required>
                            <small>Minimum aircraft count before triggering reboot</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="minimum_uptime_hours">Minimum Uptime (hours)</label>
                            <input type="number" id="minimum_uptime_hours" name="minimum_uptime_hours" 
                                   value="<?= htmlspecialchars($config['monitoring']['minimum_uptime_hours'] ?? 2) ?>" 
                                   min="0" max="24" step="0.1" required>
                            <small>Minimum uptime before allowing any reboot (0 = no minimum, supports decimals like 0.5 for 30 mins)</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="endpoint_timeout_seconds">Endpoint Timeout (seconds)</label>
                            <input type="number" id="endpoint_timeout_seconds" name="endpoint_timeout_seconds" 
                                   value="<?= htmlspecialchars($config['monitoring']['endpoint_timeout_seconds'] ?? 10) ?>" 
                                   min="1" max="60" required>
                            <small>HTTP timeout for endpoint requests</small>
                        </div>
                        <div class="form-group">
                            <div class="checkbox-group">
                                <input type="checkbox" id="verbose_output" name="verbose_output" 
                                       <?= ($config['logging']['verbose_output'] ?? false) ? 'checked' : '' ?>>
                                <label for="verbose_output">Verbose Output</label>
                            </div>
                            <small>Show detailed output in console and logs</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="retry_attempts">Retry Attempts</label>
                            <input type="number" id="retry_attempts" name="retry_attempts" 
                                   value="<?= htmlspecialchars($config['monitoring']['retry_attempts'] ?? 3) ?>" 
                                   min="1" max="10" required>
                            <small>Number of retry attempts for failed checks</small>
                        </div>
                        <div class="form-group">
                            <label for="retry_delay_seconds">Retry Delay (seconds)</label>
                            <input type="number" id="retry_delay_seconds" name="retry_delay_seconds" 
                                   value="<?= htmlspecialchars($config['monitoring']['retry_delay_seconds'] ?? 5) ?>" 
                                   min="1" max="60" required>
                            <small>Delay between retry attempts</small>
                        </div>
                    </div>
                </div>

                <!-- Endpoint Settings -->
                <div class="form-section">
                    <h4>🌐 Endpoint Settings</h4>
                    <div class="form-group">
                        <label for="endpoint_url">Endpoint URL</label>
                        <input type="url" id="endpoint_url" name="endpoint_url" 
                               value="<?= htmlspecialchars($config['monitoring']['endpoint_url'] ?? 'http://localhost:8754/monitor.json') ?>" 
                               required>
                        <small>FR24 monitoring endpoint URL</small>
                    </div>
                </div>

                <!-- Reboot Settings -->
                <div class="form-section">
                    <h4>🔄 Reboot Settings</h4>
                    <div class="checkbox-group">
                        <input type="checkbox" id="reboot_enabled" name="reboot_enabled" 
                               <?= ($config['reboot']['enabled'] ?? true) ? 'checked' : '' ?>>
                        <label for="reboot_enabled">Enable automatic reboots</label>
                    </div>
                    <div class="checkbox-group">
                        <input type="checkbox" id="dry_run_mode" name="dry_run_mode" 
                               <?= ($config['reboot']['dry_run_mode'] ?? false) ? 'checked' : '' ?>>
                        <label for="dry_run_mode">Dry run mode (log only, don't actually reboot)</label>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="reboot_delay_seconds">Reboot Delay (seconds)</label>
                            <input type="number" id="reboot_delay_seconds" name="reboot_delay_seconds" 
                                   value="<?= htmlspecialchars($config['reboot']['reboot_delay_seconds'] ?? 300) ?>" 
                                   min="0" max="3600" required>
                            <small>Delay before executing reboot command</small>
                        </div>
                    </div>
                    <div class="checkbox-group">
                        <input type="checkbox" id="send_email_alerts" name="send_email_alerts" 
                               <?= ($config['reboot']['send_email_alerts'] ?? true) ? 'checked' : '' ?>>
                        <label for="send_email_alerts">Send email alerts before rebooting</label>
                    </div>
                </div>

                <!-- System Settings -->
                <div class="form-section">
                    <h4>⚙️ System Settings</h4>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="service_name">FR24 Service Name</label>
                            <input type="text" id="service_name" name="service_name" 
                                   value="<?= htmlspecialchars($config['system']['service_name'] ?? 'fr24feed') ?>" 
                                   required>
                            <small>Name of the FR24 systemd service</small>
                        </div>
                        <div class="form-group">
                            <label for="service_restart_delay_seconds">Service Restart Delay (seconds)</label>
                            <input type="number" id="service_restart_delay_seconds" name="service_restart_delay_seconds" 
                                   value="<?= htmlspecialchars($config['system']['service_restart_delay_seconds'] ?? 30) ?>" 
                                   min="0" max="300" required>
                            <small>Delay before attempting service restart</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="min_disk_space_gb">Minimum Disk Space (GB)</label>
                            <input type="number" id="min_disk_space_gb" name="min_disk_space_gb" 
                                   value="<?= htmlspecialchars($config['system']['min_disk_space_gb'] ?? 1) ?>" 
                                   min="0" max="100" step="0.1" required>
                            <small>Minimum free disk space required</small>
                        </div>
                        <div class="form-group"></div>
                    </div>
                    <div class="checkbox-group">
                        <input type="checkbox" id="service_restart_enabled" name="service_restart_enabled" 
                               <?= ($config['system']['service_restart_enabled'] ?? true) ? 'checked' : '' ?>>
                        <label for="service_restart_enabled">Enable automatic service restart attempts</label>
                    </div>
                    <div class="checkbox-group">
                        <input type="checkbox" id="check_disk_space" name="check_disk_space" 
                               <?= ($config['system']['check_disk_space'] ?? true) ? 'checked' : '' ?>>
                        <label for="check_disk_space">Monitor disk space usage</label>
                    </div>
                </div>

                <!-- Web Dashboard Settings -->
                <div class="form-section">
                    <h4>🌐 Web Dashboard Settings</h4>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="web_port">Web Server Port</label>
                            <input type="number" id="web_port" name="web_port" 
                                   value="<?= htmlspecialchars($config['web']['port'] ?? 6869) ?>" 
                                   min="1024" max="65535" required>
                            <small>Port for the web dashboard (requires restart)</small>
                        </div>
                        <div class="form-group">
                            <label for="auto_refresh_seconds">Auto Refresh Interval (seconds)</label>
                            <input type="number" id="auto_refresh_seconds" name="auto_refresh_seconds" 
                                   value="<?= htmlspecialchars($config['web']['auto_refresh_seconds'] ?? 60) ?>" 
                                   min="10" max="600" required>
                            <small>Dashboard auto-refresh interval</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="max_reboot_history">Max Reboot History</label>
                            <input type="number" id="max_reboot_history" name="max_reboot_history" 
                                   value="<?= htmlspecialchars($config['web']['max_reboot_history'] ?? 50) ?>" 
                                   min="10" max="500" required>
                            <small>Maximum reboot entries to display</small>
                        </div>
                        <div class="form-group">
                            <label for="web_timezone">Dashboard Timezone</label>
                            <select id="web_timezone" name="web_timezone" required>
                                <?php foreach ($timezones as $tz => $label): ?>
                                    <option value="<?= htmlspecialchars($tz) ?>" 
                                            <?= ($config['web']['timezone'] ?? 'Europe/London') === $tz ? 'selected' : '' ?>>
                                        <?= htmlspecialchars($label) ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <small>Timezone for dashboard timestamps</small>
                        </div>
                    </div>
                </div>

                <!-- Logging Settings -->
                <div class="form-section">
                    <h4>📝 Logging Settings</h4>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="log_level">Log Level</label>
                            <select id="log_level" name="log_level" required>
                                <?php foreach ($logLevels as $level): ?>
                                    <option value="<?= htmlspecialchars($level) ?>" 
                                            <?= ($config['logging']['log_level'] ?? 'INFO') === $level ? 'selected' : '' ?>>
                                        <?= htmlspecialchars($level) ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <small>Minimum log level to record</small>
                        </div>
                        <div class="form-group">
                            <label for="max_log_size_mb">Max Log File Size (MB)</label>
                            <input type="number" id="max_log_size_mb" name="max_log_size_mb" 
                                   value="<?= htmlspecialchars($config['logging']['max_log_size_mb'] ?? 50) ?>" 
                                   min="1" max="1000" required>
                            <small>Maximum size before log rotation</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="keep_log_files">Keep Log Files</label>
                            <input type="number" id="keep_log_files" name="keep_log_files" 
                                   value="<?= htmlspecialchars($config['logging']['keep_log_files'] ?? 7) ?>" 
                                   min="1" max="30" required>
                            <small>Number of rotated log files to keep</small>
                        </div>
                        <div class="form-group">
                            <label for="database_retention_days">Database Retention (days)</label>
                            <input type="number" id="database_retention_days" name="database_retention_days" 
                                   value="<?= htmlspecialchars($config['logging']['database_retention_days'] ?? 365) ?>" 
                                   min="1" max="3650" required>
                            <small>Days to keep database records</small>
                        </div>
                    </div>
                </div>

                <!-- Notification Settings -->
                <div class="form-section">
                    <h4>🔔 Notification Settings</h4>
                    <div class="checkbox-group">
                        <input type="checkbox" id="email_enabled" name="email_enabled" 
                               <?= ($config['notifications']['email_enabled'] ?? false) ? 'checked' : '' ?>>
                        <label for="email_enabled">Enable email notifications</label>
                    </div>
                    <div class="checkbox-group">
                        <input type="checkbox" id="webhook_enabled" name="webhook_enabled" 
                               <?= ($config['notifications']['webhook_enabled'] ?? false) ? 'checked' : '' ?>>
                        <label for="webhook_enabled">Enable webhook notifications</label>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="webhook_url">Webhook URL</label>
                            <input type="url" id="webhook_url" name="webhook_url" 
                                   value="<?= htmlspecialchars($config['notifications']['webhook_url'] ?? '') ?>">
                            <small>URL to post webhook notifications (Discord, Slack, etc.)</small>
                        </div>
                        <div class="form-group">
                            <label for="notification_cooldown_minutes">Notification Cooldown (minutes)</label>
                            <input type="number" id="notification_cooldown_minutes" name="notification_cooldown_minutes" 
                                   value="<?= htmlspecialchars($config['notifications']['notification_cooldown_minutes'] ?? 60) ?>" 
                                   min="1" max="1440" required>
                            <small>Minimum time between duplicate notifications</small>
                        </div>
                    </div>
                </div>

                <!-- Email Settings -->
                <div class="form-section" id="email">
                    <h4>📧 Email Settings</h4>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="smtp_host">SMTP Host</label>
                            <input type="text" id="smtp_host" name="smtp_host" 
                                   value="<?= htmlspecialchars($config['email']['smtp_host'] ?? '') ?>">
                            <small>SMTP server hostname (e.g., smtp.gmail.com)</small>
                        </div>
                        <div class="form-group">
                            <label for="smtp_port">SMTP Port</label>
                            <input type="number" id="smtp_port" name="smtp_port" 
                                   value="<?= htmlspecialchars($config['email']['smtp_port'] ?? 587) ?>" 
                                   min="1" max="65535">
                            <small>SMTP server port (usually 587 for TLS)</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="smtp_security">SMTP Security</label>
                            <select id="smtp_security" name="smtp_security">
                                <option value="tls" <?= ($config['email']['smtp_security'] ?? 'tls') === 'tls' ? 'selected' : '' ?>>TLS</option>
                                <option value="ssl" <?= ($config['email']['smtp_security'] ?? 'tls') === 'ssl' ? 'selected' : '' ?>>SSL</option>
                                <option value="none" <?= ($config['email']['smtp_security'] ?? 'tls') === 'none' ? 'selected' : '' ?>>None</option>
                            </select>
                            <small>SMTP security protocol</small>
                        </div>
                        <div class="form-group">
                            <label for="smtp_username">SMTP Username</label>
                            <input type="text" id="smtp_username" name="smtp_username" 
                                   value="<?= htmlspecialchars($config['email']['smtp_username'] ?? '') ?>">
                            <small>SMTP authentication username</small>
                        </div>
                    </div>
                    <div class="form-group">
                        <label for="smtp_password">SMTP Password</label>
                        <input type="password" id="smtp_password" name="smtp_password" 
                               value="<?= htmlspecialchars($config['email']['smtp_password'] ?? '') ?>">
                        <small>SMTP authentication password (for Gmail, use App Password)</small>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="from_email">From Email</label>
                            <input type="email" id="from_email" name="from_email" 
                                   value="<?= htmlspecialchars($config['email']['from_email'] ?? '') ?>">
                            <small>Sender email address</small>
                        </div>
                        <div class="form-group">
                            <label for="from_name">From Name</label>
                            <input type="text" id="from_name" name="from_name" 
                                   value="<?= htmlspecialchars($config['email']['from_name'] ?? 'FR24 Monitor') ?>">
                            <small>Sender display name</small>
                        </div>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="to_email">To Email</label>
                            <input type="email" id="to_email" name="to_email" 
                                   value="<?= htmlspecialchars($config['email']['to_email'] ?? '') ?>">
                            <small>Recipient email address</small>
                        </div>
                        <div class="form-group">
                            <label for="subject">Email Subject</label>
                            <input type="text" id="subject" name="subject" 
                                   value="<?= htmlspecialchars($config['email']['subject'] ?? 'FR24 Monitor Alert: System Reboot Required') ?>">
                            <small>Email subject line</small>
                        </div>
                    </div>
                </div>

                <div class="form-buttons">
                    <button type="submit" name="save_settings" class="btn-primary">💾 Save Settings</button>
                    <button type="submit" name="reset_defaults" class="btn-danger" 
                            onclick="return confirm('Are you sure you want to reset all settings to defaults? This cannot be undone.')">
                        🔄 Reset to Defaults
                    </button>
                    <a href="index.php" class="btn-secondary">❌ Cancel</a>
                </div>
            </form>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>ℹ️ Configuration Information</h3>
            </div>
            <div style="padding: 1.5rem;">
                <p><strong>Configuration File:</strong> <code><?= htmlspecialchars($configFile) ?></code></p>
                <p><strong>File Status:</strong> 
                    <?php if (file_exists($configFile)): ?>
                        <span style="color: #38a169;">✓ Exists</span>
                        (<?= is_writable($configFile) ? '<span style="color: #38a169;">Writable</span>' : '<span style="color: #e53e3e;">Read-only</span>' ?>)
                    <?php else: ?>
                        <span style="color: #dd6b20;">⚠ Will be created on save</span>
                    <?php endif; ?>
                </p>
                <p><strong>Last Modified:</strong> 
                    <?php if (file_exists($configFile)): ?>
                        <?= date('d/m/Y H:i:s T', filemtime($configFile)) ?>
                    <?php else: ?>
                        N/A
                    <?php endif; ?>
                </p>
                <p><strong>Changes take effect:</strong> On next monitoring cycle (usually within <?= $config['monitoring']['check_interval_minutes'] ?? 10 ?> minutes)</p>
                <p style="margin-top: 1rem; color: #718096; font-size: 0.9rem;">
                    <strong>Note:</strong> Some settings like web port require restarting the web service to take effect.
                    Use <code>./fr24_manager.sh restart-web</code> to restart the dashboard.
                </p>
            </div>
        </div>
    </div>
</body>
</html>
