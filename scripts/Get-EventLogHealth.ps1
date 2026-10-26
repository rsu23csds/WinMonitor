<#
.SYNOPSIS
    Queries recent Windows Event Log warnings and errors.
.DESCRIPTION
    Module for WinInfraMonitor. Scans System and Application event logs over a specified
    lookback period to detect system instability, driver issues, or application crashes.
#>

function Get-RecentSystemEvents {
    [CmdletBinding()]
    param(
        [int]$LookbackHours = 24,
        [int]$MaxEvents = 10,
        [int[]]$IncludeLevels = @(1, 2) # 1 = Critical, 2 = Error, 3 = Warning
    )

    $eventsCollected = @()
    $startTime = (Get-Date).AddHours(-$LookbackHours)
    $logsToScan = @("System", "Application")

    foreach ($log in $logsToScan) {
        try {
            $filter = @{
                LogName   = $log
                Level     = $IncludeLevels
                StartTime = $startTime
            }

            $rawEvents = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction SilentlyContinue

            if ($rawEvents) {
                foreach ($evt in $rawEvents) {
                    $levelName = switch ($evt.Level) {
                        1 { "Critical" }
                        2 { "Error" }
                        3 { "Warning" }
                        default { "Information" }
                    }

                    $msg = $evt.Message
                    if ([string]::IsNullOrWhiteSpace($msg)) {
                        $msg = "No description provided by event source."
                    }
                    else {
                        $msg = ($msg -replace "[\r\n]+", " ").Trim()
                        if ($msg.Length -gt 180) {
                            $msg = $msg.Substring(0, 177) + "..."
                        }
                    }

                    $eventsCollected += [PSCustomObject]@{
                        TimeCreated = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                        LogName     = $log
                        Level       = $levelName
                        EventId     = $evt.Id
                        Provider    = $evt.ProviderName
                        Message     = $msg
                    }
                }
            }
        }
        catch {
            Write-Verbose "No events or unable to query local log '$log': $_"
        }
    }

    $sortedEvents = @()
    if ($eventsCollected.Count -gt 0) {
        $sortedEvents = $eventsCollected |
            Sort-Object { $_.TimeCreated } -Descending |
            Select-Object -First $MaxEvents
    }

    $errorCount = ($eventsCollected | Where-Object { $_.Level -in @("Error", "Critical") }).Count
    $warningCount = ($eventsCollected | Where-Object { $_.Level -eq "Warning" }).Count

    return [PSCustomObject]@{
        TotalErrors   = $errorCount
        TotalWarnings = $warningCount
        Events        = @($sortedEvents)
    }
}
