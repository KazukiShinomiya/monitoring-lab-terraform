# Node Exporter Setup Guide

Prometheus Node Exporter v1.10.2 installation on Ubuntu/Debian.

Node Exporter exposes Linux host-level metrics (CPU, memory, disk, network, etc.) on port 9100 for Prometheus to scrape.

## 1. Installation

### 1.1 Create dedicated user

```bash
sudo useradd --no-create-home --shell /bin/false node_exporter
```

### 1.2 Download and install binary

```bash
NODE_EXPORTER_VERSION="1.10.2"

cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Verify checksum
echo "c46e5b6f53948477ff3a19d97c58307394a29fe64a01905646f026ddc32cb65b  node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | sha256sum --check

# Extract and install
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Cleanup
rm -rf /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
```

### 1.3 Verify binary

```bash
node_exporter --version
```

Expected output:

```
node_exporter, version 1.10.2 (branch: HEAD, revision: ...)
```

## 2. systemd Service

### 2.1 Create service file

Create `/etc/systemd/system/node_exporter.service`:

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 2.2 Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
```

### 2.3 Check status

```bash
sudo systemctl status node_exporter
```

## 3. Prometheus Scrape Configuration

Add the following job to `prometheus.yml` under `scrape_configs`:

```yaml
scrape_configs:
  # ... existing jobs ...

  - job_name: 'node_exporter'
    scrape_interval: 15s
    static_configs:
      - targets:
          - 'YOUR_SERVER_IP:9100'   # monitoring server
          # Add more hosts as needed:
          # - 'YOUR_SERVER_IP_2:9100'
          # - 'YOUR_SERVER_IP_3:9100'
        labels:
          env: 'local'
```

After updating the config, reload Prometheus:

```bash
# Hot reload (if --web.enable-lifecycle is enabled)
curl -X POST http://YOUR_SERVER_IP:9090/-/reload

# Or restart the container
docker restart monitoring-lab-prometheus
```

## 4. Firewall (if applicable)

If UFW is enabled, allow port 9100:

```bash
sudo ufw allow 9100/tcp
```

## 5. Verification

### 5.1 Check metrics endpoint

```bash
curl -s http://localhost:9100/metrics | head -20
```

### 5.2 Confirm key metrics are present

```bash
# CPU
curl -s http://localhost:9100/metrics | grep 'node_cpu_seconds_total' | head -3

# Memory
curl -s http://localhost:9100/metrics | grep 'node_memory_MemTotal_bytes'

# Disk
curl -s http://localhost:9100/metrics | grep 'node_filesystem_size_bytes' | head -3

# Network
curl -s http://localhost:9100/metrics | grep 'node_network_receive_bytes_total' | head -3
```

### 5.3 Verify Prometheus target

Open Prometheus targets page at `http://YOUR_SERVER_IP:9090/targets` and confirm the `node_exporter` job shows **UP** status.

### 5.4 Test a PromQL query

In Prometheus UI (`http://YOUR_SERVER_IP:9090/graph`), run:

```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

## 6. Optional: Custom Collectors

Disable or enable specific collectors with flags:

```bash
# Example: disable wifi and infiniband collectors
ExecStart=/usr/local/bin/node_exporter \
  --no-collector.wifi \
  --no-collector.infiniband
```

See all available collectors:

```bash
node_exporter --help 2>&1 | grep collector
```

## References

- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
- [Node Exporter Releases](https://github.com/prometheus/node_exporter/releases)
- [Prometheus Node Exporter Guide](https://prometheus.io/docs/guides/node-exporter/)
