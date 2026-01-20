# Proxmox vLLM + ComfyUI Integration Design

## Overview

Set up vLLM for LLM inference on Proxmox host, integrated with ComfyUI for workflow orchestration. Claude Code automates the entire setup.

## Hardware

- **CPU:** Ryzen 9 9950X (16c/32t)
- **RAM:** 128GB
- **GPU (primary):** NVIDIA 4070 Ti Super (16GB VRAM) - for vLLM
- **GPU (spare):** AMD 7900 XT (20GB VRAM) - idle

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Proxmox Host                         │
│                                                         │
│  ┌──────────────────┐      ┌──────────────────────┐    │
│  │  ComfyUI LXC     │      │  vLLM LXC            │    │
│  │  (lightweight)   │─────▶│  NVIDIA 4070Ti Super │    │
│  │  No GPU          │ API  │  16GB VRAM           │    │
│  │  Orchestration   │      │  CPU offload enabled │    │
│  └──────────────────┘      └──────────────────────┘    │
│                                                         │
│  ┌──────────────────┐                                   │
│  │  Claude Code     │  (sets up & manages everything)  │
│  │  New user        │                                   │
│  └──────────────────┘                                   │
│                                                         │
│  AMD 7900 XT (20GB) - idle/spare                       │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. New User + Claude Code
- Create dedicated user on Proxmox host
- Install Claude Code CLI
- Clone vLLM repository to host for reference

### 2. vLLM Deployment
- **Method:** LXC + Docker (per vLLM official docs)
- **GPU:** NVIDIA 4070 Ti Super via passthrough (existing Proxmox helper scripts config)
- **Image:** `vllm/vllm-openai` (official Docker image)
- **Models:** 70B quantized (AWQ/GPTQ) + CPU offload (`--cpu-offload-gb`)
- **API:** OpenAI-compatible on port 8000

### 3. OpenWebUI Assessment
- Existing OpenWebUI install needs evaluation
- Options:
  - Repurpose container for vLLM (if has GPU passthrough)
  - Keep alongside vLLM (connect as frontend)
  - Scrap and reclaim resources

### 4. ComfyUI LXC Modifications
- Remove GPU passthrough configuration
- Reduce RAM/CPU allocation
- Install LLM API nodes for ComfyUI
- Configure vLLM endpoint connection

## Implementation Order

1. Connect to Proxmox host
2. Create new user, install Claude Code
3. Clone vLLM repository to host (`/opt/vllm` or user home)
4. Assess OpenWebUI - decide fate
5. Set up vLLM LXC (reuse or create new)
   - GPU passthrough (leverage existing config)
   - Docker + NVIDIA Container Toolkit
   - Pull vLLM Docker image
   - Configure for 70B models + CPU offload
6. Modify ComfyUI LXC
   - Remove GPU resources
   - Install LLM API nodes
   - Point to vLLM endpoint
7. Integration test - end-to-end workflow

## Agent Verification Checkpoints

| Checkpoint | Verification |
|------------|--------------|
| 1. User creation | Verify sudo access, SSH works |
| 2. OpenWebUI assessment | Confirm decision (repurpose/keep/scrap) |
| 3. GPU passthrough | `nvidia-smi` works in container |
| 4. vLLM container | API responds on port 8000 |
| 5. ComfyUI modification | Can reach vLLM endpoint |
| 6. Final integration | End-to-end workflow test |

## Network

- vLLM and ComfyUI on same Proxmox bridge
- Internal communication via bridge network
- vLLM API: `http://<vllm-lxc-ip>:8000/v1`

## Deployment Status (2026-01-20)

### Completed

| Component | Status | Details |
|-----------|--------|---------|
| User `claude` | ✅ | Created with sudo, SSH configured |
| Claude Code | ✅ | v2.1.12 installed at `/usr/bin/claude` |
| vLLM repo | ✅ | Cloned to `/opt/vllm` |
| NVIDIA drivers | ✅ | v580.126.09 on host, CUDA 13.0 |
| vLLM LXC (117) | ✅ | 16 cores, 96GB RAM, GPU passthrough |
| vLLM container | ✅ | Running `Mistral-7B-Instruct-v0.2-AWQ` on port 8000 |
| OpenWebUI (116) | ✅ | Reduced to 4 cores, 8GB RAM, connected to vLLM |

### Decision

**OpenWebUI selected as orchestration layer** (instead of ComfyUI) - already configured and connected to vLLM.

### Access Details

- **Proxmox Host:** `root@10.0.50.10`
- **Claude user:** `claude@10.0.50.10`
- **vLLM LXC:** `10.0.50.117:8000` (OpenAI-compatible API)
- **OpenWebUI:** `http://10.0.50.116:8080`
- **vLLM repo:** `/opt/vllm`

### Current Model

**TheBloke/Mistral-7B-Instruct-v0.2-AWQ** (7B parameters, 4-bit AWQ quantization)
- Context length: 16384 tokens
- VRAM usage: ~4GB (leaves ~11GB for KV cache)
- Excellent performance for instruction-following tasks

### Model Sizing Lessons Learned

| Model | Params | AWQ Size | 16GB VRAM | Notes |
|-------|--------|----------|-----------|-------|
| Phi-2 | 2.7B | ~2GB | ✅ Works | Good for testing |
| Mistral-7B | 7B | ~4GB | ✅ Works | Current production |
| Llama-3-8B | 8B | ~5GB | ✅ Should work | Alternative option |
| Qwen2.5-14B | 14B | ~8GB | ⚠️ Tight | May need reduced context |
| Mixtral-8x7B | 46.7B | ~23GB | ❌ OOM | MoE loads ALL experts |
| Mixtral-8x22B | 141B | ~70GB | ❌ OOM | Far too large |

**Key insight:** Mixture-of-Experts (MoE) models like Mixtral must load ALL expert weights into memory, not just the 2 active experts per token. Mixtral-8x7B has 46.7B total params despite using only ~13B per forward pass.

### Alternative Models to Try

For maximum capability on 16GB VRAM:
```yaml
# Edit /opt/vllm/docker-compose.yml in LXC 117
command:
  - --model
  - Qwen/Qwen2.5-14B-Instruct-AWQ  # or TheBloke/Qwen2.5-14B-Instruct-AWQ
  - --quantization
  - awq
  - --max-model-len
  - "8192"  # Reduced context to fit
  - --gpu-memory-utilization
  - "0.95"
  - --host
  - "0.0.0.0"
```

### Known Issues

1. **VM 151 stopped** - NVIDIA GPU was reassigned from VM to LXC passthrough
2. **AppArmor in LXC** - Docker containers need `--security-opt apparmor=unconfined`
3. **nouveau blacklisted** - `/etc/modprobe.d/blacklist-nouveau.conf` added
4. **MoE model sizing** - Mixtral/similar MoE models require full expert weight loading

## Future Expansion

- Claude Code orchestration (call vLLM + ComfyUI programmatically)
- Additional models as needed
- Potential AMD GPU utilization if ROCm matures
- ComfyUI integration pending user clarification
