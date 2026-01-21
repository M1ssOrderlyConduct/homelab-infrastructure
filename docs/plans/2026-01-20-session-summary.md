# Life Operating System - Session Summary
**Date:** 2026-01-20 (Evening Session)

## Completed

### Phase 1: Foundation
1. **Input Helpers Created:**
   - `input_select.system_state`: off, morning_routine, work, break, wind_down, bring_it_home, recovery
   - `input_select.full_house`: kids_home, kids_away, transition
   - `input_select.operating_mode`: asf, mvdb, normal, surge, recovery
   - `input_boolean.work_alarm_active`
   - `input_boolean.break_network_blocked`
   - `timer.working` (90 min)
   - `timer.on_break_short` (15 min)
   - `timer.on_break_long` (60 min)
   - `counter.work_blocks_today`

2. **Automations Deployed (13 total):**
   - Work timer → forced break
   - Break timer → resume work (or wind_down if after 5 PM)
   - Start work block (starts timer + TTS)
   - Bring it home mode
   - Morning routine (resets daily counter)
   - Wind down mode
   - Recovery mode
   - System off
   - Kids home adjustment
   - Voice commands: "ready to work", "take a break", "wind down", "bring it home"

3. **TTS Working:**
   - Google Translate TTS to Android TVs
   - Tested on: Onn 4K Plus (family_room_tv), sti6110, living_room_tv
   - Distributed alarm system functional

### Design Document
- Full spec at: `~/homelab-infrastructure/docs/plans/2026-01-20-life-operating-system-design.md`
- Includes: Two Brains architecture, ASF/MVDB modes, escalation system (Margaret/General Mattis), Notion integration specs

### Files Created
- `/home/deain/homelab-infrastructure/ha-config/life-os-helpers.yaml`
- `/home/deain/homelab-infrastructure/ha-config/life-os-automations.yaml`
- `/var/lib/homeassistant/homeassistant/automations.yaml` (on Pi)
- `/var/lib/homeassistant/homeassistant/scripts/break_block_enable.sh` (on Pi)
- `/var/lib/homeassistant/homeassistant/scripts/break_block_disable.sh` (on Pi)
- `/var/lib/homeassistant/homeassistant/configuration.yaml` updated with shell_command (on Pi)

## Remaining Phase 1
- [ ] Busy light automation (need smart bulb for office door)
- [ ] Daily schedule automations (timed triggers)
- [ ] Motion sensor configuration (4-5 in box)

### Phase 2: Network Enforcement (Started)
1. **AdGuard Break Blocking (Interim Solution):**
   - Scripts deployed: `/config/scripts/break_block_enable.sh`, `/config/scripts/break_block_disable.sh`
   - AdGuard API at `http://127.0.0.1:45158/control/filtering/set_rules`
   - Blocks: github.com, stackoverflow.com, reddit.com, youtube.com, twitter.com, x.com, news.ycombinator.com, slashdot.org, techmeme.com, lobste.rs, dev.to
   - Shell commands registered in HA: `shell_command.break_block_enable`, `shell_command.break_block_disable`

2. **HA Automations Added (15 total now):**
   - `life_os_enable_break_network_block`: Triggers when `input_boolean.break_network_blocked` → on
   - `life_os_disable_break_network_block`: Triggers when `input_boolean.break_network_blocked` → off

3. **Integration Flow:**
   - Work timer expires → system_state changes to 'break' → break_network_blocked turns on → AdGuard blocks sites
   - Break timer expires → system_state changes to 'work' → break_network_blocked turns off → Sites unblocked

## Phase 2: Remaining
- [ ] iptables on UniFi (robust solution with resolved IPs)
- [ ] Workstation WoL and sleep control
- [ ] Emergency override button (physical Zigbee)
- [ ] Override logging system

### TrueNAS Ollama + B580 Setup (Started)
1. **GPU Driver Configured:**
   - Intel B580 (Battlemage G21) at PCI 06:00.0
   - Device ID: 8086:e20b
   - xe driver binding (was on vfio-pci for passthrough)
   - `/dev/dri/card0` and `/dev/dri/renderD128` available

2. **Architecture:**
   ```
   TrueNAS (10.0.50.95) - Intel B580
   └── Ollama App → port 11434

   Proxmox
   └── Open WebUI LXC (10.0.50.116:8000)
       └── Connects to: http://10.0.50.95:11434
   ```

3. **Documentation:** `~/homelab-infrastructure/docs/setup/truenas-ollama-b580-setup.md`

4. **Remaining:**
   - [ ] Deploy Ollama via TrueNAS Apps UI
   - [ ] Configure GPU passthrough in app settings
   - [ ] Pull initial model (llama3.2:3b recommended)
   - [ ] Connect Open WebUI to TrueNAS Ollama
   - [ ] Make GPU binding persistent (remove from VM passthrough config)

## Notes
- Govee H5082 WiFi plug (boys room projector) needs cloud API integration
- Master bedroom breaker was flipped - needs integration
- kids_away state needs fine-tuning for schedule logic
- SSH access (HA Pi): `timpi@10.0.30.30`
- SSH access (TrueNAS): `tim@10.0.50.95`
- HA config: `/var/lib/homeassistant/homeassistant/`
- TrueNAS: 25.10.1 (Fangtooth), kernel 6.12.33
- Open WebUI: `http://10.0.50.116:8000`
- HA Token stored in session

## Key Entity Reference
```
# State Management
input_select.system_state
input_select.full_house
input_select.operating_mode
input_boolean.break_network_blocked
input_boolean.work_alarm_active

# Timers
timer.working
timer.on_break_short
timer.on_break_long
counter.work_blocks_today

# Media/TTS
media_player.family_room_tv (Onn 4K Plus)
tts.google_translate_en_com

# Shell Commands (Phase 2)
shell_command.break_block_enable
shell_command.break_block_disable

# Key Automations
automation.life_os_enable_break_network_block
automation.life_os_disable_break_network_block
```
