<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Set timezone to match system timezone
$systemTimezone = trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC"'));
if ($systemTimezone && $systemTimezone !== 'UTC' && $systemTimezone !== '') {
    try {
        date_default_timezone_set($systemTimezone);
    } catch (Exception $e) {
        // Fallback if timezone is invalid
        date_default_timezone_set('Europe/London');
    }
} else {
    // Force Europe/London for UK systems
    date_default_timezone_set('Europe/London');
}

// Function to properly format timestamps from database
function formatDbTimestamp($timestamp) {
    if (empty($timestamp)) return 'N/A';
    
    // Create DateTime object in UTC (SQLite CURRENT_TIMESTAMP is always UTC)
    $dt = new DateTime($timestamp, new DateTimeZone('UTC'));
    // Convert to local timezone
    $dt->setTimezone(new DateTimeZone(date_default_timezone_get()));
    
    return $dt->format('d/m/Y H:i:s');
}

$dbFile = dirname(__DIR__) . '/fr24_monitor.db';

// Check if database exists
if (!file_exists($dbFile)) {
    die('<div class="alert alert-error">Database not found. Please run the installer first.</div>');
}

try {
    $pdo = new PDO('sqlite:' . $dbFile);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die('<div class="alert alert-error">Database connection failed: ' . htmlspecialchars($e->getMessage()) . '</div>');
}

// Handle delete requests
if ($_POST && isset($_POST['delete_reboot_id'])) {
    $deleteId = intval($_POST['delete_reboot_id']);
    try {
        $stmt = $pdo->prepare("DELETE FROM reboot_events WHERE id = ?");
        if ($stmt->execute([$deleteId])) {
            $deleteMessage = "Reboot entry deleted successfully.";
            $deleteMessageType = "success";
        } else {
            $deleteMessage = "Failed to delete reboot entry.";
            $deleteMessageType = "error";
        }
    } catch (PDOException $e) {
        $deleteMessage = "Error deleting entry: " . htmlspecialchars($e->getMessage());
        $deleteMessageType = "error";
    }
    
    // Redirect to avoid resubmission on refresh
    header('Location: ' . $_SERVER['PHP_SELF'] . '?deleted=' . ($deleteMessageType === 'success' ? '1' : '0'));
    exit;
}

// Show delete message if redirected
$deleteMessage = '';
$deleteMessageType = '';
if (isset($_GET['deleted'])) {
    if ($_GET['deleted'] === '1') {
        $deleteMessage = "Reboot entry deleted successfully.";
        $deleteMessageType = "success";
    } else {
        $deleteMessage = "Failed to delete reboot entry.";
        $deleteMessageType = "error";
    }
}

// Get statistics
$totalReboots = $pdo->query("SELECT COUNT(*) FROM reboot_events")->fetchColumn();
$lastReboot = $pdo->query("SELECT timestamp, reason FROM reboot_events ORDER BY timestamp DESC LIMIT 1")->fetch();
$rebootsToday = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE DATE(timestamp) = DATE('now')")->fetchColumn();
$rebootsThisWeek = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE timestamp >= DATE('now', '-7 days')")->fetchColumn();
$rebootsThisMonth = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y-%m', timestamp) = strftime('%Y-%m', 'now')")->fetchColumn();
$rebootsThisYear = $pdo->query("SELECT COUNT(*) FROM reboot_events WHERE strftime('%Y', timestamp) = strftime('%Y', 'now')")->fetchColumn();

// Get latest monitoring data
$latestMonitoring = $pdo->query("
    SELECT tracked_aircraft, uploaded_aircraft, endpoint, timestamp, feed_status, feed_server 
    FROM monitoring_stats 
    ORDER BY timestamp DESC 
    LIMIT 1
")->fetch();

// Get recent reboot events
$recentReboots = $pdo->query("
    SELECT id, timestamp, tracked_aircraft, threshold, reason, dry_run, uptime_hours, endpoint
    FROM reboot_events 
    ORDER BY timestamp DESC 
    LIMIT 10
")->fetchAll();

// Get system health trend (last 24 hours)
$monitoringTrend = $pdo->query("
    SELECT timestamp, tracked_aircraft, uploaded_aircraft
    FROM monitoring_stats 
    WHERE timestamp >= DATETIME('now', '-24 hours')
    ORDER BY timestamp DESC
    LIMIT 50
")->fetchAll();

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Dashboard</title>
    <link rel="stylesheet" href="style.css">
    <meta http-equiv="refresh" content="60">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛩️ FR24 Monitor Dashboard</h1>
            <p>Real-time monitoring and analytics for FlightRadar24 feeder status</p>
        </div>

        <?php if ($deleteMessage): ?>
            <div class="alert alert-<?= $deleteMessageType ?>">
                <?= htmlspecialchars($deleteMessage) ?>
            </div>
        <?php endif; ?>

        <?php if ($latestMonitoring): ?>
            <div class="stats-grid">
                <div class="stat-card primary">
                    <div class="stat-value"><?= $latestMonitoring['tracked_aircraft'] ?? 'N/A' ?></div>
                    <div class="stat-label">Aircraft Currently Tracked</div>
                </div>
                
                <div class="stat-card <?= $rebootsToday > 0 ? 'warning' : 'success' ?>">
                    <div class="stat-value"><?= $rebootsToday ?></div>
                    <div class="stat-label">Reboots Today</div>
                </div>
                
                <div class="stat-card info">
                    <div class="stat-value"><?= $rebootsThisWeek ?></div>
                    <div class="stat-label">Reboots This Week</div>
                </div>
                
                <div class="stat-card <?= $rebootsThisMonth > 3 ? 'warning' : 'info' ?>">
                    <div class="stat-value"><?= $rebootsThisMonth ?? '0' ?></div>
                    <div class="stat-label">Reboots This Month</div>
                </div>
                
                <div class="stat-card <?= $rebootsThisYear > 20 ? 'warning' : 'info' ?>">
                    <div class="stat-value"><?= $rebootsThisYear ?? '0' ?></div>
                    <div class="stat-label">Reboots This Year</div>
                </div>
                
                <div class="stat-card secondary">
                    <div class="stat-value"><?= $totalReboots ?></div>
                    <div class="stat-label">Total System Reboots</div>
                </div>
            </div>
        <?php endif; ?>

        <?php if ($latestMonitoring): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>📊 Current System Status</h3>
                </div>
                <table>
                    <tr>
                        <td><strong>Last Check:</strong></td>
                        <td><?= formatDbTimestamp($latestMonitoring['timestamp']) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Aircraft Tracked:</strong></td>
                        <td>
                            <span class="status-indicator <?= $latestMonitoring['tracked_aircraft'] > 0 ? 'status-success' : 'status-error' ?>"></span>
                            <?= $latestMonitoring['tracked_aircraft'] ?>
                        </td>
                    </tr>
                    <tr>
                        <td><strong>Aircraft Uploaded:</strong></td>
                        <td><?= $latestMonitoring['uploaded_aircraft'] ?? 'N/A' ?></td>
                    </tr>
                    <tr>
                        <td><strong>Feed Status:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['feed_status'] ?? 'Unknown') ?></td>
                    </tr>
                    <tr>
                        <td><strong>Feed Server:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['feed_server'] ?? 'Unknown') ?></td>
                    </tr>
                    <tr>
                        <td><strong>Endpoint:</strong></td>
                        <td><?= htmlspecialchars($latestMonitoring['endpoint']) ?></td>
                    </tr>
                </table>
            </div>
        <?php endif; ?>

        <?php if ($lastReboot): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>⚠️ Last Reboot Event</h3>
                </div>
                <table>
                    <tr>
                        <td><strong>Time:</strong></td>
                        <td><?= formatDbTimestamp($lastReboot['timestamp']) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Reason:</strong></td>
                        <td><?= htmlspecialchars($lastReboot['reason']) ?></td>
                    </tr>
                </table>
            </div>
        <?php endif; ?>

        <?php if (!empty($recentReboots)): ?>
            <div class="table-container">
                <div class="table-header">
                    <h3>📋 Recent Reboot History</h3>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th>Date/Time</th>
                            <th>Tracked</th>
                            <th>Threshold</th>
                            <th>Uptime (hrs)</th>
                            <th>Type</th>
                            <th>Reason</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($recentReboots as $reboot): ?>
                            <tr>
                                <td><?= formatDbTimestamp($reboot['timestamp']) ?></td>
                                <td><?= $reboot['tracked_aircraft'] ?></td>
                                <td><?= $reboot['threshold'] ?></td>
                                <td><?= $reboot['uptime_hours'] ?></td>
                                <td>
                                    <?php if ($reboot['dry_run']): ?>
                                        <span class="status-indicator status-warning"></span>Test
                                    <?php else: ?>
                                        <span class="status-indicator status-error"></span>Real
                                    <?php endif; ?>
                                </td>
                                <td style="word-wrap: break-word; white-space: normal; max-width: 200px;"><?= htmlspecialchars($reboot['reason']) ?></td>
                                <td>
                                    <form method="POST" style="display: inline-block; margin: 0;" onsubmit="return confirm('Are you sure you want to delete this reboot entry?');">
                                        <input type="hidden" name="delete_reboot_id" value="<?= $reboot['id'] ?>">
                                        <button type="submit" class="delete-btn" title="Delete this entry">
                                            🗑️
                                        </button>
                                    </form>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>

        <div class="refresh-info">
            <p>🔄 Page automatically refreshes every 60 seconds | Last updated: <?= date('d/m/Y H:i:s T') ?></p>
            <p>
                <a href="logs.php" class="btn">View Detailed Logs</a>
                <a href="config.php" class="btn" style="background: #9f7aea; margin-left: 0.5rem;">Email Configuration</a>
            </p>
            <p>
                <a href="settings.php" class="btn" style="background: #667eea;">Settings</a>
            </p>
            <p style="font-size: 0.8rem; color: #718096;">PHP Timezone: <?= date_default_timezone_get() ?> | System TZ: <?= $systemTimezone ?? 'Unknown' ?></p>
        </div>
    </div>
</body>
</html>
