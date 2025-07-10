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

if ($_POST && isset($_POST['test_email'])) {
    // Load configuration
    if (file_exists($configFile)) {
        $configData = file_get_contents($configFile);
        if ($configData) {
            $config = json_decode($configData, true);
            if ($config && $config['enabled']) {
                // Use the send_email.sh script to send test email
                $emailScript = dirname(__DIR__) . '/send_email.sh';
                
                if (file_exists($emailScript)) {
                    $testSubject = "FR24 Monitor Test Email";
                    $testMessage = "This is a test email to verify your FR24 Monitor email configuration is working correctly.

Timestamp: " . date('Y-m-d H:i:s T') . "
System: " . gethostname() . "
Timezone: $systemTimezone

If you received this email, your FR24 Monitor email alerts are configured properly and will be sent when the system requires a reboot.

Configuration tested:
- SMTP Server: " . $config['smtp_host'] . ":" . $config['smtp_port'] . "
- From: " . $config['from_email'] . "
- To: " . $config['to_email'] . "
- Security: " . strtoupper($config['smtp_security'] ?? 'TLS') . "

This is an automated test email from the FR24 Monitor system.";

                    // Execute the email script and capture both stdout and stderr
                    $command = 'cd ' . escapeshellarg(dirname($emailScript)) . ' && ' . 
                              escapeshellarg($emailScript) . ' ' . 
                              escapeshellarg($testSubject) . ' ' . 
                              escapeshellarg($testMessage) . ' 2>&1';
                    
                    $output = shell_exec($command);
                    $exitCode = shell_exec('echo $?');
                    
                    // Also capture msmtp log if it exists
                    $msmtpLog = '';
                    if (file_exists('/tmp/msmtp.log')) {
                        $msmtpLog = file_get_contents('/tmp/msmtp.log');
                    }
                    
                    if (trim($exitCode) === "0") {
                        $message = "Test email sent successfully! Check your inbox at " . htmlspecialchars($config['to_email']);
                        if (!empty($output)) {
                            $message .= "\n\nScript output:\n" . htmlspecialchars($output);
                        }
                        $messageType = 'success';
                    } else {
                        $message = "Failed to send test email (exit code: " . trim($exitCode) . ")";
                        if (!empty($output)) {
                            $message .= "\n\nScript output:\n" . htmlspecialchars($output);
                        }
                        if (!empty($msmtpLog)) {
                            $message .= "\n\nmsmtp log:\n" . htmlspecialchars($msmtpLog);
                        }
                        $messageType = 'error';
                    }
                } else {
                    $message = "Email helper script not found. Please reinstall the system.";
                    $messageType = 'error';
                }
            } else {
                $message = "Email alerts are not enabled. Please enable them in the configuration.";
                $messageType = 'error';
            }
        } else {
            $message = "Failed to load email configuration.";
            $messageType = 'error';
        }
    } else {
        $message = "No email configuration found. Please configure email settings first.";
        $messageType = 'error';
    }
}

// Load existing configuration for display
$config = [];
if (file_exists($configFile)) {
    $configData = file_get_contents($configFile);
    if ($configData) {
        $config = json_decode($configData, true) ?? [];
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Email - FR24 Monitor</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📧 Test Email Configuration</h1>
            <p>Send a test email to verify your configuration</p>
            <p><a href="config.php" class="btn">← Back to Configuration</a></p>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-<?= $messageType ?>">
                <pre style="white-space: pre-wrap; margin: 0; font-family: inherit;"><?= htmlspecialchars($message) ?></pre>
            </div>
        <?php endif; ?>

        <div class="table-container">
            <div class="table-header">
                <h3>✉️ Send Test Email</h3>
            </div>
            <div style="padding: 2rem;">
                <?php if (!empty($config) && $config['enabled']): ?>
                    <p style="margin-bottom: 1.5rem;">Current configuration:</p>
                    <ul style="margin-left: 1.5rem; margin-bottom: 2rem; color: #4a5568;">
                        <li><strong>SMTP Server:</strong> <?= htmlspecialchars($config['smtp_host']) ?>:<?= $config['smtp_port'] ?></li>
                        <li><strong>From:</strong> <?= htmlspecialchars($config['from_name']) ?> &lt;<?= htmlspecialchars($config['from_email']) ?>&gt;</li>
                        <li><strong>To:</strong> <?= htmlspecialchars($config['to_email']) ?></li>
                        <li><strong>Security:</strong> <?= strtoupper($config['smtp_security']) ?></li>
                    </ul>
                    
                    <form method="POST">
                        <button type="submit" name="test_email" value="1" class="btn" style="background: #3182ce;">
                            Send Test Email
                        </button>
                    </form>
                    
                    <div style="margin-top: 2rem; padding: 1rem; background: #f7fafc; border-radius: 5px;">
                        <h4 style="margin-bottom: 0.5rem; color: #2d3748;">Debug Information:</h4>
                        <small style="color: #718096;">
                            • The email script will show detailed logs above if there are any issues<br>
                            • Check that your SMTP credentials are correct<br>
                            • For Gmail, make sure you're using an App Password, not your regular password<br>
                            • Check your spam/junk folder if the test email doesn't arrive<br>
                            • You can also check /tmp/msmtp.log for more detailed SMTP logs
                        </small>
                    </div>
                <?php else: ?>
                    <div class="alert alert-warning">
                        Email alerts are not configured or enabled. Please <a href="config.php">configure email settings</a> first.
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>
</body>
</html>
