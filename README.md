# Distributed Homelab Infrastructure

A comprehensive architecture for a distributed homelab featuring dedicated NAS, firewall with IPS, AI/ML compute cluster, and edge devices. Designed for family media streaming, file storage, backups, software development, and local AI workloads.

## Architecture Overview

```
                              ┌──────────────────┐
                              │     INTERNET     │
                              └────────┬─────────┘
                                       │
                              ┌────────▼─────────┐
                              │   i5-12600K      │
                              │   OPNsense       │
                              │   Suricata IPS   │
                              │   32GB DDR4      │
                              └────────┬─────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
┌────────▼────────┐          ┌────────▼────────┐          ┌────────▼────────┐
│  Proxmox Server │          │  Odroid H4 Ultra│          │    Desktop      │
│  Ryzen 9 9950X  │          │  TrueNAS Scale  │          │  i5-13600K      │
│  128GB DDR5     │          │  32GB DDR5      │          │  64GB DDR5      │
│                 │          │                 │          │                 │
│  ┌───────────┐  │          │  4x14TB RAID-Z2 │          │  Dev work       │
│  │ k3s ctrl  │  │          │  (~28TB usable) │          │  kubectl        │
│  ├───────────┤  │          │                 │          │  SSH/RDP        │
│  │ k3s GPU 1 │◄─┼──────────┼───NFS/iSCSI─────┼──────────┼►               │
│  │ 4070Ti 16G│  │          │                 │          │                 │
│  ├───────────┤  │          │  B580 eGPU      │          │  Radeon 7600    │
│  │ k3s GPU 2 │  │          │  (transcoding)  │          │  (local LLM)    │
│  │ 7900XT 20G│  │          │                 │          │                 │
│  └───────────┘  │          └─────────────────┘          └─────────────────┘
│                 │
│  6700XT 12GB    │                    ┌─────────────────┐
│  (embeddings)   │                    │      Pi5        │
└─────────────────┘                    │  Home Assistant │
                                       │  Frigate + NVR  │
                                       │  Hailo 8L       │
                                       └─────────────────┘
```

## Hardware Inventory

### Proxmox Server (AI/Compute Core)

| Component | Specification |
|-----------|---------------|
| CPU | AMD Ryzen 9 9950X (16 cores / 32 threads) |
| RAM | 128GB DDR5 |
| Motherboard | ASRock X870 Taichi Creator |
| GPU 1 | NVIDIA RTX 4070 Ti Super (16GB VRAM) |
| GPU 2 | AMD Radeon RX 7900 XT (20GB VRAM) |
| GPU 3 | AMD Radeon RX 6700 XT (12GB VRAM) |
| Storage | 1TB NVMe + 2x 512GB NVMe (ZFS mirror) |
| Cooling | 320mm AIO |
| Case | Thermaltake Tower 600 |
| Network | Aquantia AQC113 10GbE + Realtek RTL8126 5GbE |
| Wireless | WiFi 7 (802.11be) + Bluetooth 5.4 |

**Role**: Kubernetes cluster, AI/ML inference, GPU compute, VM hosting

> **Important**: The X870 Taichi Creator has driver considerations for Proxmox. See [X870 Taichi Creator Network Setup Guide](docs/x870-taichi-creator-network-setup.md) for RTL8126 driver installation.

#### Proxmox Network Interfaces

| NIC | Speed | Chip | Linux Driver | Kernel Status |
|-----|-------|------|--------------|---------------|
| 10GbE | 10000 Mbps | Marvell AQC113CS | `atlantic` | In-tree (kernel 5.8+) |
| 5GbE | 5000 Mbps | Realtek RTL8126 | `r8126` | **Out-of-tree DKMS required** |
| WiFi 7 | 802.11be | MediaTek (likely MT7925) | `mt7925e` | In-tree (kernel 6.5+) |

**Recommendation**: Use the 10GbE port (AQC113) during Proxmox installation, then install the `r8126` DKMS driver post-install for 5GbE support. See the [setup guide](docs/x870-taichi-creator-network-setup.md) for detailed instructions.

### TrueNAS Server (Storage)

| Component | Specification |
|-----------|---------------|
| System | Odroid H4 Ultra |
| CPU | Intel N305 (8 cores) |
| RAM | 32GB DDR5 (single SODIMM) |
| Boot Drive | USB 3.0 (128GB NVMe repurposed or dedicated USB drive) |
| Data Drives | 4x 14TB SATA HDD |
| RAID | RAID-Z2 (~28TB usable) |
| Network | 2x Intel i226-V 2.5GbE + 1x 10GbE SFP+ (M.2) |
| eGPU | Intel B580 via OCuLink |

**Role**: Family NAS, media storage, backups, Jellyfin transcoding

#### M.2 Bifurcation Configuration (Odroid)

The Odroid H4 Ultra's M.2 slot is bifurcated using the [M.2 2x2 Card](https://www.hardkernel.com/shop/m-2-2x2-card/) to support both eGPU and 10GbE networking:

```
Odroid H4 Ultra
    │
    └── M.2 PCIe x4 slot
            │
            ▼
    ┌───────────────────┐
    │   M.2 2x2 Card    │
    │   (bifurcates     │
    │    x4 → 2x x2)    │
    └───────┬───────────┘
            │
    ┌───────┴───────┐
    │               │
    ▼               ▼
┌────────┐    ┌────────┐
│ Slot 1 │    │ Slot 2 │
│ x2     │    │ x2     │
│        │    │        │
│ M.2 to │    │ M.2    │
│OCuLink │    │ 10GbE  │
│   ↓    │    │ 82599  │
│ B580   │    │ SFP+   │
│ eGPU   │    │        │
└────────┘    └────────┘
```

**Bandwidth Analysis:**

| Device | Needs | PCIe 3.0 x2 Provides | Status |
|--------|-------|----------------------|--------|
| B580 (transcoding) | ~4GB/s ideal | ~2GB/s | Acceptable for encode/decode |
| 10GbE NIC | ~1.25GB/s | ~2GB/s | Plenty of headroom |

Transcoding workloads (Quick Sync) are not bandwidth-intensive like gaming - x2 lanes are sufficient.

#### Boot Drive Note

With the M.2 slot used for bifurcation, the system boots from USB 3.0. TrueNAS doesn't require NVMe boot speeds - the OS loads once, then ZFS ARC handles everything in RAM. A quality USB drive (Samsung FIT Plus, SanDisk Extreme) works well.

#### 10GbE NIC Details

| Specification | Value |
|---------------|-------|
| Adapter | [Euqvos M.2 10GbE](https://www.amazon.com/dp/B0DDKXVJJ4) |
| Chipset | Intel 82599 |
| Port | SFP+ |
| Speeds | 100/1000/10000 Mbps |
| Driver Support | Native in TrueNAS/FreeBSD/Linux |

**Requires**: SFP+ DAC cable (~$15-20) or SFP+ transceivers for fiber.

#### eGPU Configuration

```
M.2 Slot 1 → M.2-to-OCuLink Adapter → OCuLink Cable → OCuLink-to-PCIe x16 → B580 GPU → External PSU
```

The B580 provides hardware transcoding (AV1/HEVC/H.264) for Jellyfin/Plex, significantly outperforming the N305's integrated graphics.

### Firewall/Router

| Component | Specification |
|-----------|---------------|
| CPU | Intel i5-12600K (10 cores) |
| RAM | 32GB DDR4 |
| Motherboard | ASUS PRIME B660M-A D4 |
| Storage | 1TB NVMe |
| Network | Onboard 2.5GbE + Intel X710-DA2 (10GbE) |
| OS | OPNsense |

**Role**: Network firewall, Suricata IPS/IDS, traffic inspection

#### Suricata Performance

| Internet Speed | Performance |
|----------------|-------------|
| 1 Gbps | Full IPS, no issues |
| 2.5 Gbps | Full IPS, comfortable |
| 5 Gbps | Full IPS with tuning |
| 10 Gbps | Achievable with reduced ruleset |

### Desktop Workstation (New Build)

| Component | Specification |
|-----------|---------------|
| CPU | Intel i5-13600K (14 cores: 6P + 8E) |
| RAM | 64GB DDR5 (4x 16GB) |
| Motherboard | MSI MAG B760M Mortar WiFi DDR5 |
| GPU | AMD Radeon RX 7600 (8GB) |
| Storage | NVMe (existing) |
| PSU | 650W or 750W (existing) |

**Role**: Development workstation, kubectl management, local AI fallback

### Edge Device (Home Automation)

| Component | Specification |
|-----------|---------------|
| System | Raspberry Pi 5 |
| RAM | 8GB |
| Storage | NVMe via USB |
| AI Accelerator | Hailo 8L HAT |
| Software | Home Assistant, Frigate NVR |

**Role**: Home automation, camera AI object detection

---

## Storage Architecture

### Tiered Storage Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                     STORAGE TIERS                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  TIER 1: Fast (Proxmox NVMe)                                   │
│  ├── VM boot disks                                              │
│  ├── Container root filesystems                                 │
│  ├── Database workloads                                         │
│  └── k3s etcd (control plane)                                   │
│                                                                 │
│  TIER 2: Bulk (TrueNAS RAID-Z2)                                │
│  ├── k3s persistent volumes (NFS)                               │
│  ├── Media library (Jellyfin/Plex)                              │
│  ├── Family file shares                                         │
│  ├── Backups                                                    │
│  └── VM backups (Proxmox Backup Server target)                  │
│                                                                 │
│  TIER 3: Archive (Offsite)                                     │
│  └── Backblaze B2 / second location                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Proxmox NVMe Layout

| Drive | Size | Use |
|-------|------|-----|
| 1TB NVMe | 1000GB | Primary VM storage (local-zfs) |
| 512GB NVMe #1 | 512GB | ZFS mirror (redundant) |
| 512GB NVMe #2 | 512GB | ZFS mirror (redundant) |

### TrueNAS Configuration

| Setting | Value |
|---------|-------|
| Pool Type | RAID-Z2 |
| Raw Capacity | 56TB (4x 14TB) |
| Usable Capacity | ~28TB |
| Rebuild Tolerance | 2 drive failures |
| Scrub Schedule | Monthly |

#### Why RAID-Z2?

- 14TB drives have 24-48+ hour rebuild times
- ~1 in 8 chance of URE (Unrecoverable Read Error) during rebuild on drives this large
- RAID-Z1 risks total loss if second drive fails during rebuild
- 14TB capacity hit is worth the safety margin

---

## Network Architecture

### VLAN Design (Recommended)

| VLAN | Purpose | Subnet |
|------|---------|--------|
| 1 | Management | 10.0.1.0/24 |
| 10 | Trusted (Family) | 10.0.10.0/24 |
| 20 | IoT Devices | 10.0.20.0/24 |
| 30 | Servers | 10.0.30.0/24 |
| 40 | Guest | 10.0.40.0/24 |

### Inter-Node Connectivity

| Link | Speed | Notes |
|------|-------|-------|
| Proxmox ↔ TrueNAS | **10GbE (SFP+ DAC)** | Direct connection, critical for NFS |
| Desktop ↔ Proxmox | 2.5GbE | kubectl, SSH, RDP |
| Desktop ↔ TrueNAS | 2.5GbE | File access |
| Pi5 ↔ LAN | 1GbE | Pi5 hardware limit |

#### 10GbE Backbone Topology

```
                         10GbE SFP+ DAC (Direct)
Proxmox (X870 Taichi) ◄─────────────────────────► TrueNAS (M.2 82599)
   │ 10GbE onboard                                    │ 2x 2.5GbE onboard
   │                                                  │
   │ 2.5GbE                                          │ 2.5GbE
   ▼                                                  ▼
┌─────────────────────────────────────────────────────────────┐
│                      2.5GbE Switch                          │
├─────────────────────────────────────────────────────────────┤
│     │              │              │              │          │
│     ▼              ▼              ▼              ▼          │
│  Desktop       Firewall         Pi5          Other         │
│  2.5GbE        2.5GbE          1GbE         Devices        │
└─────────────────────────────────────────────────────────────┘
```

The 10GbE direct link between Proxmox and TrueNAS enables:
- Fast NFS for k3s persistent volumes
- Quick VM backups to TrueNAS
- High-speed iSCSI if needed
- No switch bottleneck for storage traffic

### Remote Access

| Method | Use Case |
|--------|----------|
| Tailscale | Zero-config VPN, works through NAT |
| WireGuard | Direct VPN, requires port forward |
| Cloudflare Tunnel | Web services exposure |

**Recommendation**: Tailscale for simplicity and security. Avoid exposing services directly to the internet.

---

## AI/ML Infrastructure

### GPU Allocation

| GPU | VRAM | Location | Primary Use |
|-----|------|----------|-------------|
| RTX 4070 Ti Super | 16GB | Proxmox | LLM inference (CUDA) |
| RX 7900 XT | 20GB | Proxmox | Large models (ROCm) |
| RX 6700 XT | 12GB | Proxmox | Embeddings, RAG |
| Intel B580 | 12GB | Odroid (eGPU) | Media transcoding |
| RX 7600 | 8GB | Desktop | Local fallback |
| Hailo 8L | N/A | Pi5 | Object detection |

### LLM VRAM Requirements

| Model Size | VRAM (Q4 Quantized) | Suitable GPUs |
|------------|---------------------|---------------|
| 7B | 4-6GB | Any |
| 13B | 8-10GB | 7600, 6700XT, 4070Ti, 7900XT |
| 30-34B | 16-20GB | 4070Ti, 7900XT |
| 70B | 40GB+ | Multi-GPU required |

### Combined VRAM for Large Models

```
4070 Ti (16GB) + 7900 XT (20GB) + 6700 XT (12GB) = 48GB
```

With distributed inference (Exo), can run Llama 3 70B+ models.

### Software Stack

```
┌────────────────────────────────┐
│     Open WebUI (Frontend)      │  ← Chat interface
├────────────────────────────────┤
│     Ollama (Backend)           │  ← Model serving
├────────────────────────────────┤
│     GPU: 4070Ti / 7900XT       │  ← Inference
└────────────────────────────────┘
```

### Distributed Inference Options

#### Option 1: Exo (Pooled VRAM)

[Exo](https://github.com/exo-explore/exo) clusters heterogeneous GPUs across machines:

```bash
# On Proxmox node
pip install exo
exo run llama-3.1-70b

# On Desktop (joins cluster)
pip install exo
exo join <proxmox-ip>
```

#### Option 2: Multi-Endpoint (Failover)

Run Ollama on multiple machines with load balancer:

```
Desktop (7600) ──┬── Load Balancer ── Open WebUI
Proxmox (4070Ti) ┘
```

Benefits:
- Offline fallback when Proxmox is down
- Route small models to desktop, large to Proxmox

---

## Kubernetes (k3s) Planning

### Cluster Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     k3s Cluster                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Proxmox    │  │  Proxmox    │  │    Pi5      │         │
│  │  VM: k3s    │  │  VM: k3s    │  │   k3s       │         │
│  │  control    │  │  worker     │  │  worker     │         │
│  │  plane      │  │  (GPU)      │  │  (Hailo)    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                │                │                 │
│         └────────────────┼────────────────┘                 │
│                          │                                  │
│                    NFS/iSCSI                                │
│                          │                                  │
│                  ┌───────▼───────┐                          │
│                  │    TrueNAS    │                          │
│                  │  (storage)    │                          │
│                  └───────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

### Resource Allocation (Proxmox)

| VM | vCPU | RAM | Purpose |
|----|------|-----|---------|
| k3s control plane | 4 | 8GB | etcd, API server |
| k3s worker (GPU 1) | 8 | 32GB | 4070Ti workloads |
| k3s worker (GPU 2) | 8 | 32GB | 7900XT workloads |
| General VMs | 8 | 40GB | Other services |
| Proxmox overhead | 4 | 16GB | Host reserved |

### What to Skip (For Now)

| Technology | Reason |
|------------|--------|
| Ceph | Need 3+ storage nodes; you have 1 |
| Full Kubernetes | k3s is simpler, same APIs |
| Rancher | Adds complexity unnecessarily |
| Istio/Service Mesh | Overkill for homelab scale |

---

## Media Streaming

### Transcoding Architecture

```
Client → Jellyfin (TrueNAS) → B580 Quick Sync → Media Files (RAID-Z2)
```

### B580 Transcoding Capabilities

| Codec | Decode | Encode |
|-------|--------|--------|
| H.264 | ✓ | ✓ |
| HEVC | ✓ | ✓ |
| AV1 | ✓ | ✓ |

### Performance Estimates

| Scenario | B580 (eGPU) | N305 iGPU |
|----------|-------------|-----------|
| 1080p streams | 8+ | 2-3 |
| 4K streams | 4-5 | 1 |
| AV1 encode | ✓ | ✗ |
| HDR tone mapping | ✓ | Limited |

### Best Practices

1. Configure clients for "Original" or "Maximum" quality (direct play)
2. Use Tdarr to pre-optimize media if transcoding is frequent
3. B580 handles heavy lifting; N305 iGPU as fallback

---

## Implementation Phases

### Phase 1: Foundation

**Goal**: Get core infrastructure running

- [ ] Odroid H4 Ultra → TrueNAS Scale bare metal
  - [ ] Configure RAID-Z2 pool
  - [ ] Set up SMB/NFS shares
  - [ ] Connect B580 via OCuLink
  - [ ] Install Jellyfin
- [ ] i5-12600K → OPNsense
  - [ ] Add Intel X710 NIC
  - [ ] Install OPNsense
  - [ ] Configure Suricata IPS
- [ ] New Desktop → Build and configure
  - [ ] Order i5-13600K + B760M board
  - [ ] Assemble with existing components
  - [ ] Install development tools

### Phase 2: Kubernetes Learning

**Goal**: Learn k3s in isolated environment

- [ ] Create 3 VMs on Proxmox (control plane + 2 workers)
- [ ] Install k3s cluster
- [ ] Mount TrueNAS NFS for persistent volumes
- [ ] Deploy test workloads (nginx, whoami)
- [ ] Set up kubectl on desktop

### Phase 3: GPU Workloads

**Goal**: Enable AI/ML capabilities

- [ ] Configure GPU passthrough on Proxmox
- [ ] Deploy Ollama with GPU support
- [ ] Set up Open WebUI
- [ ] Test distributed inference with Exo
- [ ] Add 6700XT for embeddings

### Phase 4: Production Workloads

**Goal**: Migrate and expand services

- [ ] Ingress controller (Traefik)
- [ ] Cert-manager for TLS
- [ ] Monitoring (Prometheus/Grafana)
- [ ] GitOps (FluxCD or ArgoCD)

### Leave Standalone

- **Pi5 with Home Assistant/Frigate**: Keep separate for reliability
  - Home automation should not depend on cluster health
  - Hailo 8L works well in current configuration

---

## Hardware Shopping List

### New Purchases Required

| Item | Purpose | Est. Cost |
|------|---------|-----------|
| Intel i5-13600K | Desktop CPU | $260 |
| MSI MAG B760M Mortar WiFi DDR5 | Desktop motherboard | $170 |
| Intel X710-DA2 | Firewall 10GbE NIC | $50-60 (used) |
| Euqvos M.2 10GbE (Intel 82599) | TrueNAS 10GbE NIC | $45 |
| SFP+ DAC Cable (1-2m) | Proxmox ↔ TrueNAS link | $15-20 |
| USB Boot Drive (if needed) | TrueNAS boot | $15-25 |
| Case (if needed) | Desktop | $50-80 |
| **Total** | | **~$605-660** |

### Potential Sales

| Item | Est. Value |
|------|------------|
| Radeon RX 7600 | $200-230 |
| Radeon RX 6700 XT | $180-200 |

Selling both GPUs nearly covers the new build cost.

---

## References

### Documentation
- [X870 Taichi Creator Network Setup](docs/x870-taichi-creator-network-setup.md) - RTL8126/AQC113 driver setup for Proxmox
- [OPNsense Setup Guide](docs/opnsense-setup-guide.md) - Firewall and Suricata IPS configuration

### Hardware
- [ASRock X870 Taichi Creator](https://www.asrock.com/mb/AMD/X870%20Taichi%20Creator/index.asp)
- [Odroid H4 Ultra](https://www.hardkernel.com/shop/odroid-h4-ultra/)
- [Odroid M.2 2x2 Bifurcation Card](https://www.hardkernel.com/shop/m-2-2x2-card/)
- [Odroid M.2 4x1 Bifurcation Card](https://www.hardkernel.com/shop/m-2-4x1-card/)
- [Euqvos M.2 10GbE NIC (Intel 82599)](https://www.amazon.com/dp/B0DDKXVJJ4)

### Software
- [TrueNAS Scale Documentation](https://www.truenas.com/docs/scale/)
- [OPNsense Documentation](https://docs.opnsense.org/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [k3s Documentation](https://docs.k3s.io/)
- [Ollama](https://ollama.com/)
- [Open WebUI](https://github.com/open-webui/open-webui)
- [Exo - Distributed Inference](https://github.com/exo-explore/exo)

### Drivers
- [Realtek r8126 DKMS](https://github.com/awesometic/realtek-r8126-dkms) - RTL8126 5GbE driver
- [Aquantia AQtion Driver](https://github.com/Aquantia/AQtion) - AQC113 development driver
- [Atlantic Driver Docs](https://docs.kernel.org/networking/device_drivers/ethernet/aquantia/atlantic.html) - Kernel documentation

---

## License

This documentation is provided as-is for personal reference and community benefit.
