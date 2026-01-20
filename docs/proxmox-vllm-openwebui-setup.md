# Proxmox LLM Inference Setup

## Overview

Set up LLM inference on Proxmox host with hybrid CPU/GPU support for 70B models, using llama.cpp with OpenWebUI as the frontend. Claude Code automates the entire setup.

## Hardware

- **CPU:** Ryzen 9 9950X (16c/32t)
- **RAM:** 128GB
- **GPU (primary):** NVIDIA 4070 Ti Super (16GB VRAM) - for vLLM
- **GPU (spare):** AMD 7900 XT (20GB VRAM) - idle

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Proxmox Host (10.0.50.10)            │
│                                                         │
│  ┌──────────────────┐      ┌──────────────────────┐    │
│  │  OpenWebUI (116) │      │  llama.cpp LXC (118) │    │
│  │  Web Frontend    │─────▶│  NVIDIA 4070Ti Super │    │
│  │  Port 8080       │ API  │  16GB VRAM           │    │
│  │                  │      │  + CPU hybrid (96GB) │    │
│  └──────────────────┘      └──────────────────────┘    │
│                                                         │
│  ┌──────────────────┐      ┌──────────────────────┐    │
│  │  Claude Code     │      │  vLLM LXC (117)      │    │
│  │  claude user     │      │  (standby/alternate) │    │
│  └──────────────────┘      └──────────────────────┘    │
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
| vLLM LXC (117) | ⏸️ | 16 cores, 96GB RAM, GPU passthrough (standby) |
| llama.cpp LXC (118) | ✅ | Hybrid CPU/GPU inference with 70B model |
| OpenWebUI (116) | ✅ | Connected to llama.cpp |

### Current Architecture

**llama.cpp selected as primary inference server** - enables true hybrid CPU/GPU inference for 70B models.

### Access Details

- **Proxmox Host:** `root@10.0.50.10`
- **Claude user:** `claude@10.0.50.10`
- **llama.cpp LXC:** `10.0.50.118:8080` (OpenAI-compatible API)
- **vLLM LXC:** `10.0.50.117:8000` (standby, GPU conflict with llama.cpp)
- **OpenWebUI:** `http://10.0.50.116:8080`

### Current Model

**Meta Llama 3.1 70B Instruct** (Q4_K_M quantization, GGUF format)
- Model size: 39.6 GB
- Parameters: 70.55 billion
- Context length: 16384 tokens
- **Hybrid inference**: 25 layers on GPU (~12.7GB), 55 layers on CPU (~27GB)
- **KV cache**: 1.5GB GPU + 3.6GB CPU
- **Performance**: ~2.2 tokens/sec generation, ~44 tokens/sec prompt processing
- Inference speed scales with CPU threads (16 configured)

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

### llama.cpp Configuration

Location: `/opt/llama-cpp/docker-compose.yml` in LXC 118

```yaml
services:
  llama-server:
    image: ghcr.io/ggml-org/llama.cpp:server-cuda
    container_name: llama-server
    security_opt:
      - apparmor=unconfined
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    ports:
      - "8080:8080"
    volumes:
      - ./models:/models
    command:
      - --host
      - "0.0.0.0"
      - --port
      - "8080"
      - -m
      - /models/model.gguf
      - -ngl
      - "25"              # GPU layers (adjust based on VRAM)
      - -c
      - "16384"           # Context length
      - --threads
      - "16"              # CPU threads
    restart: unless-stopped
```

**Key parameters:**
- `-ngl 25`: Number of layers on GPU. Max ~25-28 for 16GB VRAM with this model.
- `-c 16384`: Context window size. Can increase if reducing GPU layers.
- `--threads 16`: CPU threads for hybrid computation.

### Switching Between vLLM and llama.cpp

The GPU can only be used by one container at a time. To switch:

**Switch to vLLM (smaller models, faster):**
```bash
# On LXC 118
cd /opt/llama-cpp && docker compose down
# On LXC 117
cd /opt/vllm && docker compose up -d
# Update OpenWebUI
echo 'OPENAI_API_BASE_URLS=http://10.0.50.117:8000/v1
OPENAI_API_KEYS=sk-no-key-needed' > /root/.env
systemctl restart open-webui
```

**Switch to llama.cpp (70B model, hybrid):**
```bash
# On LXC 117
cd /opt/vllm && docker compose down
# On LXC 118
cd /opt/llama-cpp && docker compose up -d
# Update OpenWebUI
echo 'OPENAI_API_BASE_URLS=http://10.0.50.118:8080/v1
OPENAI_API_KEYS=sk-no-key-needed' > /root/.env
systemctl restart open-webui
```

### Alternative Models for llama.cpp

Download GGUF models to `/opt/llama-cpp/models/` in LXC 118:

```bash
# Qwen2.5 72B (similar quality to Llama 70B)
wget -O /opt/llama-cpp/models/model.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-72B-Instruct-GGUF/resolve/main/qwen2.5-72b-instruct-q4_k_m.gguf"

# DeepSeek Coder V2 Lite (smaller, coding focused)
wget -O /opt/llama-cpp/models/model.gguf \
  "https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf"
```

### Alternative Models for vLLM (LXC 117)

For GPU-only inference with smaller models:
```yaml
# Edit /opt/vllm/docker-compose.yml in LXC 117
command:
  - --model
  - Qwen/Qwen2.5-14B-Instruct-AWQ
  - --quantization
  - awq
  - --max-model-len
  - "8192"
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
5. **GPU sharing** - vLLM and llama.cpp cannot run simultaneously (single GPU)
6. **NVIDIA driver version** - LXC containers need matching `libnvidia-compute-580` package

### Hybrid Inference Explained

llama.cpp supports true hybrid CPU/GPU inference:

- **GPU layers**: Handle part of the transformer forward pass on VRAM (fast)
- **CPU layers**: Handle remaining layers using system RAM (slower but allows large models)
- **KV cache**: Split between GPU and CPU memory proportionally

This differs from vLLM's `--cpu-offload-gb` which only offloads static weights while keeping KV cache on GPU, limiting effective model size.

**Performance tuning:**
- Increase `-ngl` to use more GPU (faster, but limited by VRAM)
- Decrease `-ngl` to fit larger models or longer context
- Increase `--threads` if CPU-bound (up to physical core count)

## Future Expansion

- AMD 7900 XT utilization with ROCm (if maturity improves)
- ComfyUI integration for image generation workflows
- Claude Code orchestration for programmatic LLM access
- Model routing based on task complexity
