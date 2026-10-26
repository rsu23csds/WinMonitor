<#
.SYNOPSIS
    Gathers operating system, hardware, CPU, memory, and disk storage metrics.
.DESCRIPTION
    Module for WinInfraMonitor. Uses CIM (Common Information Model) to query local Windows
    hardware and OS performance metrics efficiently on Windows 10, Windows 11, and Windows Server.
#>

function Get-HostSystemInfo {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        $lastBoot = $os.LastBootUpTime
        $uptimeSpan = (Get-Date) - $lastBoot
        $uptimeFormatted = "{0}d {1}h {2}m {3}s" -f $uptimeSpan.Days, $uptimeSpan.Hours, $uptimeSpan.Minutes, $uptimeSpan.Seconds

        # Resolve primary active IPv4 address
        $ipAddress = "127.0.0.1"
        try {
            $activeNet = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "*" -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' } |
                Select-Object -First 1
            if ($activeNet) {
                $ipAddress = $activeNet.IPAddress
            }
        }
        catch {
            $wmiNet = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = TRUE" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($wmiNet -and $wmiNet.IPAddress) {
                $ipAddress = $wmiNet.IPAddress[0]
            }
        }

        return [PSCustomObject]@{
            Hostname        = $env:COMPUTERNAME
            Domain          = $cs.Domain
            Manufacturer    = $cs.Manufacturer
            Model           = $cs.Model
            OSName          = $os.Caption
            OSVersion       = $os.Version
            OSArchitecture  = $os.OSArchitecture
            LastBootUpTime  = $lastBoot
            UptimeFormatted = $uptimeFormatted
            UptimeDays      = [Math]::Round($uptimeSpan.TotalDays, 2)
            PrimaryIP       = $ipAddress
        }
    }
    catch {
        Write-Warning "Failed to query system information: $_"
        return [PSCustomObject]@{
            Hostname        = $env:COMPUTERNAME
            Domain          = "WORKGROUP"
            Manufacturer    = "Unknown"
            Model           = "Unknown"
            OSName          = [System.Environment]::OSVersion.VersionString
            OSVersion       = "Unknown"
            OSArchitecture  = (Get-Item env:PROCESSOR_ARCHITECTURE).Value
            LastBootUpTime  = (Get-Date)
            UptimeFormatted = "N/A"
            UptimeDays      = 0
            PrimaryIP       = "127.0.0.1"
        }
    }
}

function Get-CpuMetric {
    [CmdletBinding()]
    param(
        [double]$WarningThreshold = 75,
        [double]$CriticalThreshold = 90
    )

    try {
        $processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $cpuLoadAvg = ($processors | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -eq $cpuLoadAvg) { $cpuLoadAvg = 0 }
        $cpuLoadAvg = [Math]::Round([double]$cpuLoadAvg, 1)

        $coreCount = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        $logicalCount = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $cpuName = ($processors | Select-Object -First 1).Name

        $status = "HEALTHY"
        if ($cpuLoadAvg -ge $CriticalThreshold) {
            $status = "CRITICAL"
        }
        elseif ($cpuLoadAvg -ge $WarningThreshold) {
            $status = "WARNING"
        }

        return [PSCustomObject]@{
            ProcessorName     = $cpuName
            PhysicalCores     = $coreCount
            LogicalProcessors = $logicalCount
            UsagePercent      = $cpuLoadAvg
            Status            = $status
        }
    }
    catch {
        Write-Warning "Failed to query CPU metric: $_"
        return [PSCustomObject]@{
            ProcessorName     = "Unknown Processor"
            PhysicalCores     = 1
            LogicalProcessors = 1
            UsagePercent      = 0.0
            Status            = "UNKNOWN"
        }
    }
}

function Get-MemoryMetric {
    [CmdletBinding()]
    param(
        [double]$WarningThreshold = 80,
        [double]$CriticalThreshold = 90
    )

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalKB = [double]$os.TotalVisibleMemorySize
        $freeKB = [double]$os.FreePhysicalMemory
        $usedKB = $totalKB - $freeKB

        $totalGB = [Math]::Round(($totalKB / 1024 / 1024), 2)
        $freeGB = [Math]::Round(($freeKB / 1024 / 1024), 2)
        $usedGB = [Math]::Round(($usedKB / 1024 / 1024), 2)

        $usedPercent = 0.0
        $freePercent = 0.0
        if ($totalKB -gt 0) {
            $usedPercent = [Math]::Round(($usedKB / $totalKB) * 100, 1)
            $freePercent = [Math]::Round(($freeKB / $totalKB) * 100, 1)
        }

        $status = "HEALTHY"
        if ($usedPercent -ge $CriticalThreshold) {
            $status = "CRITICAL"
        }
        elseif ($usedPercent -ge $WarningThreshold) {
            $status = "WARNING"
        }

        return [PSCustomObject]@{
            TotalMemoryGB = $totalGB
            UsedMemoryGB  = $usedGB
            FreeMemoryGB  = $freeGB
            UsagePercent  = $usedPercent
            FreePercent   = $freePercent
            Status        = $status
        }
    }
    catch {
        Write-Warning "Failed to query Memory metric: $_"
        return [PSCustomObject]@{
            TotalMemoryGB = 0.0
            UsedMemoryGB  = 0.0
            FreeMemoryGB  = 0.0
            UsagePercent  = 0.0
            FreePercent   = 0.0
            Status        = "UNKNOWN"
        }
    }
}

function Get-DiskMetrics {
    [CmdletBinding()]
    param(
        [double]$WarningFreePercent = 15,
        [double]$CriticalFreePercent = 10
    )

    try {
        # Query local fixed hard drives (DriveType = 3)
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop
        $results = @()

        foreach ($disk in $disks) {
            $totalBytes = [double]$disk.Size
            $freeBytes = [double]$disk.FreeSpace
            $usedBytes = $totalBytes - $freeBytes

            $totalGB = [Math]::Round(($totalBytes / 1GB), 2)
            $freeGB  = [Math]::Round(($freeBytes / 1GB), 2)
            $usedGB  = [Math]::Round(($usedBytes / 1GB), 2)

            $freePercent = 0.0
            $usedPercent = 0.0
            if ($totalBytes -gt 0) {
                $freePercent = [Math]::Round(($freeBytes / $totalBytes) * 100, 1)
                $usedPercent = [Math]::Round(($usedBytes / $totalBytes) * 100, 1)
            }

            $status = "HEALTHY"
            if ($freePercent -le $CriticalFreePercent) {
                $status = "CRITICAL"
            }
            elseif ($freePercent -le $WarningFreePercent) {
                $status = "WARNING"
            }

            $results += [PSCustomObject]@{
                DriveLetter  = $disk.DeviceID
                VolumeName   = if ([string]::IsNullOrWhiteSpace($disk.VolumeName)) { "Local Disk" } else { $disk.VolumeName }
                FileSystem   = $disk.FileSystem
                TotalSizeGB  = $totalGB
                UsedSpaceGB  = $usedGB
                FreeSpaceGB  = $freeGB
                FreePercent  = $freePercent
                UsedPercent  = $usedPercent
                Status       = $status
            }
        }

        return $results
    }
    catch {
        Write-Warning "Failed to query Disk metrics: $_"
        return @()
    }
}
