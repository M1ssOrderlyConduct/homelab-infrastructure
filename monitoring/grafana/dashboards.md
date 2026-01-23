# Grafana Dashboard Reference

## Proxmox Dashboards

| ID | Name | Data Source | Link |
|----|------|-------------|------|
| **10347** | Proxmox via Prometheus | Prometheus | https://grafana.com/grafana/dashboards/10347-proxmox-via-prometheus/ |
| **10048** | Proxmox | InfluxDB | https://grafana.com/grafana/dashboards/10048-proxmox/ |
| **15356** | Proxmox Cluster Flux | InfluxDB 2.0 | https://grafana.com/grafana/dashboards/15356-proxmox-cluster-flux/ |
| **23855** | Proxmox VE Dashboard | OpenTelemetry (Proxmox 9) | https://grafana.com/grafana/dashboards/23855-proxmox-ve-dashboard/ |
| **1147** | Proxmox Top 10 Hogs | Graphite | https://grafana.com/grafana/dashboards/1147-proxmox-top-10-hogs/ |
| **1860** | Node Exporter Full | Prometheus | https://grafana.com/grafana/dashboards/1860-node-exporter-full/ |

## NVIDIA GPU Dashboards

| ID | Name | Use Case | Link |
|----|------|----------|------|
| **12239** | NVIDIA DCGM Exporter | GPU metrics via dcgm-exporter | https://grafana.com/grafana/dashboards/12239-nvidia-dcgm-exporter-dashboard/ |
| **14574** | Nvidia GPU Metrics | nvidia_gpu_exporter | https://grafana.com/grafana/dashboards/14574-nvidia-gpu-metrics/ |
| **19476** | Nvidia GPU Metrics (Instances) | Multi-GPU monitoring | https://grafana.com/grafana/dashboards/19476-nvidia-gpu-metrics-over-instances/ |
| **23382** | NVIDIA DCGM for Kubernetes | K8s + MIG GPUs | https://grafana.com/grafana/dashboards/23382-nvidia-mig-dcgm/ |
| **6387** | Nvidia GPU | Basic GPU stats | https://grafana.com/grafana/dashboards/6387-gpus/ |
| **17742** | GPU Capacity Dashboard | Cluster GPU capacity | https://grafana.com/grafana/dashboards/17742-gpu-capacity-dashboard/ |
| **20243** | GPU Overview | General overview | https://grafana.com/grafana/dashboards/20243-gpu-overview/ |

## AMD GPU Dashboards

| ID | Name | Use Case | Link |
|----|------|----------|------|
| **23434** | AMD Instinct Single Node | AMD Device Metrics Exporter | https://grafana.com/grafana/dashboards/23434-amd-instinct-single-node-dashboard/ |
| **18913** | AMD GPU Nodes | amd_smi_exporter / ROCm | https://grafana.com/grafana/dashboards/18913-amd-gpu-nodes/ |
| **18302** | macOS GPU Intel+AMD | Mac Intel/AMD GPUs | https://grafana.com/grafana/dashboards/18302-macos-gpu/ |
| **11072** | GPU Monitoring | Generic GPU monitoring | https://grafana.com/grafana/dashboards/11072-gpu-monitoring/ |
| **16161** | Windows Gamer Dashboard | Windows + AMD/NVIDIA | https://grafana.com/grafana/dashboards/16161-desktop-gamer-dashboard/ |

## TrueNAS Dashboards

| ID | Name | Data Source | Link |
|----|------|-------------|------|
| **19661** | TrueNAS | Prometheus | https://grafana.com/grafana/dashboards/19661-truenas/ |
| **16745** | TrueNAS Scale | Graphite | https://grafana.com/grafana/dashboards/16745-truenas-scale/ |
| **20439** | TrueNAS Scale Graphite | Graphite | https://grafana.com/grafana/dashboards/20439-truenas-scale/ |
| **20804** | TrueNAS Dashboard | InfluxDB | https://grafana.com/grafana/dashboards/20804-truenas-dashboard/ |
| **12921** | Customized TrueNAS | InfluxDB/Graphite | https://grafana.com/grafana/dashboards/12921-truenas/ |
| **17383** | TrueNAS Core | InfluxDB | https://grafana.com/grafana/dashboards/17383-truenas/ |

## Required Exporters

| Target | Exporter | Port |
|--------|----------|------|
| Proxmox | pve-exporter | 9221 |
| NVIDIA GPU | dcgm-exporter or nvidia_gpu_exporter | 9400 |
| AMD GPU | amd_smi_exporter or rocm_smi_exporter | 9400 |
| TrueNAS | graphite_exporter or node_exporter | 9100 |
| General hosts | node_exporter | 9100 |

## Import Instructions

1. **Dashboards** → **New** → **Import**
2. Enter dashboard ID
3. Click **Load**
4. Select appropriate data source
5. Click **Import**
