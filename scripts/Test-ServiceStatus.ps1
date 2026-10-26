<#
.SYNOPSIS
    Monitors Windows Services and provides automated self-healing remediation.
.DESCRIPTION
    Module for WinInfraMonitor. Checks status and startup configuration of critical Windows
    services and optionally auto-restarts failed/stopped automatic services.
#>

function Test-MonitoredServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames,

        [Parameter(Mandatory = $false)]
        [bool]$EnableAutoRestart = $false,

        [Parameter(Mandatory = $false)]
        [int]$MaxRestartAttempts = 1
    )

    $results = @()

    foreach ($svcName in $ServiceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue

        if ($null -eq $svc) {
            $results += [PSCustomObject]@{
                ServiceName       = $svcName
                DisplayName       = "Service Not Found"
                Status            = "NOT_INSTALLED"
                StartType         = "N/A"
                HealthStatus      = "WARNING"
                RemediationAction = "Service is not installed on this system"
            }
            continue
        }

        # Resolve Startup Type
        $startType = "Unknown"
        if ($svc.PSObject.Properties['StartType']) {
            $startType = $svc.StartType.ToString()
        }
        else {
            try {
                $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name = '$svcName'" -ErrorAction SilentlyContinue
                if ($wmiSvc) {
                    $startType = $wmiSvc.StartMode
                }
            }
            catch {
                $startType = "Automatic"
            }
        }

        $currentStatus = $svc.Status.ToString()
        $healthStatus = "HEALTHY"
        $remediationAction = "Operating normally"

        if ($currentStatus -eq "Running") {
            $healthStatus = "HEALTHY"
            $remediationAction = "Operating normally"
        }
        elseif ($currentStatus -eq "Stopped") {
            if ($startType -match "Automatic|Auto") {
                $healthStatus = "CRITICAL"
                $remediationAction = "Service is stopped but configured as Automatic"

                if ($EnableAutoRestart) {
                    Write-Verbose "Attempting automated restart for critical service: $svcName"
                    $restartSuccess = $false

                    for ($i = 1; $i -le $MaxRestartAttempts; $i++) {
                        try {
                            Start-Service -Name $svcName -ErrorAction Stop
                            Start-Sleep -Seconds 2
                            $svc.Refresh()

                            if ($svc.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) {
                                $restartSuccess = $true
                                break
                            }
                        }
                        catch {
                            Write-Warning "Attempt $i to restart '$svcName' failed: $_"
                        }
                    }

                    if ($restartSuccess) {
                        $currentStatus = "Running"
                        $healthStatus = "REMEDIATED"
                        $remediationAction = "Auto-restarted successfully by automation engine"
                    }
                    else {
                        $remediationAction = "Auto-restart failed (requires administrative privileges or manual investigation)"
                    }
                }
            }
            else {
                $healthStatus = "INFO"
                $remediationAction = "Stopped (Startup type: $startType)"
            }
        }
        else {
            $healthStatus = "WARNING"
            $remediationAction = "Service in transitional state: $currentStatus"
        }

        $results += [PSCustomObject]@{
            ServiceName       = $svc.Name
            DisplayName       = $svc.DisplayName
            Status            = $currentStatus
            StartType         = $startType
            HealthStatus      = $healthStatus
            RemediationAction = $remediationAction
        }
    }

    return $results
}
