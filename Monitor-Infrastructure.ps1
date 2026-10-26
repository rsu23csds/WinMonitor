<#
.SYNOPSIS
    WinInfraMonitor - IT Infrastructure Monitoring & Automation Tool.
.DESCRIPTION
    A lightweight, enterprise-grade Windows health monitoring and self-healing automation suite.
    Built for Associate Systems Administrators to monitor hardware performance, storage capacity,
    critical Windows services, and event log anomalies on a standard Windows workstation or server.
.PARAMETER ConfigPath
    Path to configuration JSON file. Defaults to './config/config.json'.
.PARAMETER AutoRemediate
    Enables automatic restart of stopped services that have startup type 'Automatic'.
.PARAMETER AuditOnly
    Forces read-only audit mode without attempting any service remediation.
.PARAMETER Interactive
    Launches an interactive console menu interface.
.PARAMETER OpenReport
    Automatically opens the generated HTML dashboard in the default web browser upon completion.
.PARAMETER SkipEventLogs
    Skips Windows Event Log scanning for faster operational execution.
.EXAMPLE
    .\Monitor-Infrastructure.ps1
    Runs standard monitoring scan, writes console output, and generates HTML/CSV/JSON reports.
.EXAMPLE
    .\Monitor-Infrastructure.ps1 -OpenReport
    Runs the scan and launches the HTML report directly in your default browser.
.EXAMPLE
    .\Monitor-Infrastructure.ps1 -Interactive
    Launches the interactive menu for administrative operations.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [switch]$AutoRemediate,
    [switch]$AuditOnly,
    [switch]$Interactive,
    [switch]$OpenReport,
    [switch]$SkipEventLogs
)

$ErrorActionPreference = "Continue"

# Resolve script root
$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = (Get-Location).Path
}

# Resolve config path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot "config\config.json"
}

# Source modular script libraries
$scriptsDir = Join-Path $scriptRoot "scripts"
$requiredModules = @(
    "Get-SystemMetrics.ps1",
    "Test-ServiceStatus.ps1",
    "Get-EventLogHealth.ps1",
    "Export-HtmlReport.ps1"
)

foreach ($module in $requiredModules) {
    $modPath = Join-Path $scriptsDir $module
    if (Test-Path $modPath) {
        . $modPath
    }
    else {
        Write-Error "Critical module missing: $modPath"
        exit 1
    }
}

# Load and validate configuration
function Get-AppConfig {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            $rawJson = Get-Content -Path $Path -Raw | ConvertFrom-Json
            return $rawJson
        }
        catch {
            Write-Warning "Could not parse JSON config at '$Path'. Loading safe defaults."
        }
    }
    else {
        Write-Warning "Config file not found at '$Path'. Using safe defaults."
    }

    # Safe built-in defaults
    return [PSCustomObject]@{
        SystemName = "Windows Workstation / Local Server"
        Thresholds = [PSCustomObject]@{
            CpuWarningPercent       = 75
            CpuCriticalPercent      = 90
            MemoryWarningPercent    = 80
            MemoryCriticalPercent   = 90
            DiskWarningFreePercent  = 15
            DiskCriticalFreePercent = 10
        }
        MonitoredServices = @("Spooler", "wuauserv", "EventLog", "Dhcp", "Dnscache", "LanmanServer", "WinDefend")
        Automation = [PSCustomObject]@{
            EnableAutoRestartStoppedServices = $false
            MaxRestartAttempts = 1
        }
        EventLog = [PSCustomObject]@{
            ScanHours = 24
            MaxEvents = 10
            IncludeLevels = @(1, 2)
        }
        Reporting = [PSCustomObject]@{
            ReportOutputDir = "./reports"
            GenerateHtml = $true
            GenerateCsv = $true
            GenerateJson = $true
            OpenReportAfterExecution = $false
        }
    }
}

# Core execution function
function Invoke-SystemHealthScan {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Config,
        [bool]$DoAutoRemediate = $false,
        [bool]$DoSkipEventLogs = $false,
        [bool]$DoOpenReport = $false
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scanTimestamp = Get-Date

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  WinInfraMonitor - IT Infrastructure Health Diagnostic & Automation Engine   " -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " [INFO] Initiating diagnostic scan on: $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host " [INFO] Scan Started: $($scanTimestamp.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

    # 1. Host System Info
    Write-Host " [1/5] Querying System Information and Uptime..." -ForegroundColor Yellow -NoNewline
    $sysInfo = Get-HostSystemInfo
    Write-Host " [DONE] ($($sysInfo.Hostname))" -ForegroundColor Green

    # 2. CPU Metrics
    Write-Host " [2/5] Querying Processor Utilization..." -ForegroundColor Yellow -NoNewline
    $cpuMetric = Get-CpuMetric -WarningThreshold $Config.Thresholds.CpuWarningPercent -CriticalThreshold $Config.Thresholds.CpuCriticalPercent
    Write-Host " [DONE] ($($cpuMetric.UsagePercent)%)" -ForegroundColor Green

    # 3. Memory Metrics
    Write-Host " [3/5] Querying Physical Memory Allocation..." -ForegroundColor Yellow -NoNewline
    $memMetric = Get-MemoryMetric -WarningThreshold $Config.Thresholds.MemoryWarningPercent -CriticalThreshold $Config.Thresholds.MemoryCriticalPercent
    Write-Host " [DONE] ($($memMetric.UsagePercent)% Used - $($memMetric.UsedMemoryGB)GB / $($memMetric.TotalMemoryGB)GB)" -ForegroundColor Green

    # 4. Storage Disk Metrics
    Write-Host " [4/5] Querying Storage Partitions & Disk Capacity..." -ForegroundColor Yellow -NoNewline
    $diskMetrics = Get-DiskMetrics -WarningFreePercent $Config.Thresholds.DiskWarningFreePercent -CriticalFreePercent $Config.Thresholds.DiskCriticalFreePercent
    Write-Host " [DONE] ($($diskMetrics.Count) drive(s) detected)" -ForegroundColor Green

    # 5. Windows Services & Self-Healing
    Write-Host " [5/5] Auditing Monitored Services & Automation Policies..." -ForegroundColor Yellow -NoNewline
    $servicesToMonitor = @($Config.MonitoredServices)
    $serviceMetrics = Test-MonitoredServices -ServiceNames $servicesToMonitor -EnableAutoRestart $DoAutoRemediate -MaxRestartAttempts $Config.Automation.MaxRestartAttempts
    Write-Host " [DONE]" -ForegroundColor Green

    # 6. Event Logs (Optional)
    $eventMetrics = $null
    if (-not $DoSkipEventLogs) {
        Write-Host " [*] Scanning Windows Event Logs for critical errors..." -ForegroundColor Yellow -NoNewline
        $eventMetrics = Get-RecentSystemEvents -LookbackHours $Config.EventLog.ScanHours -MaxEvents $Config.EventLog.MaxEvents -IncludeLevels $Config.EventLog.IncludeLevels
        Write-Host " [DONE] ($($eventMetrics.TotalErrors) error(s), $($eventMetrics.TotalWarnings) warning(s))" -ForegroundColor Green
    }

    $stopwatch.Stop()
    $totalSeconds = $stopwatch.Elapsed.TotalSeconds

    # Calculate Overall Status
    $overallStatus = "HEALTHY"

    if ($diskMetrics | Where-Object { $_.Status -eq "CRITICAL" }) {
        $overallStatus = "CRITICAL"
    }
    elseif ($diskMetrics | Where-Object { $_.Status -eq "WARNING" }) {
        $overallStatus = "WARNING"
    }

    if ($cpuMetric.Status -eq "CRITICAL") {
        $overallStatus = "CRITICAL"
    }
    elseif (($cpuMetric.Status -eq "WARNING") -and ($overallStatus -ne "CRITICAL")) {
        $overallStatus = "WARNING"
    }

    if ($memMetric.Status -eq "CRITICAL") {
        $overallStatus = "CRITICAL"
    }
    elseif (($memMetric.Status -eq "WARNING") -and ($overallStatus -ne "CRITICAL")) {
        $overallStatus = "WARNING"
    }

    if ($serviceMetrics | Where-Object { $_.HealthStatus -eq "CRITICAL" }) {
        $overallStatus = "CRITICAL"
    }
    elseif (($serviceMetrics | Where-Object { $_.HealthStatus -in @("WARNING", "REMEDIATED") }) -and ($overallStatus -ne "CRITICAL")) {
        $overallStatus = "WARNING"
    }

    # Display Rich Terminal Dashboard
    Write-Host ""
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "                             INFRASTRUCTURE SNAPSHOT                            " -ForegroundColor White
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray

    $overallBg = switch ($overallStatus) {
        "HEALTHY"  { "DarkGreen" }
        "WARNING"  { "DarkYellow" }
        "CRITICAL" { "DarkRed" }
        default    { "DarkGray" }
    }
    Write-Host "  OVERALL SYSTEM STATUS: " -NoNewline
    Write-Host "  [ $overallStatus ]  " -ForegroundColor White -BackgroundColor $overallBg
    Write-Host ""
    Write-Host ("  Hostname:      {0,-20} Primary IP:  {1}" -f $sysInfo.Hostname, $sysInfo.PrimaryIP)
    Write-Host ("  Operating Sys: {0,-20} Build:       {1}" -f $sysInfo.OSName, $sysInfo.OSVersion)
    Write-Host ("  System Uptime: {0,-20} Last Boot:   {1}" -f $sysInfo.UptimeFormatted, $sysInfo.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'))
    Write-Host ("  CPU Load:      {0,-20} Status:      {1}" -f "$($cpuMetric.UsagePercent)%", $cpuMetric.Status)
    Write-Host ("  Memory Load:   {0,-20} Status:      {1}" -f "$($memMetric.UsagePercent)% ($($memMetric.UsedMemoryGB)GB / $($memMetric.TotalMemoryGB)GB)", $memMetric.Status)

    Write-Host ""
    Write-Host "  DRIVE CAPACITY:" -ForegroundColor Cyan
    foreach ($d in $diskMetrics) {
        $color = switch ($d.Status) {
            "HEALTHY"  { "Green" }
            "WARNING"  { "Yellow" }
            "CRITICAL" { "Red" }
            default    { "Gray" }
        }
        Write-Host ("    Drive {0,-3} ({1,-10}): Total: {2,7} GB | Free: {3,7} GB ({4,4}%) | Status: {5}" -f `
            $d.DriveLetter, $d.VolumeName, $d.TotalSizeGB, $d.FreeSpaceGB, $d.FreePercent, $d.Status) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  CRITICAL SERVICES:" -ForegroundColor Cyan
    foreach ($s in $serviceMetrics) {
        $sColor = switch ($s.HealthStatus) {
            "HEALTHY"    { "Green" }
            "REMEDIATED" { "Cyan" }
            "WARNING"    { "Yellow" }
            "CRITICAL"   { "Red" }
            default      { "Gray" }
        }
        Write-Host ("    {0,-15} | Status: {1,-10} | Type: {2,-10} | Health: {3,-10} | {4}" -f `
            $s.ServiceName, $s.Status, $s.StartType, $s.HealthStatus, $s.RemediationAction) -ForegroundColor $sColor
    }

    if ($eventMetrics) {
        Write-Host ""
        Write-Host ("  EVENT LOG AUDIT (Last {0}h): Errors: {1} | Warnings: {2}" -f `
            $Config.EventLog.ScanHours, $eventMetrics.TotalErrors, $eventMetrics.TotalWarnings) -ForegroundColor $(if ($eventMetrics.TotalErrors -gt 0) { "Yellow" } else { "Green" })
    }

    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("  Diagnostic Scan Completed in {0:N2} seconds" -f $totalSeconds) -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan

    # Generate Reports
    $reportsDir = Join-Path $scriptRoot "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }

    $timeSlug = $scanTimestamp.ToString("yyyyMMdd_HHmmss")
    $safeHost = ($sysInfo.Hostname -replace '[^a-zA-Z0-9_\-]', '_').ToUpper()

    $htmlReportPath = Join-Path $reportsDir "SystemHealth_${safeHost}_$timeSlug.html"
    $latestHtmlPath = Join-Path $reportsDir "Latest_Report.html"
    $csvPath        = Join-Path $reportsDir "SystemMetrics_History.csv"
    $jsonPath       = Join-Path $reportsDir "Audit_Snapshot_${safeHost}_$timeSlug.json"

    # 1. HTML Report
    if ($Config.Reporting.GenerateHtml) {
        Export-HtmlHealthDashboard `
            -SystemInfo $sysInfo `
            -CpuMetric $cpuMetric `
            -MemoryMetric $memMetric `
            -DiskMetrics $diskMetrics `
            -ServiceMetrics $serviceMetrics `
            -EventMetrics $eventMetrics `
            -OverallStatus $overallStatus `
            -OutputPath $htmlReportPath `
            -ExecutionTimeSeconds $totalSeconds

        Copy-Item -Path $htmlReportPath -Destination $latestHtmlPath -Force
        Write-Host " [REPORT] HTML Dashboard written to:" -ForegroundColor Green
        Write-Host "          $htmlReportPath" -ForegroundColor White
        Write-Host "          $latestHtmlPath (Latest copy)" -ForegroundColor Gray
    }

    # 2. CSV History Log
    if ($Config.Reporting.GenerateCsv) {
        $primaryDisk = $diskMetrics | Where-Object { $_.DriveLetter -eq "C:" } | Select-Object -First 1
        $cDriveFreePct = if ($primaryDisk) { $primaryDisk.FreePercent } else { "N/A" }
        $failedServicesCount = ($serviceMetrics | Where-Object { $_.HealthStatus -eq "CRITICAL" }).Count

        $csvRecord = [PSCustomObject]@{
            Timestamp            = $scanTimestamp.ToString("yyyy-MM-dd HH:mm:ss")
            Hostname             = $sysInfo.Hostname
            OS                   = $sysInfo.OSName
            PrimaryIP            = $sysInfo.PrimaryIP
            CPU_Usage_Pct        = $cpuMetric.UsagePercent
            RAM_Total_GB         = $memMetric.TotalMemoryGB
            RAM_Used_GB          = $memMetric.UsedMemoryGB
            RAM_Used_Pct         = $memMetric.UsagePercent
            Disk_C_Free_Pct      = $cDriveFreePct
            FailedServices_Count = $failedServicesCount
            EventErrors_Count    = if ($eventMetrics) { $eventMetrics.TotalErrors } else { 0 }
            Overall_Status       = $overallStatus
            Execution_Seconds    = [Math]::Round($totalSeconds, 2)
        }

        $csvRecord | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8
        Write-Host " [REPORT] Metrics appended to CSV history: $csvPath" -ForegroundColor Green
    }

    # 3. JSON Audit Snapshot
    if ($Config.Reporting.GenerateJson) {
        $auditObject = [PSCustomObject]@{
            ScanMetadata = [PSCustomObject]@{
                Timestamp      = $scanTimestamp.ToString("o")
                ExecutionTime  = [Math]::Round($totalSeconds, 2)
                OverallStatus  = $overallStatus
                Host           = $sysInfo.Hostname
            }
            HostProfile     = $sysInfo
            CPU             = $cpuMetric
            Memory          = $memMetric
            Storage         = $diskMetrics
            Services        = $serviceMetrics
            RecentEvents    = $eventMetrics
        }
        $auditObject | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding UTF8 -Force
        Write-Host " [REPORT] JSON Audit Snapshot written to: $jsonPath" -ForegroundColor Green
    }

    Write-Host ""

    # Open HTML report in default browser if requested
    if ($DoOpenReport -or $Config.Reporting.OpenReportAfterExecution) {
        Write-Host " [ACTION] Launching HTML Dashboard report in default browser..." -ForegroundColor Cyan
        Start-Process $latestHtmlPath
    }

    return [PSCustomObject]@{
        Status         = $overallStatus
        HtmlReportPath = $latestHtmlPath
        ExecutionTime  = $totalSeconds
    }
}

# Interactive Menu Console
function Show-InteractiveMenu {
    param([PSCustomObject]$Config)

    while ($true) {
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "           WinInfraMonitor - Systems Administration Control Console             " -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "  1. Run Complete Infrastructure Diagnostic Scan (Generate HTML/CSV/JSON)" -ForegroundColor White
        Write-Host "  2. Run Diagnostic Scan with Automated Service Self-Healing (Auto-Remediate)" -ForegroundColor White
        Write-Host "  3. Open Latest HTML Health Dashboard Report in Browser" -ForegroundColor White
        Write-Host "  4. View Historical Performance Metrics (CSV Summary)" -ForegroundColor White
        Write-Host "  5. Inspect Active Monitored Services & Status" -ForegroundColor White
        Write-Host "  6. View / Inspect Current Threshold Configuration" -ForegroundColor White
        Write-Host "  7. Exit Console" -ForegroundColor White
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host ""
        $choice = Read-Host " Select an option (1-7)"

        switch ($choice) {
            "1" {
                Invoke-SystemHealthScan -Config $Config -DoAutoRemediate $false -DoOpenReport $true
                Write-Host ""
                Read-Host "Press Enter to return to menu..."
            }
            "2" {
                Invoke-SystemHealthScan -Config $Config -DoAutoRemediate $true -DoOpenReport $true
                Write-Host ""
                Read-Host "Press Enter to return to menu..."
            }
            "3" {
                $latestPath = Join-Path $scriptRoot "reports\Latest_Report.html"
                if (Test-Path $latestPath) {
                    Start-Process $latestPath
                    Write-Host "Report launched in browser." -ForegroundColor Green
                } else {
                    Write-Warning "No report found. Please run Option 1 or 2 first."
                }
                Start-Sleep -Seconds 2
            }
            "4" {
                $csvPath = Join-Path $scriptRoot "reports\SystemMetrics_History.csv"
                if (Test-Path $csvPath) {
                    Write-Host ""
                    Write-Host "--- RECENT METRICS HISTORY ---" -ForegroundColor Cyan
                    Import-Csv -Path $csvPath | Select-Object -Last 10 | Format-Table -AutoSize
                } else {
                    Write-Warning "No CSV history file found. Run a diagnostic scan first."
                }
                Write-Host ""
                Read-Host "Press Enter to return to menu..."
            }
            "5" {
                Write-Host ""
                Write-Host "--- MONITORED SERVICES ---" -ForegroundColor Cyan
                Test-MonitoredServices -ServiceNames $Config.MonitoredServices -EnableAutoRestart $false |
                    Format-Table ServiceName, DisplayName, Status, StartType, HealthStatus -AutoSize
                Write-Host ""
                Read-Host "Press Enter to return to menu..."
            }
            "6" {
                Write-Host ""
                Write-Host "--- CURRENT CONFIGURATION (config/config.json) ---" -ForegroundColor Cyan
                $Config | ConvertTo-Json -Depth 5
                Write-Host ""
                Read-Host "Press Enter to return to menu..."
            }
            "7" {
                Write-Host "Exiting WinInfraMonitor Console. Goodbye!" -ForegroundColor Green
                return
            }
            default {
                Write-Warning "Invalid option. Please choose 1 through 7."
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Main Execution Switch
$appConfig = Get-AppConfig -Path $ConfigPath

# Determine auto-remediation flag
$effectiveAutoRemediate = if ($PSBoundParameters.ContainsKey('AutoRemediate')) {
    $AutoRemediate.IsPresent
} elseif ($AuditOnly.IsPresent) {
    $false
} else {
    [bool]$appConfig.Automation.EnableAutoRestartStoppedServices
}

$effectiveOpenReport = if ($PSBoundParameters.ContainsKey('OpenReport')) {
    $OpenReport.IsPresent
} else {
    [bool]$appConfig.Reporting.OpenReportAfterExecution
}

if ($Interactive.IsPresent) {
    Show-InteractiveMenu -Config $appConfig
}
else {
    Invoke-SystemHealthScan `
        -Config $appConfig `
        -DoAutoRemediate $effectiveAutoRemediate `
        -DoSkipEventLogs $SkipEventLogs.IsPresent `
        -DoOpenReport $effectiveOpenReport
}
