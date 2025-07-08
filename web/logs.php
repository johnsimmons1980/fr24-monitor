<?php
$logFile = dirname(__DIR__) . '/fr24_monitor.log';
$dbFile = dirname(__DIR__) . '/fr24_monitor.db';

// Read log file
$logs = [];
if (file_exists($logFile)) {
    $logs = array_reverse(array_slice(file($logFile, FILE_IGNORE_NEW_LINES), -100));
}

// Get database logs
$dbLogs = [];
if (file_exists($dbFile)) {
    try {
        $pdo = new PDO('sqlite:' . $dbFile);
        $dbLogs = $pdo->query("
            SELECT timestamp, tracked_aircraft, uploaded_aircraft, endpoint, feed_status
            FROM monitoring_stats 
            ORDER BY timestamp DESC 
            LIMIT 50
        ")->fetchAll();
    } catch (PDOException $e) {
        // Ignore database errors in logs view
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FR24 Monitor Logs</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📄 FR24 Monitor Logs</h1>
            <p><a href="index.php" class="btn">← Back to Dashboard</a></p>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>💾 Database Monitoring History</h3>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Tracked</th>
                        <th>Uploaded</th>
                        <th>Feed Status</th>
                        <th>Endpoint</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($dbLogs as $log): ?>
                        <tr>
                            <td><?= date('d/m/Y H:i:s', strtotime($log['timestamp'])) ?></td>
                            <td><?= $log['tracked_aircraft'] ?></td>
                            <td><?= $log['uploaded_aircraft'] ?? 'N/A' ?></td>
                            <td><?= htmlspecialchars($log['feed_status'] ?? 'Unknown') ?></td>
                            <td><?= htmlspecialchars(parse_url($log['endpoint'], PHP_URL_HOST) . ':' . parse_url($log['endpoint'], PHP_URL_PORT)) ?></td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>

        <div class="table-container">
            <div class="table-header">
                <h3>📝 File-based Logs (Latest 100 entries)</h3>
            </div>
            <div style="background: #1a202c; color: #e2e8f0; padding: 1rem; font-family: monospace; font-size: 0.9rem; max-height: 500px; overflow-y: auto;">
                <?php foreach ($logs as $log): ?>
                    <div style="margin-bottom: 0.25rem;"><?= htmlspecialchars($log) ?></div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
</body>
</html>
