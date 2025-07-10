<?php
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

$configFile = dirname(__DIR__) . '/email_config.json';
$message = '';
$messageType = '';

// Handle form submission
if ($_POST) {
    $config = [
        'enabled' => isset($_POST['enabled']) ? true : false,
        'smtp_host' => $_POST['smtp_host'] ?? '',
        'smtp_port' => intval($_POST['smtp_port'] ?? 587),
        'use_tls' => $_POST['smtp_security'] === 'tls',
        'use_starttls' => $_POST['smtp_security'] === 'tls',
        'smtp_user' => $_POST['smtp_username'] ?? '',
        'smtp_password' => $_POST['smtp_password'] ?? '',
        'from_email' => $_POST['from_email'] ?? '',
        'from_name' => $_POST['from_name'] ?? 'FR24 Monitor',
        'to_email' => $_POST['to_email'] ?? '',
        'subject' => $_POST['subject'] ?? 'FR24 Monitor Alert: System Reboot Required',
        'smtp_security' => $_POST['smtp_security'] ?? 'tls'
    ];
    
    if (file_put_contents($configFile, json_encode($config, JSON_PRETTY_PRINT))) {
        $message = 'Configuration saved successfully!';
        $messageType = 'success';
    } else {
        $message = 'Failed to save configuration. Check file permissions.';
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

// Default values
$config = array_merge([
    'enabled' => false,
    'smtp_host' => '',
    'smtp_port' => 587,
    'smtp_security' => 'tls',
    'use_tls' => true,
    'use_starttls' => true,
    'smtp_user' => '',
    'smtp_username' => '',
    'smtp_password' => '',
    'from_email' => '',
    'from_name' => 'FR24 Monitor',
    'to_email' => '',
    'subject' => 'FR24 Monitor Alert: System Reboot Required'
], $config);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Configuration</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚙️ FR24 Monitor Configuration</h1>
            <p>Configure email alerts for system reboot notifications</p>
            <p><a href="index.php" class="btn">← Back to Dashboard</a></p>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-<?= $messageType ?>">
                <?= htmlspecialchars($message) ?>
            </div>
        <?php endif; ?>

        <div class="table-container">
            <div class="table-header">
                <h3>📧 Email Alert Configuration</h3>
            </div>
            <form method="POST" style="padding: 2rem;">
                <div style="margin-bottom: 1.5rem;">
                    <label style="display: flex; align-items: center; font-weight: 600; margin-bottom: 0.5rem;">
                        <input type="checkbox" name="enabled" value="1" <?= $config['enabled'] ? 'checked' : '' ?> style="margin-right: 0.5rem;">
                        Enable Email Alerts
                    </label>
                    <small style="color: #718096;">Send email notifications when the system requires a reboot</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Server Host:</label>
                    <input type="text" name="smtp_host" value="<?= htmlspecialchars($config['smtp_host']) ?>" 
                           placeholder="e.g., smtp.gmail.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">SMTP server hostname or IP address</small>
                </div>

                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1.5rem;">
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Port:</label>
                        <input type="number" name="smtp_port" value="<?= $config['smtp_port'] ?>" 
                               placeholder="587" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                        <small style="color: #718096;">Usually 587 for TLS or 465 for SSL</small>
                    </div>
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">Security:</label>
                        <select name="smtp_security" style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                            <option value="tls" <?= $config['smtp_security'] === 'tls' ? 'selected' : '' ?>>TLS</option>
                            <option value="ssl" <?= $config['smtp_security'] === 'ssl' ? 'selected' : '' ?>>SSL</option>
                            <option value="none" <?= $config['smtp_security'] === 'none' ? 'selected' : '' ?>>None</option>
                        </select>
                    </div>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Username:</label>
                    <input type="text" name="smtp_username" value="<?= htmlspecialchars($config['smtp_username']) ?>" 
                           placeholder="your.email@example.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">Usually your email address</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">SMTP Password:</label>
                    <input type="password" name="smtp_password" value="<?= htmlspecialchars($config['smtp_password']) ?>" 
                           placeholder="Your email password or app password" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">For Gmail, use an App Password instead of your regular password</small>
                </div>

                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; margin-bottom: 1.5rem;">
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">From Email:</label>
                        <input type="email" name="from_email" value="<?= htmlspecialchars($config['from_email']) ?>" 
                               placeholder="monitor@example.com" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    </div>
                    <div>
                        <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">From Name:</label>
                        <input type="text" name="from_name" value="<?= htmlspecialchars($config['from_name']) ?>" 
                               placeholder="FR24 Monitor" 
                               style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    </div>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">To Email:</label>
                    <input type="email" name="to_email" value="<?= htmlspecialchars($config['to_email']) ?>" 
                           placeholder="admin@example.com" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                    <small style="color: #718096;">Email address to receive alerts</small>
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <label style="display: block; font-weight: 600; margin-bottom: 0.5rem;">Email Subject:</label>
                    <input type="text" name="subject" value="<?= htmlspecialchars($config['subject']) ?>" 
                           placeholder="FR24 Monitor Alert: System Reboot Required" 
                           style="width: 100%; padding: 0.5rem; border: 1px solid #e2e8f0; border-radius: 5px;">
                </div>

                <div style="display: flex; gap: 1rem;">
                    <button type="submit" class="btn" style="background: #38a169;">Save Configuration</button>
                    <a href="test_email.php" class="btn" style="background: #3182ce;">Test Email</a>
                </div>
            </form>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>📝 Configuration Help</h3>
            </div>
            <div style="padding: 1.5rem;">
                <h4 style="margin-bottom: 1rem; color: #2d3748;">Common SMTP Settings:</h4>
                <ul style="margin-left: 1.5rem; margin-bottom: 1.5rem;">
                    <li><strong>Gmail:</strong> smtp.gmail.com, Port 587, TLS (requires App Password)</li>
                    <li><strong>Outlook/Hotmail:</strong> smtp-mail.outlook.com, Port 587, TLS</li>
                    <li><strong>Yahoo:</strong> smtp.mail.yahoo.com, Port 587, TLS</li>
                    <li><strong>ISP SMTP:</strong> Check with your internet provider</li>
                </ul>
                
                <h4 style="margin-bottom: 1rem; color: #2d3748;">Gmail Setup:</h4>
                <ol style="margin-left: 1.5rem;">
                    <li>Enable 2-factor authentication on your Google account</li>
                    <li>Go to Google Account settings → Security → App passwords</li>
                    <li>Generate an App Password for "Mail"</li>
                    <li>Use this App Password instead of your regular password</li>
                </ol>
            </div>
        </div>
    </div>
</body>
</html>
