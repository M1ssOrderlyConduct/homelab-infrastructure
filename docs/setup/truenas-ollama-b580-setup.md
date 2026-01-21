# TrueNAS Ollama Setup with Intel B580 GPU

**Server:** TrueNAS SCALE 25.10.1 (Fangtooth) at 10.0.50.95
**GPU:** Intel Arc B580 (Battlemage G21) - Device ID 8086:e20b
**Date:** 2026-01-20

## Architecture

```
TrueNAS (10.0.50.95) - Intel B580
└── Ollama App (TrueNAS Apps)
    └── GPU accelerated inference
    └── Port 11434

Proxmox
└── Open WebUI LXC (10.0.50.116:8000)
    └── Ollama Base URL: http://10.0.50.95:11434
```

## GPU Driver Setup

The Intel B580 uses the `xe` driver (not i915). On TrueNAS 25.10.1 with kernel 6.12.33, the driver is included but may need manual binding if configured for VM passthrough.

### Check GPU Status
```bash
# Verify GPU detected
lspci | grep -i vga
# Should show: Intel Corporation Battlemage G21 [Intel Graphics]

# Check DRI devices
ls -la /dev/dri/
# Should show: card0, renderD128

# Check driver binding
ls -la /sys/bus/pci/devices/0000:06:00.0/driver
# Should link to: xe (not vfio-pci)
```

### If GPU Bound to vfio-pci (Passthrough Mode)

If the GPU was configured for VM passthrough, it needs to be rebound to xe:

```bash
# Check current binding
cat /sys/bus/pci/devices/0000:06:00.0/driver_override
# If shows "vfio-pci", run:

# Clear driver override
echo "" | sudo tee /sys/bus/pci/devices/0000:06:00.0/driver_override

# Unbind from vfio-pci
echo "0000:06:00.0" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind

# Trigger reprobe (binds to xe)
echo "0000:06:00.0" | sudo tee /sys/bus/pci/drivers_probe

# Verify
ls -la /dev/dri/
```

### Making GPU Binding Persistent

The manual binding reverts on reboot. To make permanent:

1. **Remove from VM passthrough** in TrueNAS UI (if configured)
2. **Or** create udev rule:
```bash
# /etc/udev/rules.d/99-intel-gpu.rules
ACTION=="add", KERNEL=="0000:06:00.0", SUBSYSTEM=="pci", ATTR{driver_override}=""
```

3. **Or** configure in TrueNAS Apps GPU settings (preferred)

## Ollama Deployment via TrueNAS Apps

### Installation

1. **TrueNAS Web UI** → Apps → Discover Apps
2. Search **"Ollama"**
3. Click **Install**
4. Configure:
   - **Application Name:** ollama
   - **GPU Configuration:**
     - Enable GPU passthrough
     - Select Intel B580 / Intel Graphics
   - **Network:**
     - Host Port: 11434
   - **Storage:**
     - Models storage: Create or select dataset (e.g., `tank/apps/ollama`)

### Post-Install: Pull Models

Access Ollama shell via TrueNAS Apps UI or:

```bash
# Via TrueNAS shell (find container name first)
# Or use the Ollama API:
curl http://10.0.50.95:11434/api/pull -d '{"name": "llama3.2:3b"}'
```

### Recommended Models for B580

| Model | Size | Use Case |
|-------|------|----------|
| `llama3.2:3b` | ~2GB | Fast responses, good quality |
| `phi3:mini` | ~2GB | Microsoft's efficient model |
| `mistral:7b` | ~4GB | Excellent general purpose |
| `llama3.1:8b` | ~5GB | Best quality for size |
| `deepseek-r1:7b` | ~4GB | Strong reasoning |

## Open WebUI Configuration

### Connect to TrueNAS Ollama

1. Open WebUI (http://10.0.50.116:8000)
2. **Settings → Connections**
3. **Ollama Base URL:** `http://10.0.50.95:11434`
4. Click **Refresh** to verify connection
5. Should see: "Service Connection Verified"

### Verify GPU Acceleration

In Open WebUI, start a chat and check response speed. With B580 acceleration:
- 7B models: ~30-50 tokens/sec
- 3B models: ~60-100 tokens/sec

Without GPU (CPU only):
- 7B models: ~5-10 tokens/sec

## Life OS Integration

The Ollama instance can serve as the "Coach" component in the Life Operating System:

```
Home Assistant (Enforcer)     Open WebUI (Coach Interface)
        │                              │
        │                              │
        └──────── Ollama API ──────────┘
                 (10.0.50.95:11434)
```

### Potential Automations

1. **Task Verification:** HA calls Ollama API to verify task completion
2. **Daily Review:** Scheduled summary generation
3. **Escalation Messages:** Generate "Margaret" or "General Mattis" style messages
4. **Voice Assistant:** Wyoming + Whisper + Ollama for local voice AI

### API Example (from HA or scripts)

```bash
# Simple completion
curl http://10.0.50.95:11434/api/generate \
  -d '{"model": "llama3.2:3b", "prompt": "Summarize my completed tasks today", "stream": false}'

# Chat format
curl http://10.0.50.95:11434/api/chat \
  -d '{
    "model": "llama3.2:3b",
    "messages": [
      {"role": "system", "content": "You are a productivity coach..."},
      {"role": "user", "content": "What should I focus on next?"}
    ]
  }'
```

## Troubleshooting

### No GPU Acceleration

1. Check `/dev/dri/` exists
2. Verify Ollama container has GPU access (check app config)
3. Check driver: `ls -la /sys/bus/pci/devices/0000:06:00.0/driver`

### Ollama Not Responding

1. Check app status in TrueNAS Apps
2. Verify port 11434 is accessible: `curl http://10.0.50.95:11434/api/tags`
3. Check firewall rules between VLANs (Services 10.0.50.x ↔ House 10.0.30.x)

### Model Download Fails

1. Check internet connectivity from TrueNAS
2. Verify storage dataset has space
3. Try smaller model first: `ollama pull phi3:mini`

## Network Reference

```
Services VLAN (10.0.50.0/24)
├── TrueNAS: 10.0.50.95
│   └── Ollama: port 11434
├── Open WebUI LXC: 10.0.50.116
│   └── Web UI: port 8000
└── Other services...

House VLAN (10.0.30.0/24)
├── HA Pi: 10.0.30.30
└── UniFi Gateway: 10.0.30.1
```

## Maintenance

### Update Ollama
- TrueNAS Apps → Ollama → Update (when available)

### Update Models
```bash
ollama pull llama3.2:3b  # Re-pulls latest version
```

### Backup Models
Models stored in configured dataset - included in TrueNAS snapshots/replication

## References

- [IPEX-LLM Intel GPU Guide](https://github.com/intel-analytics/ipex-llm)
- [Ollama Documentation](https://ollama.ai/docs)
- [Open WebUI Docs](https://docs.openwebui.com)
- [Level1Techs Intel Arc/B580 Discussion](https://forum.level1techs.com)
