# Windows Exporter Setup Guide

Prometheus Windows Exporter for monitoring Windows hosts.

- **Repository**: [prometheus-community/windows_exporter](https://github.com/prometheus-community/windows_exporter)
- **Latest Version**: v0.31.3
- **Default Port**: 9182

## 1. Installation

### Download

Download the MSI installer from the [GitHub Releases](https://github.com/prometheus-community/windows_exporter/releases) page.

Direct download link (amd64):

```
https://github.com/prometheus-community/windows_exporter/releases/download/v0.31.3/windows_exporter-0.31.3-amd64.msi
```

### PowerShell Installation (Silent)

Run PowerShell as Administrator:

```powershell
# Download the installer
$version = "0.31.3"
$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v${version}/windows_exporter-${version}-amd64.msi"
$output = "$env:TEMP\windows_exporter-${version}-amd64.msi"

Invoke-WebRequest -Uri $url -OutFile $output

# Install silently with default collectors
msiexec /i $output /qn

# Or install with specific collectors and port
msiexec /i $output /qn --% ENABLED_COLLECTORS=cpu,cs,logical_disk,memory,net,os,service,system LISTEN_PORT=9182
```

### Service Management

The MSI installer automatically registers `windows_exporter` as a Windows service.

```powershell
# Check service status
Get-Service -Name "windows_exporter"

# Start the service
Start-Service -Name "windows_exporter"

# Ensure service starts automatically on boot
Set-Service -Name "windows_exporter" -StartupType Automatic

# Restart the service (after config changes)
Restart-Service -Name "windows_exporter"
```

### Firewall Rule

The MSI installer creates a firewall exception automatically. If needed manually:

```powershell
# Create inbound firewall rule for port 9182
New-NetFirewallRule `
    -DisplayName "Windows Exporter (Prometheus)" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 9182 `
    -Action Allow `
    -Profile Any `
    -Description "Allow Prometheus to scrape Windows Exporter metrics on port 9182"
```

## 2. Collectors

### Default Enabled Collectors

The following collectors are enabled by default:

| Collector | Description |
|-----------|-------------|
| `cpu` | CPU usage metrics (per core and total) |
| `cs` | Computer system info (hostname, domain) |
| `logical_disk` | Disk space usage, read/write IOPS |
| `memory` | Memory usage (physical and virtual) |
| `net` | Network interface traffic and errors |
| `os` | OS version, uptime, paging file usage |
| `physical_disk` | Physical disk performance counters |
| `service` | Windows service state monitoring |
| `system` | System-level counters (context switches, threads) |

### Configuring Collectors

#### Via MSI Installer

```powershell
# Specify collectors during installation
msiexec /i windows_exporter-0.31.3-amd64.msi /qn --% ENABLED_COLLECTORS=cpu,cs,logical_disk,memory,net,os,service,system
```

#### Via Command Line

```powershell
# Run with specific collectors
.\windows_exporter.exe --collectors.enabled="cpu,memory,logical_disk,net,os,service,system"

# Use [defaults] placeholder and add extra collectors
.\windows_exporter.exe --collectors.enabled="[defaults],iis,mssql"
```

#### Via YAML Config File

Create a configuration file (e.g., `C:\Program Files\windows_exporter\config.yml`):

```yaml
collectors:
  enabled: cpu,cs,logical_disk,memory,net,os,physical_disk,service,system
collector:
  service:
    include: "windows_exporter|W3SVC|MSSQLSERVER"
```

Apply the config file:

```powershell
# During MSI installation
msiexec /i windows_exporter-0.31.3-amd64.msi /qn --% CONFIG_FILE="C:\Program Files\windows_exporter\config.yml"
```

### Additional Useful Collectors

| Collector | Use Case |
|-----------|----------|
| `iis` | IIS web server metrics |
| `mssql` | SQL Server performance |
| `process` | Per-process CPU and memory |
| `tcp` | TCP connection states |
| `thermalzone` | Temperature sensors |
| `scheduled_task` | Scheduled task status |

## 3. Prometheus Scrape Configuration

Add the following job to `prometheus.yml` on the Prometheus server (10.0.0.220):

```yaml
scrape_configs:
  # Windows hosts via windows_exporter
  - job_name: "windows_exporter"
    scrape_interval: 30s
    scrape_timeout: 10s
    static_configs:
      - targets:
          - "10.0.0.10:9182"    # Example: Windows workstation
          - "10.0.0.11:9182"    # Example: Windows server 1
          - "10.0.0.12:9182"    # Example: Windows server 2
        labels:
          env: "local"
```

After editing `prometheus.yml`, reload the configuration:

```bash
# Hot reload via HTTP API
curl -X POST http://10.0.0.220:9090/-/reload

# Or restart the Prometheus container
docker restart monitoring-lab-prometheus
```

### Using File-Based Service Discovery (Optional)

For dynamic target management, use file-based service discovery:

```yaml
scrape_configs:
  - job_name: "windows_exporter"
    scrape_interval: 30s
    file_sd_configs:
      - files:
          - "/etc/prometheus/targets/windows_targets.json"
        refresh_interval: 5m
```

Target file (`windows_targets.json`):

```json
[
  {
    "targets": ["10.0.0.10:9182", "10.0.0.11:9182"],
    "labels": {
      "env": "local",
      "os": "windows"
    }
  }
]
```

## 4. Verification

### On the Windows Host

```powershell
# 1. Check service is running
Get-Service -Name "windows_exporter"

# 2. Test metrics endpoint locally
Invoke-WebRequest -Uri "http://localhost:9182/metrics" -UseBasicParsing | Select-Object -First 20

# 3. Check listening port
netstat -an | findstr "9182"

# 4. Verify specific metric is present
(Invoke-WebRequest -Uri "http://localhost:9182/metrics" -UseBasicParsing).Content | Select-String "windows_os_info"
```

### From Prometheus Server

```bash
# Test connectivity from Prometheus host (10.0.0.220)
curl -s http://<WINDOWS_HOST_IP>:9182/metrics | head -20

# Check target status in Prometheus
curl -s http://10.0.0.220:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="windows_exporter")'
```

### In Prometheus Web UI

1. Open http://10.0.0.220:9090/targets
2. Locate the `windows_exporter` job
3. Confirm all targets show **State: UP**
4. Run a test query: `windows_os_info` or `rate(windows_cpu_time_total[5m])`

## 5. Troubleshooting

| Symptom | Possible Cause | Fix |
|---------|---------------|-----|
| Service not starting | Port conflict | Check `netstat -an \| findstr 9182`, change port if needed |
| Prometheus target DOWN | Firewall blocking | Verify firewall rule, test with `Test-NetConnection` |
| Missing metrics | Collector not enabled | Check enabled collectors in service arguments |
| High CPU usage | Too many collectors | Reduce enabled collectors or increase scrape interval |

```powershell
# Check windows_exporter service logs
Get-WinEvent -LogName Application -FilterXPath "*[System[Provider[@Name='windows_exporter']]]" -MaxEvents 10

# Test network connectivity from another host
Test-NetConnection -ComputerName <TARGET_IP> -Port 9182
```

## References

- [windows_exporter GitHub Repository](https://github.com/prometheus-community/windows_exporter)
- [Releases / Downloads](https://github.com/prometheus-community/windows_exporter/releases)
- [Collector Documentation](https://github.com/prometheus-community/windows_exporter/tree/master/docs)
