# WinInfraMonitor - IT Infrastructure Monitoring & Automation Suite

> **Lightweight, Zero-Dependency Windows Health Monitoring & Self-Healing Tool for Systems Administrators**  
> *Targeted Role: Associate Systems Administrator | Thermo Fisher Scientific IT Infrastructure*

---

## 📌 Executive Summary

**WinInfraMonitor** is a modular, native PowerShell-based infrastructure health monitoring and automated remediation platform. It provides real-time performance analytics, capacity tracking, critical Windows services supervision, and event log auditing on standard Windows workstations and Windows Servers without requiring third-party agents, database dependencies, or paid software.

---

## 🛠️ Key Capabilities & Features

1. **Native & Agentless**:
   - Runs out-of-the-box on standard Windows PCs (Windows 10, Windows 11, Windows Server 2016/2019/2022/2025).
   - Zero software installations or paid licenses required.

2. **Core System Metrics Monitored**:
   - **CPU Utilization**: Multi-core processor load sampling with configurable Warning (75%) and Critical (90%) thresholds.
   - **Physical Memory (RAM)**: Allocation tracking (Total GB, Used GB, Free GB, Percentage Used) with threshold breach alerts.
   - **Storage Drive Capacity**: Automated enumeration of all local fixed drives (`DriveType=3`) with used/free capacity analysis and color-coded status badges.
   - **System Identity & Uptime**: OS caption, build number, architecture, domain/workgroup, primary IP, last reboot timestamp, and formatted uptime days/hours.

3. **Critical Windows Services Supervision & Self-Healing Automation**:
   - Audits core infrastructure services: `Spooler`, `wuauserv`, `EventLog`, `Dhcp`, `Dnscache`, `LanmanServer`, `WinDefend`.
   - **Self-Healing Automation Engine**: Automatically detects stopped services configured with `Automatic` startup mode and safely triggers automated recovery restarts with full audit logging.

4. **Proactive Diagnostic Event Log Auditing**:
   - Scans Windows `System` and `Application` logs over a configurable lookback window (default: 24 hours) for Level 1 (Critical) and Level 2 (Error) events to pinpoint driver failures, DCOM errors, or application crashes.

5. **Multi-Format Enterprise Reporting**:
   - **Executive HTML Dashboard**: Standalone, dark-mode responsive HTML report styled after modern observability suites (Datadog/SolarWinds) with KPI metric cards, progress bars, and status badges.
   - **Historical CSV Performance Log**: Appends metrics to `reports/SystemMetrics_History.csv` for trend analysis and capacity planning across multiple runs.
   - **JSON Audit Snapshots**: Structured machine-readable snapshots (`Audit_Snapshot_<HOSTNAME>_<timestamp>.json`) for ingestion into SIEMs, ServiceNow CMDB, or REST APIs.

---

## 📁 Repository Structure

```
├── config/
│   └── config.json                  # Centralized threshold & service configuration
├── scripts/
│   ├── Get-SystemMetrics.ps1        # CPU, RAM, Disk, and OS metrics collector
│   ├── Test-ServiceStatus.ps1       # Service supervision & self-healing automation
│   ├── Get-EventLogHealth.ps1       # System & Application event log anomaly auditor
│   └── Export-HtmlReport.ps1        # Executive HTML dashboard generation engine
├── reports/                         # Auto-generated reports and audit logs
│   ├── SystemMetrics_History.csv    # Historical performance metrics CSV
│   ├── SystemHealth_<HOST>_<TS>.html# Detailed HTML dashboard
│   ├── Latest_Report.html           # Quick-access latest dashboard copy
│   └── Audit_Snapshot_<HOST>.json   # Raw JSON diagnostic snapshot
├── Monitor-Infrastructure.ps1       # Master CLI & Interactive Orchestrator
├── Start-Monitor.bat                # 1-Click Windows Batch launcher
└── README.md                        # Technical documentation & guide
```

---

## 🚀 Quick Start Guide

### 1. Run Health Diagnostic (1-Click)
Double-click `Start-Monitor.bat` in the project root. This executes the health scan and opens the HTML dashboard in your default browser.

### 2. Run via PowerShell CLI

```powershell
# Standard local scan
powershell -ExecutionPolicy Bypass -File .\Monitor-Infrastructure.ps1

# Launch the interactive systems administration console
powershell -ExecutionPolicy Bypass -File .\Monitor-Infrastructure.ps1 -Interactive

# Run in read-only audit mode without restarting any services
powershell -ExecutionPolicy Bypass -File .\Monitor-Infrastructure.ps1 -AuditOnly

# Automatically open report after execution
powershell -ExecutionPolicy Bypass -File .\Monitor-Infrastructure.ps1 -OpenReport
```

---

## 🔒 Security & Least-Privilege Design

- **Safe Remediation Limits**: Service auto-restart is strictly restricted to services marked with `Automatic` startup type, preventing accidental execution of manual or disabled services.
- **Audit Logging**: Every action, metric, and service restart is timestamped and recorded in CSV and JSON formats for audit compliance.
- **Zero Inbound Ports**: Runs purely in user/admin context without opening listening network ports.

---

