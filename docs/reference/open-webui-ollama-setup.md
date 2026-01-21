# Open WebUI + Ollama Setup Guide

**Source:** Open WebUI Documentation + Medium Article (Henry Navarro)
**Saved:** 2026-01-20

## Architecture Options

### Option 1: Direct Ollama Connection (Simplest)
```
[Open WebUI] --> [Ollama Server]
     |
     v
  Port 8080 (HTTP)
```

- No HTTPS needed for local-only access
- Ollama default: `http://localhost:11434`

### Option 2: Traefik Reverse Proxy (Production)
```
[Internet] --> [Traefik] --> [Open WebUI] --> [Ollama]
                  |
                  v
            HTTPS/Let's Encrypt
```

**Pros:**
- Automatic HTTPS via Let's Encrypt
- Multi-service routing
- Docker-native labels for config

**Cons:**
- Extra container overhead
- More complex debugging
- Requires domain name + open ports

### Option 3: Caddy Reverse Proxy (Simpler Alternative)
```
[Internet] --> [Caddy] --> [Open WebUI] --> [Ollama]
```

**Pros:**
- Simpler config than Traefik
- Automatic HTTPS
- Single binary, no dependencies

**Cons:**
- Less Docker-native than Traefik
- Fewer advanced routing features

### Option 4: TrueNAS + LXC (Recommended for Homelab)
```
[TrueNAS Server]
    |
    +-- [Open WebUI LXC] --> [Ollama Container/Service]
    |
    +-- [Home Assistant LXC]
    |
    +-- GPU Passthrough (Intel B580)
```

**Pros:**
- Consolidated infrastructure
- ZFS storage benefits
- GPU can be shared/dedicated
- No external domain needed for local use

## Intel GPU Setup (IPEX-LLM)

For Intel Arc/B580 GPUs, use IPEX-LLM for acceleration:

1. Install IPEX-LLM Ollama backend
2. Set environment: `OLLAMA_HOST=0.0.0.0`
3. Run: `ollama serve`
4. Configure Open WebUI: Settings > Connections > Ollama Base URL

### Intel B580 Considerations
- Check Level1Techs forum for latest driver status
- IPEX-LLM provides PyTorch acceleration
- Works with: Arc A-Series, Flex, Max, and newer GPUs

## Docker Compose (Traefik + Open WebUI)

```yaml
# proxy-compose.yml
version: "3.8"
services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - web

# open-webui-compose.yml
version: "3.8"
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`${OPEN_WEBUI_HOST}`)"
      - "traefik.http.routers.openwebui.entrypoints=websecure"
      - "traefik.http.routers.openwebui.tls.certresolver=letsencrypt"
    volumes:
      - open-webui-data:/app/backend/data
    networks:
      - web

  ollama:
    image: ollama/ollama
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - web
    # For GPU passthrough, add:
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - capabilities: [gpu]

networks:
  web:
    external: true

volumes:
  open-webui-data:
  ollama-data:
```

## Environment Variables

```bash
# .env
ACME_EMAIL=your@email.com
OPEN_WEBUI_HOST=chat.yourdomain.com
WEBUI_SECRET_KEY=your-persistent-secret-key

# For Ollama
OLLAMA_HOST=0.0.0.0
OLLAMA_ORIGINS=*
```

## Configuring Open WebUI for Ollama

1. Access: Settings > Connections
2. Ollama Base URL: `http://localhost:11434` (or container name)
3. Click Refresh to verify connection
4. Should see: "Service Connection Verified"

## Backend API Integration

For programmatic control (e.g., Life OS Coach integration):

### Create Chat
```bash
curl -X POST https://host/api/v1/chats/new \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"chat": {"title": "New Chat", "models": ["llama3"], ...}}'
```

### Trigger Completion
```bash
curl -X POST https://host/api/chat/completions \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"chat_id": "...", "model": "llama3", "stream": true, ...}'
```

See full API reference in Open WebUI documentation.

## Voice Assistant Integration

For Home Assistant voice assistant with Open WebUI:

1. Run Ollama with speech-capable model
2. Configure Wyoming protocol integration in HA
3. Use Open WebUI API for text processing
4. Connect TTS output to media players

## Security Notes

- Always set `WEBUI_SECRET_KEY` for OAuth persistence
- Use HTTPS for any external access
- Consider VPN for remote access instead of exposing ports
- Rate limit API endpoints if publicly accessible
