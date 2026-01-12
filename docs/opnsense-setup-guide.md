# OPNsense Step-by-Step Setup Guide

Complete configuration guide for OPNsense firewall with Suricata IPS, Unbound DNS, Q-Feeds threat intelligence, and monitoring integration.

---

## Table of Contents

1. [Hardware Preparation](#phase-1-hardware-preparation)
2. [OPNsense Installation](#phase-2-opnsense-installation)
3. [Web GUI Initial Configuration](#phase-3-web-gui-initial-configuration)
4. [VLAN Configuration](#phase-4-vlan-configuration)
5. [Firewall Rules](#phase-5-firewall-rules)
6. [Unbound DNS](#phase-6-unbound-dns)
7. [Suricata IPS](#phase-7-suricata-ips)
8. [Q-Feeds Integration](#phase-8-q-feeds-integration)
9. [Threat Intel Aliases](#phase-9-threat-intel-aliases)
10. [Monitoring (Telegraf)](#phase-10-monitoring-telegraf)
11. [Final Checklist](#phase-11-final-checklist)

---

## Phase 1: Hardware Preparation

### 1.1 Dell OptiPlex 7060 SFF

| Component | Spec |
|-----------|------|
| CPU | i7-8700 (6C/12T) |
| RAM | 32GB DDR4 |
| Storage | Existing SSD/NVMe |
| NIC (onboard) | Intel I219-LM (1GbE) |
| NIC (add) | Intel i350-T2 Low-Profile |

### 1.2 Install NIC

1. Power off, unplug
2. Remove case cover
3. Insert i350-T2 into low-profile PCIe slot
4. Attach low-profile bracket
5. Reassemble

### 1.3 Cable Connections

| Port | Connection |
|------|------------|
| i350 Port 1 | WAN → Verizon ONT |
| i350 Port 2 | LAN → Switch (trunk) |
| I219 (onboard) | Management (optional backup) |

---

## Phase 2: OPNsense Installation

### 2.1 Download

1. Go to https://opnsense.org/download/
2. Select:
   - Architecture: `amd64`
   - Image type: `dvd` (for USB install)
   - Mirror: nearest location
3. Download and verify checksum

### 2.2 Create Boot USB

```bash
# Linux/Mac
dd if=OPNsense-*.img of=/dev/sdX bs=4M status=progress

# Windows: Use Rufus or balenaEtcher
```

### 2.3 Install

1. Boot Dell 7060 from USB (F12 for boot menu)
2. Select `Install (UFS)`
3. Choose target disk
4. Set root password
5. Reboot, remove USB

### 2.4 Initial Console Setup

After reboot, at console:

```
1) Assign interfaces

WAN: igb0 (i350 port 1)
LAN: igb1 (i350 port 2)
OPT1: em0 (I219 onboard) - optional

2) Set interface IP address

LAN: 10.0.0.1/24
```

---

## Phase 3: Web GUI Initial Configuration

### 3.1 Access GUI

1. Connect laptop to LAN port
2. Set laptop IP: 10.0.0.2/24
3. Browse to: https://10.0.0.1
4. Login: `root` / [your password]

### 3.2 Setup Wizard

Complete the wizard:

| Setting | Value |
|---------|-------|
| Hostname | opnsense |
| Domain | home.lan |
| Primary DNS | 9.9.9.9 |
| Secondary DNS | 1.1.1.1 |
| Timezone | [Your timezone] |
| WAN | DHCP (Verizon) |
| LAN | 10.0.0.1/24 |

---

## Phase 4: VLAN Configuration

### 4.1 Create VLANs

**Interfaces → Other Types → VLAN → Add** (repeat for each):

| VLAN Tag | Parent | Description |
|----------|--------|-------------|
| 2 | igb1 (LAN) | Cameras |
| 3 | igb1 (LAN) | House |
| 4 | igb1 (LAN) | Main |
| 5 | igb1 (LAN) | Server |
| 6 | igb1 (LAN) | Lab |

*(VLAN 1 is native/untagged on LAN interface)*

### 4.2 Assign VLAN Interfaces

**Interfaces → Assignments → Add** (for each VLAN):

| Interface | Assignment |
|-----------|------------|
| vlan02 | CAMERAS |
| vlan03 | HOUSE |
| vlan04 | MAIN |
| vlan05 | SERVER |
| vlan06 | LAB |

### 4.3 Configure VLAN Interfaces

**Interfaces → [VLAN Name]** (repeat for each):

| VLAN | IPv4 Address | Subnet |
|------|--------------|--------|
| LAN (VLAN 1) | 10.0.0.1 | /24 |
| CAMERAS | 10.0.20.1 | /24 |
| HOUSE | 10.0.30.1 | /24 |
| MAIN | 10.0.40.1 | /24 |
| SERVER | 10.0.50.1 | /24 |
| LAB | 10.0.60.1 | /24 |

Settings for each:
- Enable: ✓
- IPv4 Configuration Type: Static IPv4
- IPv4 Address: [as above]

### 4.4 DHCP Servers

**Services → DHCPv4 → [Interface]** (repeat for each VLAN):

| VLAN | Range Start | Range End |
|------|-------------|-----------|
| LAN | 10.0.0.100 | 10.0.0.254 |
| CAMERAS | 10.0.20.100 | 10.0.20.254 |
| HOUSE | 10.0.30.100 | 10.0.30.254 |
| MAIN | 10.0.40.100 | 10.0.40.254 |
| SERVER | 10.0.50.100 | 10.0.50.254 |
| LAB | 10.0.60.100 | 10.0.60.254 |

---

## Phase 5: Firewall Rules

### 5.1 Default Deny Strategy

By default, OPNsense blocks all inter-VLAN traffic. Create rules to allow what's needed.

### 5.2 Create RFC1918 Alias

**Firewall → Aliases → Add:**

| Setting | Value |
|---------|-------|
| Name | RFC1918 |
| Type | Network(s) |
| Content | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 |

### 5.3 Basic Rules Per VLAN

**Firewall → Rules → [VLAN]**

**Allow outbound internet (each VLAN):**

| Setting | Value |
|---------|-------|
| Action | Pass |
| Interface | [VLAN] |
| Source | [VLAN] net |
| Destination | ! RFC1918 |
| Description | Allow internet access |

### 5.4 Inter-VLAN Rules (Examples)

**Allow Server VLAN to access all:**

| Setting | Value |
|---------|-------|
| Action | Pass |
| Interface | SERVER |
| Source | SERVER net |
| Destination | Any |

**Allow Main to access Server VLAN:**

| Setting | Value |
|---------|-------|
| Action | Pass |
| Interface | MAIN |
| Source | MAIN net |
| Destination | SERVER net |

**Block Cameras from internet (IoT isolation):**

| Setting | Value |
|---------|-------|
| Action | Block |
| Interface | CAMERAS |
| Source | CAMERAS net |
| Destination | ! CAMERAS net |

---

## Phase 6: Unbound DNS

### 6.1 Basic Configuration

**Services → Unbound DNS → General:**

| Setting | Value |
|---------|-------|
| Enable | ✓ |
| Listen Port | 53 |
| Network Interfaces | All VLANs |
| DNSSEC | ✓ |
| DHCP Registration | ✓ |

### 6.2 DNS-over-TLS

**Services → Unbound DNS → DNS over TLS:**

| Setting | Value |
|---------|-------|
| Enable | ✓ |

**Add servers:**

| Server | IP | Port |
|--------|-----|------|
| dns.quad9.net | 9.9.9.9 | 853 |
| dns.quad9.net | 149.112.112.112 | 853 |
| cloudflare-dns.com | 1.1.1.1 | 853 |

### 6.3 DNS Blocklists

**System → Firmware → Plugins** → Install `os-unbound-plus`

**Services → Unbound DNS → Blocklist:**

| Setting | Value |
|---------|-------|
| Enable | ✓ |

Add lists:
- Steven Black: `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts`
- OISD: `https://big.oisd.nl/domainswild`

### 6.4 Strict DNS Enforcement

#### NAT Redirect (per VLAN)

**Firewall → NAT → Port Forward:**

| Setting | Value |
|---------|-------|
| Interface | [VLAN] |
| Protocol | TCP/UDP |
| Destination | ! This Firewall |
| Destination Port | 53 |
| Redirect Target IP | 127.0.0.1 |
| Redirect Target Port | 53 |

#### Firewall Rules (per VLAN)

**Firewall → Rules → [VLAN]:**

**Rule 1 - Allow DNS to OPNsense:**

| Setting | Value |
|---------|-------|
| Action | Pass |
| Destination | This Firewall |
| Destination Port | 53 |

**Rule 2 - Block external DNS:**

| Setting | Value |
|---------|-------|
| Action | Block |
| Destination | Any |
| Destination Port | 53 |

**Rule 3 - Block DoT:**

| Setting | Value |
|---------|-------|
| Action | Block |
| Destination | Any |
| Destination Port | 853 |

---

## Phase 7: Suricata IPS

### 7.1 Install

**System → Firmware → Plugins** → Install `os-suricata`

### 7.2 Download Rules

**Services → Intrusion Detection → Administration → Download**

Enable:
- [x] ET Open Rules
- [x] Abuse.ch SSL Blacklist
- [x] Abuse.ch URLhaus
- [x] Feodo Tracker

Click **Download & Update Rules**

### 7.3 Configure

**Services → Intrusion Detection → Administration:**

| Setting | Value |
|---------|-------|
| Enable | ✓ |
| IPS mode | ✓ |
| Pattern matcher | Hyperscan |
| Interfaces | WAN |

**Services → Intrusion Detection → Administration → Advanced:**

| Setting | Value |
|---------|-------|
| Promiscuous mode | ✓ |
| Log rotate | 7 days |

### 7.4 Enable Rules

**Services → Intrusion Detection → Rules:**

1. Select rule categories
2. Enable desired rules
3. Click **Apply**

### 7.5 Schedule Updates

**Services → Intrusion Detection → Administration:**

| Setting | Value |
|---------|-------|
| Update Cron | Every 6 hours |

---

## Phase 8: Q-Feeds Integration

### 8.1 Install Plugin

**System → Firmware → Plugins** → Install `os-q-feeds-connector`

### 8.2 Configure

**Security → Q-Feeds Connect:**

| Setting | Value |
|---------|-------|
| API Token | [from tip.qfeeds.com] |

Click **Apply**

### 8.3 Verify Feeds

**Security → Q-Feeds Connect → Feeds tab**

Confirm feeds show as licensed and updated.

### 8.4 Firewall Rules

**Firewall → Rules → WAN:**

| Setting | Value |
|---------|-------|
| Action | Block |
| Direction | in |
| Source | `__qfeeds_malware_ip` |
| Log | ✓ |
| Description | Block Q-Feeds threats inbound |

**Firewall → Rules → [Each VLAN]:**

| Setting | Value |
|---------|-------|
| Action | Block |
| Direction | in |
| Destination | `__qfeeds_malware_ip` |
| Log | ✓ |
| Description | Block Q-Feeds threats outbound |

---

## Phase 9: Threat Intel Aliases

### 9.1 Create IP Blocklist Aliases

**Firewall → Aliases → Add** (repeat for each):

**Spamhaus DROP:**

| Setting | Value |
|---------|-------|
| Name | Spamhaus_DROP |
| Type | URL Table (IPs) |
| Content | `https://www.spamhaus.org/drop/drop.txt` |
| Refresh | 86400 |

**FireHOL Level 1:**

| Setting | Value |
|---------|-------|
| Name | FireHOL_L1 |
| Type | URL Table (IPs) |
| Content | `https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset` |
| Refresh | 21600 |

**Abuse.ch Feodo:**

| Setting | Value |
|---------|-------|
| Name | Abusech_Feodo |
| Type | URL Table (IPs) |
| Content | `https://feodotracker.abuse.ch/downloads/ipblocklist.txt` |
| Refresh | 3600 |

### 9.2 Combined Alias

**Firewall → Aliases → Add:**

| Setting | Value |
|---------|-------|
| Name | Threat_IPs_All |
| Type | Network group |
| Content | Spamhaus_DROP, FireHOL_L1, Abusech_Feodo, __qfeeds_malware_ip |

### 9.3 Apply to Firewall

Use `Threat_IPs_All` in block rules (same pattern as Q-Feeds rules above).

---

## Phase 10: Monitoring (Telegraf)

### 10.1 Install

**System → Firmware → Plugins** → Install `os-telegraf`

### 10.2 Configure

**Services → Telegraf → General:**

| Setting | Value |
|---------|-------|
| Enable | ✓ |

**Services → Telegraf → Output:**

| Setting | Value |
|---------|-------|
| Enable InfluxDB v2 | ✓ |
| URL | http://10.0.50.10:8086 |
| Organization | homelab |
| Bucket | opnsense |
| Token | [your influxdb token] |

**Services → Telegraf → Input:**

Enable:
- [x] System
- [x] Network
- [x] PF
- [x] Suricata

### 10.3 Syslog Forwarding

**System → Settings → Logging / Targets → Add:**

| Setting | Value |
|---------|-------|
| Transport | UDP |
| Address | 10.0.50.10 |
| Port | 1514 |

---

## Phase 11: Final Checklist

### Pre-Migration

- [ ] Intel i350-T2 LP installed
- [ ] OPNsense installed and accessible
- [ ] All VLANs configured
- [ ] DHCP servers active
- [ ] Firewall rules in place
- [ ] Unbound DNS working
- [ ] Suricata IPS enabled
- [ ] Q-Feeds integrated
- [ ] Threat aliases configured
- [ ] Telegraf sending metrics

### Migration Day

1. **Backup Cloud Gateway Max config** (just in case)
2. **Update switch port** to trunk mode (all VLANs tagged)
3. **Disconnect Cloud Gateway Max WAN**
4. **Connect OPNsense WAN to ONT**
5. **Connect OPNsense LAN to switch**
6. **Test connectivity from each VLAN**
7. **Verify DNS resolution**
8. **Check Suricata alerts**
9. **Confirm Q-Feeds updating**

---

## Quick Reference

### URLs

| Service | URL |
|---------|-----|
| OPNsense GUI | https://10.0.0.1 |
| Grafana | http://10.0.50.10:3000 |
| InfluxDB | http://10.0.50.10:8086 |
| Q-Feeds Portal | https://tip.qfeeds.com |

### Key Aliases

| Alias | Purpose |
|-------|---------|
| `__qfeeds_malware_ip` | Q-Feeds threat IPs (auto-created) |
| `Threat_IPs_All` | Combined blocklist |
| `RFC1918` | Private IP ranges |

### VLAN Summary

| VLAN | Name | Subnet | Gateway |
|------|------|--------|---------|
| 1 | Management | 10.0.0.0/24 | 10.0.0.1 |
| 2 | Cameras | 10.0.20.0/24 | 10.0.20.1 |
| 3 | House | 10.0.30.0/24 | 10.0.30.1 |
| 4 | Main | 10.0.40.0/24 | 10.0.40.1 |
| 5 | Server | 10.0.50.0/24 | 10.0.50.1 |
| 6 | Lab | 10.0.60.0/24 | 10.0.60.1 |

---

## Hardware Summary

```
Dell OptiPlex 7060 SFF
├── CPU: i7-8700 (6C/12T)
├── RAM: 32GB DDR4
├── Storage: NVMe/SSD
└── NICs:
    ├── Intel I219-LM (onboard) → OPT/Management
    ├── Intel i350 Port 1 → WAN
    └── Intel i350 Port 2 → LAN Trunk
```

---

## Architecture Diagram

```
                           ┌─────────────────┐
                           │   Verizon ONT   │
                           │    (1 Gbps)     │
                           └────────┬────────┘
                                    │
                           ┌────────▼────────┐
                           │    OPNsense     │
                           │  Dell 7060 SFF  │
                           │    i7-8700      │
                           │   Suricata IPS  │
                           │   Unbound DNS   │
                           │    Q-Feeds      │
                           └────────┬────────┘
                                    │ (Trunk - All VLANs)
                           ┌────────▼────────┐
                           │  Managed Switch │
                           └────────┬────────┘
          ┌──────────┬──────────┬───┴───┬──────────┬──────────┐
          │          │          │       │          │          │
     ┌────▼───┐ ┌────▼───┐ ┌────▼──┐ ┌──▼───┐ ┌────▼───┐ ┌────▼───┐
     │ VLAN 1 │ │ VLAN 2 │ │VLAN 3 │ │VLAN 4│ │ VLAN 5 │ │ VLAN 6 │
     │  Mgmt  │ │Cameras │ │ House │ │ Main │ │ Server │ │  Lab   │
     │10.0.0.x│ │10.0.20.x│ │10.0.30│ │10.0.40│ │10.0.50.x│ │10.0.60.x│
     └────────┘ └────────┘ └───────┘ └──────┘ └────────┘ └────────┘
```
