<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

$message = '';

// Handle delete request
if ($_POST['action'] ?? '' === 'delete' && !empty($_POST['timestamp'])) {
    $dbFile = dirname(__DIR__) . '/fr24_monitor.db';
    
    if (file_exists($dbFile)) {
        try {
            $pdo = new PDO('sqlite:' . $dbFile);
            $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            
            $stmt = $pdo->prepare("DELETE FROM reboot_events WHERE timestamp = ?");
            $deleted = $stmt->execute([$_POST['timestamp']]);
            
            if ($deleted && $stmt->rowCount() > 0) {
                $message = '<div class="alert alert-success">✅ Reboot entry deleted successfully!</div>';
            } else {
                $message = '<div class="alert alert-warning">⚠️ No matching entry found to delete.</div>';
            }
        } catch (PDOException $e) {
            $message = '<div class="alert alert-error">❌ Error deleting entry: ' . htmlspecialchars($e->getMessage()) . '</div>';
        }
    }
}

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
    
    // Create DateTime object and set timezone
    $dt = new DateTime($timestamp);
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
    SELECT timestamp, tracked_aircraft, threshold, reason, dry_run, uptime_hours, endpoint
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
        <?php if ($message): ?>
            <?= $message ?>
        <?php endif; ?>
        
        <div class="header">
            <h1>🛩️ FR24 Monitor Dashboard</h1>
            <p>Real-time monitoring and analytics for FlightRadar24 feeder status</p>
        </div>

        <?php if ($latestMonitoring): ?>
            <!-- Debug: Variable check -->
            <?php 
            // Debug output (remove after testing)
            error_log("DEBUG: rebootsThisMonth = " . $rebootsThisMonth);
            error_log("DEBUG: rebootsThisYear = " . $rebootsThisYear);
            ?>
            
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
                            <th>Action</th>
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
                                <td class="reason-cell"><?= htmlspecialchars($reboot['reason']) ?></td>
                                <td>
                                    <form method="post" style="display: inline;" onsubmit="return confirm('Are you sure you want to delete this reboot entry?');">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="timestamp" value="<?= htmlspecialchars($reboot['timestamp']) ?>">
                                        <button type="submit" class="delete-btn" title="Delete this entry">🗑️</button>
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
                <a href="config.php" class="btn">Email Config</a>
            </p>
            <!-- Debug: Timezone info -->
            <p style="font-size: 0.8rem; color: #999; margin-top: 10px;">
                Debug: PHP Timezone: <?= date_default_timezone_get() ?> | 
                System TZ: <?= trim(shell_exec('timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown"')) ?>
            </p>
        </div>
    </div>
</body>
</html>
