# Family Accountability System

A verification-based task tracking system using Home Assistant, eliminating self-reporting through data-driven verification.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Home Assistant                            │
├─────────────────────────────────────────────────────────────┤
│  Verification Sources                                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │ ADB Bridge   │ │ RFID Readers │ │ Phone GPS    │        │
│  │ (Call Logs)  │ │ (Location)   │ │ (HA Companion)│        │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘        │
│         └────────────────┼────────────────┘                 │
│                          ▼                                   │
│              ┌───────────────────────┐                      │
│              │   Task State Engine   │                      │
│              │   (Template Sensors)  │                      │
│              └───────────┬───────────┘                      │
│                          ▼                                   │
│              ┌───────────────────────┐                      │
│              │  Voice Assistant LLM  │                      │
│              │  (Accountability)     │                      │
│              └───────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Voice Assistant (`voice-assistant/`)
- Custom system prompt for family guidance
- Local LLM via Ollama (qwen2.5:7b-instruct)
- Wyoming protocol voice pipeline (Whisper → LLM → Piper)

### 2. RFID Task Verification (`rfid/`)
- ESP32 + RC522 readers at task locations
- Scan-to-complete workflow
- Multi-step tasks (laundry: start → dry → fold)

### 3. Phone Call Monitoring (`adb-monitor/`)
- ADB wireless connection to phone
- Extracts call logs to verify required calls
- Pushes to HA sensors via REST API

### 4. GPS Location Tracking (`gps-tracking/`)
- HA Companion app location
- Zone-based appointment verification
- Dwell time tracking (session duration)

## Quick Start

1. **Voice Assistant**: Configure Ollama and HA conversation agent
2. **RFID**: Flash ESP32s with ESPHome configs, mount at task locations
3. **ADB**: Enable wireless debugging, configure call_monitor.py
4. **GPS**: Define zones in HA, install Companion app

## Philosophy

- **No self-reporting**: Data proves completion
- **Escalating accountability**: Gentle → Direct → Blunt
- **Structure as medicine**: Routine reduces anxiety
- **Tough love**: "I believe you can handle this"

See `voice-assistant/family_guide_prompt.txt` for the full assistant personality.
