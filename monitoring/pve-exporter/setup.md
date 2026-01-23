# PVE Exporter Setup

## Installation on Proxmox Host

```bash
# Install via pip in venv
apt install python3-pip python3-venv -y
python3 -m venv /opt/pve-exporter
/opt/pve-exporter/bin/pip install prometheus-pve-exporter
```

## Configuration

Create config file:

```bash
mkdir -p /etc/pve-exporter

cat > /etc/pve-exporter/pve.yml << 'EOF'
default:
  user: root@pam
  token_name: pve-exporter
  token_value: YOUR_API_TOKEN_HERE
  verify_ssl: false
EOF

chmod 600 /etc/pve-exporter/pve.yml
```

### Create API Token in Proxmox

1. Proxmox Web UI → **Datacenter** → **Permissions** → **API Tokens**
2. Click **Add**
3. User: `root@pam`
4. Token ID: `pve-exporter`
5. **Uncheck** "Privilege Separation"
6. Copy the token value (shown only once)

## Systemd Service

```bash
cat > /etc/systemd/system/pve-exporter.service << 'EOF'
[Unit]
Description=Prometheus PVE Exporter
After=network.target

[Service]
ExecStart=/opt/pve-exporter/bin/pve_exporter --config.file /etc/pve-exporter/pve.yml --web.listen-address 0.0.0.0:9221
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now pve-exporter
```

## Verify

```bash
curl http://localhost:9221/pve | head
```

## Prometheus Scrape Config

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'pve'
    static_configs:
      - targets: ['10.0.50.10:9221']
    metrics_path: /pve
    params:
      target: ['10.0.50.10']
      cluster: ['1']
      node: ['1']
```
