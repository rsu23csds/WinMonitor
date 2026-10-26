<#
.SYNOPSIS
    Generates an executive-ready, responsive HTML health dashboard report.
.DESCRIPTION
    Module for WinInfraMonitor. Formats collected infrastructure metrics, disk usage,
    service health, and event logs into a standalone HTML report with modern dashboard styling.
#>

function Export-HtmlHealthDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SystemInfo,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CpuMetric,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$MemoryMetric,

        [Parameter(Mandatory = $true)]
        [array]$DiskMetrics,

        [Parameter(Mandatory = $true)]
        [array]$ServiceMetrics,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$EventMetrics,

        [Parameter(Mandatory = $true)]
        [string]$OverallStatus,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [double]$ExecutionTimeSeconds = 0
    )

    $reportTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # Status theme configurations
    $statusColor = switch ($OverallStatus) {
        "HEALTHY"  { "#10b981" }
        "WARNING"  { "#f59e0b" }
        "CRITICAL" { "#ef4444" }
        default    { "#6b7280" }
    }

    $statusBg = switch ($OverallStatus) {
        "HEALTHY"  { "linear-gradient(135deg, #064e3b 0%, #065f46 100%)" }
        "WARNING"  { "linear-gradient(135deg, #78350f 0%, #92400e 100%)" }
        "CRITICAL" { "linear-gradient(135deg, #7f1d1d 0%, #991b1b 100%)" }
        default    { "linear-gradient(135deg, #1f2937 0%, #374151 100%)" }
    }

    $statusText = switch ($OverallStatus) {
        "HEALTHY"  { "ALL SYSTEMS OPERATIONAL" }
        "WARNING"  { "SYSTEM PERFORMANCE WARNING" }
        "CRITICAL" { "CRITICAL ACTION REQUIRED" }
        default    { "STATUS UNKNOWN" }
    }

    # Helper function for status badges
    function Get-BadgeHtml($status) {
        $color = switch ($status) {
            "HEALTHY"    { "#10b981" }
            "REMEDIATED" { "#38bdf8" }
            "WARNING"    { "#f59e0b" }
            "CRITICAL"   { "#ef4444" }
            "INFO"       { "#94a3b8" }
            default      { "#94a3b8" }
        }
        $bg = switch ($status) {
            "HEALTHY"    { "rgba(16, 185, 129, 0.15)" }
            "REMEDIATED" { "rgba(56, 189, 248, 0.15)" }
            "WARNING"    { "rgba(245, 158, 11, 0.15)" }
            "CRITICAL"   { "rgba(239, 68, 68, 0.15)" }
            default      { "rgba(148, 163, 184, 0.15)" }
        }
        return "<span style='display:inline-flex;align-items:center;padding:3px 10px;border-radius:9999px;font-size:11px;font-weight:700;letter-spacing:0.5px;color:$color;background:$bg;border:1px solid $color;'>$status</span>"
    }

    # Helper function for progress bars
    function Get-BarHtml($pct, $status) {
        $barColor = switch ($status) {
            "HEALTHY"  { "#10b981" }
            "WARNING"  { "#f59e0b" }
            "CRITICAL" { "#ef4444" }
            default    { "#38bdf8" }
        }
        return "<div style='background:#1e293b;border-radius:6px;height:10px;width:100%;overflow:hidden;'><div style='background:$barColor;height:100%;width:$pct%;border-radius:6px;'></div></div>"
    }

    # Service metrics summary
    $totalServices = $ServiceMetrics.Count
    $runningServices = ($ServiceMetrics | Where-Object { $_.Status -eq "Running" }).Count
    $serviceStatusBadge = if ($runningServices -eq $totalServices) { "HEALTHY" } else { "WARNING" }

    # Build Disks Table rows
    $diskRows = ""
    foreach ($d in $DiskMetrics) {
        $badge = Get-BadgeHtml $d.Status
        $pbar = Get-BarHtml $d.UsedPercent $d.Status
        $diskRows += "<tr>"
        $diskRows += "<td style='font-weight:600;color:#f8fafc;'>$($d.DriveLetter)</td>"
        $diskRows += "<td style='color:#94a3b8;'>$($d.VolumeName)</td>"
        $diskRows += "<td style='color:#94a3b8;'>$($d.FileSystem)</td>"
        $diskRows += "<td style='color:#f8fafc;'>$($d.TotalSizeGB) GB</td>"
        $diskRows += "<td style='color:#f8fafc;'>$($d.UsedSpaceGB) GB ($($d.UsedPercent)%)</td>"
        $diskRows += "<td style='color:#38bdf8;font-weight:600;'>$($d.FreeSpaceGB) GB ($($d.FreePercent)%)</td>"
        $diskRows += "<td style='min-width:140px;'>$pbar</td>"
        $diskRows += "<td>$badge</td>"
        $diskRows += "</tr>`n"
    }

    # Build Services Table rows
    $serviceRows = ""
    foreach ($s in $ServiceMetrics) {
        $badge = Get-BadgeHtml $s.HealthStatus
        $dotColor = if ($s.Status -eq "Running") { "#10b981" } else { "#ef4444" }
        $statusDot = "<span style='display:inline-block;width:8px;height:8px;border-radius:50%;background:$dotColor;margin-right:8px;'></span>"
        $serviceRows += "<tr>"
        $serviceRows += "<td style='font-family:Consolas, monospace;font-weight:600;color:#38bdf8;'>$($s.ServiceName)</td>"
        $serviceRows += "<td style='color:#cbd5e1;'>$($s.DisplayName)</td>"
        $serviceRows += "<td style='color:#94a3b8;'>$($s.StartType)</td>"
        $serviceRows += "<td>$statusDot<span style='color:#f8fafc;'>$($s.Status)</span></td>"
        $serviceRows += "<td>$badge</td>"
        $serviceRows += "<td style='color:#94a3b8;font-size:12px;'>$($s.RemediationAction)</td>"
        $serviceRows += "</tr>`n"
    }

    # Build Event Log rows
    $eventRows = ""
    if ($EventMetrics -and $EventMetrics.Events -and $EventMetrics.Events.Count -gt 0) {
        foreach ($e in $EventMetrics.Events) {
            $targetLevel = "WARNING"
            if ($e.Level -eq "Error" -or $e.Level -eq "Critical") {
                $targetLevel = "CRITICAL"
            }
            $evtBadge = Get-BadgeHtml $targetLevel
            $eventRows += "<tr>"
            $eventRows += "<td style='white-space:nowrap;color:#94a3b8;font-size:12px;'>$($e.TimeCreated)</td>"
            $eventRows += "<td><span style='font-weight:600;color:#f8fafc;'>$($e.LogName)</span></td>"
            $eventRows += "<td>$evtBadge</td>"
            $eventRows += "<td style='color:#38bdf8;font-family:Consolas, monospace;'>$($e.EventId)</td>"
            $eventRows += "<td style='color:#e2e8f0;font-size:12px;'>$($e.Provider)</td>"
            $eventRows += "<td style='color:#94a3b8;font-size:12px;'>$($e.Message)</td>"
            $eventRows += "</tr>`n"
        }
    }
    else {
        $eventRows = "<tr><td colspan='6' style='text-align:center;padding:24px;color:#10b981;'>No critical or error event anomalies detected in the past 24 hours.</td></tr>"
    }

    $cpuNameClean = if ($CpuMetric.ProcessorName) { ($CpuMetric.ProcessorName -split '@')[0].Trim() } else { "Standard Multi-Core CPU" }
    $execSecondsFormatted = [Math]::Round($ExecutionTimeSeconds, 2)
    $lastBootFormatted = if ($SystemInfo.LastBootUpTime) { $SystemInfo.LastBootUpTime.ToString("yyyy-MM-dd HH:mm") } else { "N/A" }
    $overallBadgeHtml = Get-BadgeHtml $OverallStatus
    $cpuBarHtml = Get-BarHtml $CpuMetric.UsagePercent $CpuMetric.Status
    $memBarHtml = Get-BarHtml $MemoryMetric.UsagePercent $MemoryMetric.Status

    # CSS styles using literal string to prevent PowerShell variable evaluation
    $cssBlock = @'
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #0b0f19;
            color: #e2e8f0;
            line-height: 1.5;
            padding: 24px;
        }
        .container {
            max-width: 1280px;
            margin: 0 auto;
        }
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 20px;
            border-bottom: 1px solid #1e293b;
            margin-bottom: 24px;
        }
        .brand-title {
            font-size: 24px;
            font-weight: 800;
            color: #f8fafc;
            letter-spacing: -0.5px;
        }
        .brand-subtitle {
            font-size: 13px;
            color: #64748b;
            margin-top: 4px;
        }
        .header-meta {
            text-align: right;
            font-size: 12px;
            color: #94a3b8;
        }
        .header-meta span {
            color: #38bdf8;
            font-weight: 600;
        }
        .status-banner {
            border-radius: 12px;
            padding: 20px 24px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 24px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.4);
        }
        .status-indicator {
            display: flex;
            align-items: center;
            gap: 16px;
        }
        .status-dot {
            width: 14px;
            height: 14px;
            border-radius: 50%;
        }
        .status-title {
            font-size: 18px;
            font-weight: 700;
            color: #ffffff;
            letter-spacing: 0.5px;
        }
        .status-desc {
            font-size: 13px;
            color: rgba(255, 255, 255, 0.85);
        }
        .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        .kpi-card {
            background: #111827;
            border: 1px solid #1f2937;
            border-radius: 12px;
            padding: 18px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2);
        }
        .kpi-title {
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: #94a3b8;
            margin-bottom: 8px;
        }
        .kpi-value {
            font-size: 26px;
            font-weight: 800;
            color: #f8fafc;
            margin-bottom: 8px;
        }
        .kpi-subtext {
            font-size: 12px;
            color: #64748b;
        }
        .panel {
            background: #111827;
            border: 1px solid #1f2937;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2);
        }
        .panel-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 14px;
            margin-bottom: 16px;
            border-bottom: 1px solid #1f2937;
        }
        .panel-title {
            font-size: 16px;
            font-weight: 700;
            color: #f8fafc;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 14px;
        }
        .info-item {
            background: #0f172a;
            padding: 12px 16px;
            border-radius: 8px;
            border: 1px solid #1e293b;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .info-label {
            font-size: 12px;
            color: #94a3b8;
        }
        .info-val {
            font-size: 13px;
            font-weight: 600;
            color: #f8fafc;
            text-align: right;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }
        th {
            text-align: left;
            padding: 10px 14px;
            color: #64748b;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 0.5px;
            border-bottom: 1px solid #1e293b;
            background: #0d131f;
        }
        td {
            padding: 12px 14px;
            border-bottom: 1px solid #1e293b;
        }
        tr:hover td {
            background-color: #172033;
        }
        footer {
            margin-top: 32px;
            padding-top: 20px;
            border-top: 1px solid #1e293b;
            display: flex;
            justify-content: space-between;
            align-items: center;
            color: #64748b;
            font-size: 12px;
        }
'@

    # Assemble HTML page
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('    <meta charset="UTF-8">')
    [void]$sb.AppendLine('    <meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine("    <title>IT Infrastructure Health Report - $($SystemInfo.Hostname)</title>")
    [void]$sb.AppendLine('    <style>')
    [void]$sb.AppendLine($cssBlock)
    [void]$sb.AppendLine('    </style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('    <div class="container">')

    # Header
    [void]$sb.AppendLine('        <header>')
    [void]$sb.AppendLine('            <div>')
    [void]$sb.AppendLine('                <div class="brand-title">WinInfraMonitor Enterprise Diagnostic</div>')
    [void]$sb.AppendLine('                <div class="brand-subtitle">IT Infrastructure Automated Health & Remediation Report</div>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <div class="header-meta">')
    [void]$sb.AppendLine("                <div>Host: <span>$($SystemInfo.Hostname)</span></div>")
    [void]$sb.AppendLine("                <div>Generated: <span>$reportTimestamp</span></div>")
    [void]$sb.AppendLine("                <div>Scan Runtime: <span>${execSecondsFormatted}s</span></div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </header>')

    # Status Banner
    [void]$sb.AppendLine("        <div class='status-banner' style='background:$statusBg;border:1px solid $statusColor;'>")
    [void]$sb.AppendLine('            <div class="status-indicator">')
    [void]$sb.AppendLine("                <div class='status-dot' style='background:$statusColor;'></div>")
    [void]$sb.AppendLine('                <div>')
    [void]$sb.AppendLine("                    <div class='status-title'>$statusText</div>")
    [void]$sb.AppendLine('                    <div class="status-desc">All evaluated thresholds, storage partitions, and critical services matched health policies.</div>')
    [void]$sb.AppendLine('                </div>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine("            <div>$overallBadgeHtml</div>")
    [void]$sb.AppendLine('        </div>')

    # KPI Grid
    [void]$sb.AppendLine('        <div class="kpi-grid">')
    [void]$sb.AppendLine('            <div class="kpi-card">')
    [void]$sb.AppendLine('                <div class="kpi-title">CPU Utilization</div>')
    [void]$sb.AppendLine("                <div class='kpi-value'>$($CpuMetric.UsagePercent)%</div>")
    [void]$sb.AppendLine("                <div class='kpi-subtext'>$cpuNameClean</div>")
    [void]$sb.AppendLine("                <div style='margin-top:10px;'>$cpuBarHtml</div>")
    [void]$sb.AppendLine('            </div>')

    [void]$sb.AppendLine('            <div class="kpi-card">')
    [void]$sb.AppendLine('                <div class="kpi-title">Memory Allocation</div>')
    [void]$sb.AppendLine("                <div class='kpi-value'>$($MemoryMetric.UsagePercent)%</div>")
    [void]$sb.AppendLine("                <div class='kpi-subtext'>$($MemoryMetric.UsedMemoryGB) GB of $($MemoryMetric.TotalMemoryGB) GB Used</div>")
    [void]$sb.AppendLine("                <div style='margin-top:10px;'>$memBarHtml</div>")
    [void]$sb.AppendLine('            </div>')

    [void]$sb.AppendLine('            <div class="kpi-card">')
    [void]$sb.AppendLine('                <div class="kpi-title">System Uptime</div>')
    [void]$sb.AppendLine("                <div class='kpi-value' style='font-size:20px;line-height:1.4;'>$($SystemInfo.UptimeFormatted)</div>")
    [void]$sb.AppendLine("                <div class='kpi-subtext'>Last Boot: $lastBootFormatted</div>")
    [void]$sb.AppendLine('            </div>')

    [void]$sb.AppendLine('            <div class="kpi-card">')
    [void]$sb.AppendLine('                <div class="kpi-title">Monitored Services</div>')
    [void]$sb.AppendLine("                <div class='kpi-value'>$runningServices / $totalServices</div>")
    [void]$sb.AppendLine("                <div class='kpi-subtext'>Status: $(Get-BadgeHtml $serviceStatusBadge)</div>")
    [void]$sb.AppendLine('            </div>')

    $errColor = if ($EventMetrics -and $EventMetrics.TotalErrors -gt 0) { '#ef4444' } else { '#10b981' }
    $totalErrCount = if ($EventMetrics) { $EventMetrics.TotalErrors } else { 0 }
    [void]$sb.AppendLine('            <div class="kpi-card">')
    [void]$sb.AppendLine('                <div class="kpi-title">Recent Event Errors</div>')
    [void]$sb.AppendLine("                <div class='kpi-value' style='color:$errColor;'>$totalErrCount</div>")
    [void]$sb.AppendLine('                <div class="kpi-subtext">24h System & Application Logs</div>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </div>')

    # Hardware & OS Specs
    [void]$sb.AppendLine('        <div class="panel">')
    [void]$sb.AppendLine('            <div class="panel-header">')
    [void]$sb.AppendLine('                <div class="panel-title">System Hardware & Operating System Profile</div>')
    [void]$sb.AppendLine("                <div>$(Get-BadgeHtml 'INFO')</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <div class="info-grid">')
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Computer Name</span><span class='info-val'>$($SystemInfo.Hostname)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Domain / Workgroup</span><span class='info-val'>$($SystemInfo.Domain)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Primary IP Address</span><span class='info-val'>$($SystemInfo.PrimaryIP)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Operating System</span><span class='info-val'>$($SystemInfo.OSName)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>OS Version / Build</span><span class='info-val'>$($SystemInfo.OSVersion)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Architecture</span><span class='info-val'>$($SystemInfo.OSArchitecture)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Hardware Manufacturer</span><span class='info-val'>$($SystemInfo.Manufacturer) $($SystemInfo.Model)</span></div>")
    [void]$sb.AppendLine("                <div class='info-item'><span class='info-label'>Cores / Threads</span><span class='info-val'>$($CpuMetric.PhysicalCores) Cores / $($CpuMetric.LogicalProcessors) Threads</span></div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </div>')

    # Storage Disk Partitions
    [void]$sb.AppendLine('        <div class="panel">')
    [void]$sb.AppendLine('            <div class="panel-header">')
    [void]$sb.AppendLine('                <div class="panel-title">Storage Drive Capacity & Utilization</div>')
    [void]$sb.AppendLine("                <div>$(Get-BadgeHtml 'STORAGE')</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <table>')
    [void]$sb.AppendLine('                <thead><tr><th>Drive</th><th>Volume Label</th><th>File System</th><th>Total Capacity</th><th>Used Space</th><th>Free Space</th><th>Utilization Bar</th><th>Status</th></tr></thead>')
    [void]$sb.AppendLine("                <tbody>$diskRows</tbody>")
    [void]$sb.AppendLine('            </table>')
    [void]$sb.AppendLine('        </div>')

    # Windows Services Table
    [void]$sb.AppendLine('        <div class="panel">')
    [void]$sb.AppendLine('            <div class="panel-header">')
    [void]$sb.AppendLine('                <div class="panel-title">Monitored Windows Services & Automation Health</div>')
    [void]$sb.AppendLine("                <div>$(Get-BadgeHtml $serviceStatusBadge)</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <table>')
    [void]$sb.AppendLine('                <thead><tr><th>Service ID</th><th>Display Name</th><th>Startup Type</th><th>Execution Status</th><th>Health Policy</th><th>Remediation / Diagnostic Note</th></tr></thead>')
    [void]$sb.AppendLine("                <tbody>$serviceRows</tbody>")
    [void]$sb.AppendLine('            </table>')
    [void]$sb.AppendLine('        </div>')

    # Event Logs
    [void]$sb.AppendLine('        <div class="panel">')
    [void]$sb.AppendLine('            <div class="panel-header">')
    [void]$sb.AppendLine('                <div class="panel-title">Windows Event Log Anomaly Audit (Last 24 Hours)</div>')
    $evtStatusBadge = if ($EventMetrics -and $EventMetrics.TotalErrors -gt 0) { "WARNING" } else { "HEALTHY" }
    [void]$sb.AppendLine("                <div>$(Get-BadgeHtml $evtStatusBadge)</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <table>')
    [void]$sb.AppendLine('                <thead><tr><th>Timestamp</th><th>Log</th><th>Severity</th><th>Event ID</th><th>Source Provider</th><th>Event Description</th></tr></thead>')
    [void]$sb.AppendLine("                <tbody>$eventRows</tbody>")
    [void]$sb.AppendLine('            </table>')
    [void]$sb.AppendLine('        </div>')

    # Footer
    [void]$sb.AppendLine('        <footer>')
    [void]$sb.AppendLine('            <div><strong>WinInfraMonitor</strong> &mdash; Systems Administration Automation Suite</div>')
    [void]$sb.AppendLine('            <div>Associate Systems Administrator Portfolio | Thermo Fisher Scientific Target Role</div>')
    [void]$sb.AppendLine('        </footer>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    $sb.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    return $OutputPath
}
