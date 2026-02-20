# Network Architecture — Complete Reference v4
# Last updated: 2026-02-19

---

## v4 Change Log (notable deltas)

- **INFRA (VLAN 50) bridging clarified:** single L3 interface on the bridge only; members have **no IPs**; firewall rules evaluated on the bridge interface only. Tunables included for correct filtering behavior.
- **Dedicated storage link added:** Proxmox↔TrueNAS moved to **10.0.60.0/30** point-to-point; all NFS/iSCSI mounts use 10.0.60.2.
- **Flint 2 wired semantics fixed:** added `br-personal-wired` (VLAN 40) for most LAN ports; keep **one** LAN port mapped to VLAN 50 (INFRA).
- **SSH hardening:** removed `passwd -d root`; added Dropbear `authorized_keys` guidance; optional keys-only SSH; LuCI stays HTTPS.
- **Wi-Fi stability defaults:** HE160 → HE80; 802.11r disabled initially.
- **Kids egress policy updated:** allow TCP 80/443 to `!RFC1918`, allow UDP high ports to `!RFC1918`; stronger DNS controls (block DoT 853 + QUIC 443/udp) and explicit DoH endpoint blocking on 443/tcp.
- **NVR exception added:** host-specific allow rules for Dahua NVR access from admin sources (LAN + VPN).
- **VPN management scaffolding:** Tailscale subnet-router approach described; mgmt access constrained to mgmt targets/ports.

---

## 1. VLAN Scheme

| VLAN | Subnet | Gateway | Purpose | DHCP Range |
|------|---------|---------|---------|------------|
| 50 | 10.0.50.0/24 | 10.0.50.1 | Infrastructure | .100-.250 |
| 20 | 10.0.20.0/24 | 10.0.20.1 | IoT/Cameras | .100-.199 |
| 30 | 10.0.30.0/24 | 10.0.30.1 | Kids | .100-.199 |
| 40 | 10.0.40.0/24 | 10.0.40.1 | Personal | .100-.199 |
| 10 | 10.0.10.0/24 | 10.0.10.1 | Home Assistant | .100-.199 |


**CHANGE (v4): Dedicated storage point-to-point (not a VLAN)**

| Link | Subnet | Proxmox | TrueNAS | Notes |
|------|--------|---------|---------|-------|
| Storage P2P | 10.0.60.0/30 | 10.0.60.1/30 | 10.0.60.2/30 | No gateway; use only for NFS/iSCSI/SMB server-side as required |
---

## 2. Physical Topology

```
                            INTERNET
                               |
                           [em0 WAN]
                          ┌─────────┐
                          │ OPNsense│
                          │   x86   │
                          │         │
                          │ em0  WAN│──── ISP
                          │ igb0  HA│──── Home Assistant (VLAN 10, 10.0.10.0/24)
                          │ igb1 TRK│──── Flint 2 WAN port (VLAN trunk: 20,30,40,50)
                          │ ix0  10G│──── Proxmox AQC113 (VLAN trunk: 50 + future)
                          │ ix1  10G│──── (future — TrueNAS second NIC)
                          └─────────┘

                     [Proxmox - 10.0.50.10]
                     AQC113 10Gb ←── ix0 (VLAN 50)
                     RTL8126A 5Gb ←── (future)
                     Dedicated storage link ──→ TrueNAS (10.0.60.0/30, no gateway, no firewall)

                     [TrueNAS - 10.0.50.95]
                     Storage NIC ──→ Proxmox (10.0.60.2/30 ↔ 10.0.60.1/30)
                     Second NIC ──→ (future: OPNsense ix1 for management/updates)

                     [Flint 2 - GL-MT6000]
                     WAN port ←── igb1 (VLAN trunk)
                     IP: 10.0.50.5 (mgmt, VLAN 50)
                     OpenWRT 25.12.0-rc4
                          │
                     ┌────┴────────────────────────────┐
                     │ radio1 (5GHz MT7986)             │
                     │  SSID: "Personal" → VLAN 40      │
                     │  SSID: "IoT_Backhaul" → VLAN 20  │
                     │        (hidden, WDS for Marble)  │
                     │                                  │
                     │ radio0 (2.4GHz MT7986)           │
                     │  SSID: "StarBase" → VLAN 30      │
                     │  SSID: "IoT_Net" → VLAN 20       │
                     │        (hidden)                  │
                     └──────────────────────────────────┘

              [Marble - GL-B3000]
              WDS client → "IoT_Backhaul" (5GHz, trunk: V20+V30)
              IP: 10.0.20.15 (mgmt, IoT VLAN)
              OpenWRT 25.12.0-rc4
                     │
                     ├── radio0 (2.4GHz IPQ5018)
                     │   SSID: "StarBase" → VLAN 30 (Kids)
                     │   SSID: "IoT_Net" → VLAN 20 (hidden, IoT)
                     │
                     └── LAN ports: NVR + wired cameras (VLAN 20, 10.0.20.0/24)
```

**No managed switch required.** Every device has a dedicated OPNsense port.
GS305E stays in the drawer until more wired ports are needed.

---

## 3. OPNsense Interface Map

| Interface | Physical | VLAN | IP | Purpose |
|-----------|----------|------|----|---------|
| WAN | em0 | — | DHCP from ISP | Internet uplink |
| HASSVLAN | igb0 | — | 10.0.10.1/24 | Home Assistant (dedicated port) |
| OPT1 | igb1 | — | (no IP) | Trunk to Flint 2 |
| PERSONAL | igb1.40 | 40 | 10.0.40.1/24 | Personal devices |
| KIDS | igb1.30 | 30 | 10.0.30.1/24 | Kids devices |
| IOT | igb1.20 | 20 | 10.0.20.1/24 | IoT/Cameras |
| INFRA_BR | bridge0 (members below) | 50 | 10.0.50.1/24 | Infra L2 + routing (rules live here) |

**CHANGE (v4): VLAN 50 bridge-only L3**
- Create **bridge0** with members: **igb1.50** (tagged VLAN 50 subif) + **ix0** (Proxmox 10Gb).
- Put the **only** 10.0.50.1/24 address on **INFRA_BR (bridge0)**.
- Leave **igb1.50** and **ix0** **unassigned/no IP** (members only). Avoid “two interfaces in one subnet.”
- Evaluate firewall policy on **INFRA_BR only** (not on bridge members).

**Bridge filtering tunables (required for sane policy):**
- `net.link.bridge.pfil_member=0`
- `net.link.bridge.pfil_bridge=1`

(These ensure filtering happens on the bridge, not inconsistently on members.)

**RESOLVED: Suricata/IPS placement strategy (see Section 16).**

---

## 4. Static IP Assignments

### VLAN 50 — Infrastructure (10.0.50.0/24)
| IP | Device | Notes |
|----|--------|-------|
| 10.0.50.1 | OPNsense | Gateway (bridge: igb1.50 + ix0) |
| 10.0.50.5 | Flint 2 | AP + WDS base |
| 10.0.50.10 | Proxmox | Via ix0 10Gb direct |
| 10.0.50.15 | (available) | — |
| 10.0.50.95 | TrueNAS | When second NIC connected via ix1 |

### VLAN 40 — Personal (10.0.40.0/24)
| IP | Device | Notes |
|----|--------|-------|
| 10.0.40.1 | OPNsense | Gateway |
| 10.0.40.10 | Red Magic 10 Pro | **CHANGE (v4):** DHCP reservation (MAC DC:F0:90:F3:DF:AE) |
| 10.0.40.11 | iPhone 16e | **CHANGE (v4):** DHCP reservation (MAC 9C:79:E3:D1:DA:A8) |
| 10.0.40.12 | PC | **CHANGE (v4):** DHCP reservation (MAC 5C:B2:6D:E1:8B:FB) |
| 10.0.40.13 | Tablet | **CHANGE (v4):** DHCP reservation (MAC 5C:8B:6B:3C:D6:E7) |
| 10.0.40.100+ | Other Personal devices | DHCP |

### VLAN 30 — Kids (10.0.30.0/24)
| IP | Device | Notes |
|----|--------|-------|
| 10.0.30.1 | OPNsense | Gateway |
| 10.0.30.10 | TV #1 | Static DHCP |
| 10.0.30.11 | TV #2 | Static DHCP |
| 10.0.30.12 | TV #3 | Static DHCP |

### VLAN 20 — IoT/Cameras (10.0.20.0/24)
| IP | Device | Notes |
|----|--------|-------|
| 10.0.20.1 | OPNsense | Gateway |
| 10.0.20.15 | Marble | WDS bridge management |
| 10.0.20.20 | Dahua NV41AI8P-4K NVR | **CHANGE (v4):** recommend static DHCP reservation; PTZ camera is typically behind NVR PoE ports |
| 10.0.20.x | Blink cameras | DHCP |

### VLAN 10 — Home Assistant (10.0.10.0/24)
| IP | Device | Notes |
|----|--------|-------|
| 10.0.10.1 | OPNsense (igb0) | Gateway |
| 10.0.10.x | Home Assistant | DHCP or static TBD |

---

## 5. WiFi SSID Map

### Flint 2 (GL-MT6000)
| SSID | Band | Radio | VLAN | Subnet | Hidden | Password |
|------|------|-------|------|--------|--------|----------|
| Personal | 5GHz | radio1 | 40 | 10.0.40.0/24 | No | `PLACEHOLDER_PERSONAL_KEY` |
| IoT_Backhaul | 5GHz | radio1 | trunk(20+30) | — | Yes | `PLACEHOLDER_IOT_KEY` |
| StarBase | 2.4GHz | radio0 | 30 | 10.0.30.0/24 | No | `PLACEHOLDER_KIDS_KEY` |
| IoT_Net | 2.4GHz | radio0 | 20 | 10.0.20.0/24 | Yes | `PLACEHOLDER_IOT_KEY` |

### Marble (GL-B3000)
| SSID | Band | Radio | VLAN | Subnet | Hidden | Password |
|------|------|-------|------|--------|--------|----------|
| (WDS client) | 5GHz | radio1 | trunk(20+30) | — | — | `PLACEHOLDER_IOT_KEY` |
| StarBase | 2.4GHz | radio0 | 30 | 10.0.30.0/24 | No | `PLACEHOLDER_KIDS_KEY` |
| IoT_Net | 2.4GHz | radio0 | 20 | 10.0.20.0/24 | Yes | `PLACEHOLDER_IOT_KEY` |

All SSIDs use SAE-mixed encryption (WPA3/WPA2 transitional).
802.11r fast transition disabled initially on all SSIDs (stability-first; enable after validation).

---

## 6. Aliases

| Name | Type | Content |
|------|------|---------|
| RFC1918 | Network | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 |
| CGNAT_TAILSCALE | Network | 100.64.0.0/10 |
| NET_INFRA | Network | 10.0.50.0/24 |
| NET_PERSONAL | Network | 10.0.40.0/24 |
| NET_KIDS | Network | 10.0.30.0/24 |
| NET_IOT | Network | 10.0.20.0/24 |
| NET_HASS | Network | 10.0.10.0/24 |
| STORAGE_P2P | Network | 10.0.60.0/30 |
| OPNSENSE_MGMT | Host | 10.0.50.1, 10.0.40.1, 10.0.30.1, 10.0.20.1, 10.0.10.1 |
| PROXMOX | Host | 10.0.50.10 |
| TRUENAS | Host | 10.0.50.95 |
| FLINT_MGMT | Host | 10.0.50.5 |
| MARBLE_MGMT | Host | 10.0.20.15 |
| NVR_DAHUA | Host | 10.0.20.20 |
| ADMIN_CLIENTS | Host | 10.0.40.10, 10.0.40.11, 10.0.40.12, 10.0.40.13 |
| MGMT_TARGETS | Host | 10.0.50.1, 10.0.50.5, 10.0.20.15, 10.0.50.10, 10.0.50.95, 10.0.20.20 |
| DNS_ADGUARD | Host | 10.0.50.5 |
| CAST_PORTS_TCP | Port | 8008, 8009, 8443, 9000 |
| CAST_PORTS_UDP | Port | 32768:61000 |
| SMB_PORTS | Port | 139, 445 |
| NFS_PORTS | Port | 111, 2049 |
| IOT_UPDATE_PORTS | Port | 80, 443, 8883 |
| NVR_PORTS_TCP | Port | 443, 554, 37777 | **TBD:** start minimal, expand after confirming workflows (HTTP 80 removed unless needed) |
| NVR_PORTS_UDP | Port | 37778 | **TBD:** only if Dahua private protocol UDP is confirmed required |
| DOH_ENDPOINTS | Hostname | dns.google, dns.cloudflare.com, cloudflare-dns.com, mozilla.cloudflare-dns.com, dns.quad9.net, dns.nextdns.io |

**CHANGE (v4):** `DOH_ENDPOINTS` is intentionally a small starter set. Expand over time as you observe bypass attempts.

---

## 7. Firewall Rules

### 7a. PERSONAL (VLAN 40 — 10.0.40.0/24)

Goal: **Personal is “default deny to other VLANs”** with management exceptions constrained to `ADMIN_CLIENTS`.

| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | ICMP | NET_PERSONAL | PERSONAL address | * | Ping gateway |
| 2 | Pass | UDP | NET_PERSONAL | DNS_ADGUARD | 53 | **CHANGE (v4):** DNS → AdGuardHome (Flint) |
| 3 | Pass | TCP | NET_PERSONAL | DNS_ADGUARD | 53 | DNS TCP → AdGuardHome |
| 4 | Pass | UDP | NET_PERSONAL | PERSONAL address | 123 | NTP |
| 5 | Pass | TCP | ADMIN_CLIENTS | PERSONAL address | 443,22 | **CHANGE (v4):** OPNsense UI/SSH (admin only) |
| 6 | Pass | TCP | ADMIN_CLIENTS | PROXMOX | 8006,22 | Proxmox UI/SSH (admin only) |
| 7 | Pass | TCP | ADMIN_CLIENTS | TRUENAS | 443,22 | TrueNAS UI/SSH (admin only) |
| 8 | Pass | TCP | ADMIN_CLIENTS | TRUENAS | SMB_PORTS | SMB (admin only) |
| 9 | Pass | TCP/UDP | ADMIN_CLIENTS | TRUENAS | NFS_PORTS | NFS (admin only) |
| 10 | Pass | TCP | ADMIN_CLIENTS | FLINT_MGMT | 443,22 | Flint mgmt (LuCI/SSH) |
| 11 | Pass | TCP | ADMIN_CLIENTS | MARBLE_MGMT | 443,22 | Marble mgmt (LuCI/SSH) |
| 12 | Pass | TCP | ADMIN_CLIENTS | NET_HASS | 8123,22 | HA dashboard/SSH |
| 13 | Pass | TCP | ADMIN_CLIENTS | NVR_DAHUA | NVR_PORTS_TCP | **CHANGE (v4):** Dahua NVR UI/RTSP/private protocol |
| 14 | Pass | UDP | ADMIN_CLIENTS | NVR_DAHUA | NVR_PORTS_UDP | **CHANGE (v4):** Dahua UDP port |
| 15 | Pass | TCP | ADMIN_CLIENTS | KIDS_TVS | CAST_PORTS_TCP | Cast control (admin only) |
| 16 | Pass | UDP | ADMIN_CLIENTS | KIDS_TVS | CAST_PORTS_UDP | Cast media (admin only) |
| 17 | Pass | UDP | ADMIN_CLIENTS | KIDS_TVS | 5353 | mDNS to TVs (admin only) |
| 18 | Block | * | NET_PERSONAL | NET_KIDS | * | Block other Kids |
| 19 | Block | * | NET_PERSONAL | NET_IOT | * | Block IoT |
| 20 | Block | * | NET_PERSONAL | NET_INFRA | * | Block Infra (after specific allows) |
| 21 | Pass | TCP | NET_PERSONAL | !RFC1918 | 80,443 | Internet TCP |
| 22 | Pass | UDP | NET_PERSONAL | !RFC1918 | * | Internet UDP |
| 23 | Block | * | * | * | * | Deny all (log) |

### 7b. INFRA_BR (VLAN 50 — 10.0.50.0/24)

**CHANGE (v4):** Apply these rules on **INFRA_BR (bridge0)** only.

| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | ICMP | NET_INFRA | * | * | Ping anything (monitoring) |
| 2 | Pass | UDP | NET_INFRA | DNS_ADGUARD | 53 | DNS → AdGuardHome (local) |
| 3 | Pass | TCP | NET_INFRA | DNS_ADGUARD | 53 | DNS TCP → AdGuardHome |
| 4 | Pass | UDP | NET_INFRA | INFRA_BR address | 123 | NTP |
| 5 | Pass | * | NET_INFRA | NET_INFRA | * | Intra-VLAN (PVE mgmt, etc.) |
| 6 | Pass | TCP | NET_INFRA | !RFC1918 | 80,443 | Internet TCP |
| 7 | Pass | UDP | NET_INFRA | !RFC1918 | * | Internet UDP |
| 8 | Block | * | NET_INFRA | RFC1918 | * | Block inter-VLAN |
| 9 | Block | * | * | * | * | Deny all (log) |

### 7c. KIDS (VLAN 30 — 10.0.30.0/24)

Goal: allow “normal internet + gaming” while preventing DNS/DoH bypass.

| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | ICMP | NET_KIDS | KIDS address | * | Ping gateway |
| 2 | Pass | UDP | NET_KIDS | KIDS address | 123 | NTP |
| 3 | Block | TCP/UDP | NET_KIDS | * | 853 | **CHANGE (v4):** Block DoT (Private DNS) |
| 4 | Block | UDP | NET_KIDS | * | 443 | **CHANGE (v4):** Block QUIC |
| 5 | Block | TCP | NET_KIDS | DOH_ENDPOINTS | 443 | **CHANGE (v4):** Block known DoH endpoints |
| 6 | Pass | UDP | NET_KIDS | DNS_ADGUARD | 53 | **CHANGE (v4):** DNS → AdGuardHome only |
| 7 | Pass | TCP | NET_KIDS | DNS_ADGUARD | 53 | DNS TCP → AdGuardHome |
| 8 | Block | * | NET_KIDS | RFC1918 | * | Block inter-VLAN (after DNS allow) |
| 9 | Pass | TCP | NET_KIDS | !RFC1918 | 80,443 | **CHANGE (v4):** Web (HTTP/HTTPS) |
| 10 | Pass | UDP | NET_KIDS | !RFC1918 | 1024:65535 | **CHANGE (v4):** Gaming/voice/chat UDP high ports |
| 11 | Block | * | * | * | * | Deny all (log) |

### 7d. IOT (VLAN 20 — 10.0.20.0/24)

| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | ICMP | NET_IOT | IOT address | * | Ping gateway |
| 2 | Pass | UDP | NET_IOT | IOT address | 123 | NTP |
| 3 | Pass | UDP | NET_IOT | DNS_ADGUARD | 53 | **CHANGE (v4):** DNS → AdGuardHome |
| 4 | Pass | TCP | NET_IOT | DNS_ADGUARD | 53 | DNS TCP → AdGuardHome |
| 5 | Block | TCP | NET_IOT | IOT address | 443,22 | Block OPNsense mgmt |
| 6 | Block | * | NET_IOT | RFC1918 | * | Block inter-VLAN |
| 7 | Pass | TCP | NET_IOT | !RFC1918 | IOT_UPDATE_PORTS | Internet (updates/cloud) |
| 8 | Pass | UDP | NET_IOT | !RFC1918 | 123,443 | NTP + QUIC (if needed) |
| 9 | Block | * | * | * | * | Deny all (log) |

### 7e. HASSVLAN (VLAN 10 — 10.0.10.0/24)

| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | ICMP | NET_HASS | HASSVLAN address | * | Ping gateway |
| 2 | Pass | UDP | NET_HASS | HASSVLAN address | 123 | NTP |
| 3 | Pass | UDP | NET_HASS | DNS_ADGUARD | 53 | DNS → AdGuardHome |
| 4 | Pass | TCP | NET_HASS | DNS_ADGUARD | 53 | DNS TCP → AdGuardHome |
| 5 | Pass | * | NET_HASS | NET_IOT | * | HA → IoT (device control) |
| 6 | Pass | * | NET_HASS | NET_KIDS | * | HA → Kids (TV automation) |
| 7 | Pass | TCP | NET_HASS | !RFC1918 | 443,8883 | Internet (integrations) |
| 8 | Pass | UDP | NET_HASS | !RFC1918 | 443,123 | QUIC + NTP |
| 9 | Block | * | NET_HASS | RFC1918 | * | Block other VLANs |
| 10 | Block | * | * | * | * | Deny all (log) |

### 7f. VPN_MGMT (Tailscale subnet-router on OPNsense)

**CHANGE (v4):** Preferred “manage everything from anywhere” path without opening inter-VLAN LAN rules.

Assumptions:
- OPNsense runs Tailscale as a **subnet router** advertising `10.0.10.0/24,10.0.20.0/24,10.0.30.0/24,10.0.40.0/24,10.0.50.0/24`.
- Remote admin devices connect via Tailscale and reach LAN subnets via routes.

Rules (apply on the Tailscale interface):
| # | Act | Proto | Source | Dest | Port | Note |
|---|-----|-------|--------|------|------|------|
| 1 | Pass | TCP | CGNAT_TAILSCALE | MGMT_TARGETS | 22,443,8006 | VPN → mgmt targets (UI/SSH/PVE) |
| 2 | Pass | TCP/UDP | CGNAT_TAILSCALE | NVR_DAHUA | NVR_PORTS_TCP,NVR_PORTS_UDP | VPN → Dahua NVR |
| 3 | Block | * | * | * | * | Deny all (log) |

### 7g. Floating Rules

| # | Act | Dir | Interfaces | Proto | Source | Dest | Port | Quick |
|---|-----|-----|------------|-------|--------|------|------|-------|
| 1 | Block | in | KIDS, IOT | * | * | OPNSENSE_MGMT | 443,22 | ✓ |
| 2 | Block | out | WAN | * | RFC1918 | * | * | ✓ |

---

## 8. Flint 2 — Multi-SSID VLAN AP Config

**Firmware Selector URL:**
`https://firmware-selector.openwrt.org/?version=25.12.0-rc4&target=mediatek/filogic&id=glinet_gl-mt6000`

**Packages:** `luci luci-ssl`

**Script:**

```bash
#!/bin/sh

# ============================================
# Flint 2 (GL-MT6000) — Multi-SSID VLAN AP
# OpenWRT 25.12.0-rc4
# Management: 10.0.50.5 (VLAN 50)
# Personal (5GHz/V40), StarBase (2.4GHz/V30)
# IoT_Net (2.4GHz/V20), IoT_Backhaul (5GHz/V20/WDS)
# ============================================

# CHANGE (v4): do NOT delete root password. Set a strong password + SSH keys.

uci set system.@system[0].hostname='flint2-ap'
uci set system.@system[0].timezone='EST5EDT,M3.2.0,M11.1.0'
uci set system.@system[0].zonename='America/New_York'
uci commit system


# --- SSH hardening (CHANGE v4) ---
# 1) Set a strong root password interactively before/after running this script:
#    passwd
# 2) Install your SSH public key(s) for Dropbear:
mkdir -p /etc/dropbear
cat > /etc/dropbear/authorized_keys << 'EOF'
PLACEHOLDER_SSH_PUBKEY_1
# PLACEHOLDER_SSH_PUBKEY_2
EOF
chmod 600 /etc/dropbear/authorized_keys

# IMPORTANT: Do NOT disable password auth until key-auth is verified from at least 2 admin devices.
# Once confirmed, uncomment the lines below:
# uci set dropbear.@dropbear[0].PasswordAuth='off'
# uci set dropbear.@dropbear[0].RootPasswordAuth='off'
# uci commit dropbear
# /etc/init.d/dropbear restart

# --- Disable services (pure AP) ---
/etc/init.d/firewall disable
/etc/init.d/firewall stop
/etc/init.d/dnsmasq disable

# --- Network ---
uci delete network.wan 2>/dev/null
uci delete network.wan6 2>/dev/null
uci delete network.lan 2>/dev/null

# --- Auto-detect trunk uplink interface ---
# GL-MT6000 DSA: WAN port is commonly eth1 (not eth0). Detect at runtime.
TRUNK_IF=$(uci -q get network.wan.device || uci -q get network.wan.ifname || echo "eth0")
# Fallback: inspect ip link for the interface connected to WAN port
if [ "$TRUNK_IF" = "eth0" ]; then
    # Double-check: if eth1 exists and has a carrier, prefer it
    if ip link show eth1 >/dev/null 2>&1; then
        logger -t vlan-setup "Detected eth1 — using as trunk uplink (DSA WAN)"
        TRUNK_IF="eth1"
    fi
fi
logger -t vlan-setup "Trunk uplink interface: $TRUNK_IF"

# VLAN sub-interfaces on trunk uplink (WAN port → OPNsense igb1 trunk)
for VID in 50 40 30 20; do
    uci set network.${TRUNK_IF}_v${VID}=device
    uci set network.${TRUNK_IF}_v${VID}.type='8021q'
    uci set network.${TRUNK_IF}_v${VID}.ifname="$TRUNK_IF"
    uci set network.${TRUNK_IF}_v${VID}.vid="$VID"
    uci set network.${TRUNK_IF}_v${VID}.name="${TRUNK_IF}.${VID}"
done

# --- Management bridge (VLAN 50) ---
uci set network.br_mgmt=device
uci set network.br_mgmt.type='bridge'
uci set network.br_mgmt.name='br-mgmt'
uci add_list network.br_mgmt.ports="${TRUNK_IF}.50"
uci add_list network.br_mgmt.ports='lan5'  # CHANGE (v4): dedicate one LAN port to VLAN 50 (INFRA)

uci set network.mgmt=interface
uci set network.mgmt.proto='static'
uci set network.mgmt.ipaddr='10.0.50.5'
uci set network.mgmt.netmask='255.255.255.0'
uci set network.mgmt.gateway='10.0.50.1'
uci set network.mgmt.dns='10.0.50.1'
uci set network.mgmt.device='br-mgmt'

# --- Personal bridge (VLAN 40) ---
uci set network.br_personal=device
uci set network.br_personal.type='bridge'
uci set network.br_personal.name='br-personal-wired'  # CHANGE (v4): VLAN 40 wired + Wi-Fi
uci add_list network.br_personal.ports="${TRUNK_IF}.40"
uci add_list network.br_personal.ports='lan1'
uci add_list network.br_personal.ports='lan2'
uci add_list network.br_personal.ports='lan3'
uci add_list network.br_personal.ports='lan4'

uci set network.personal=interface
uci set network.personal.proto='none'
uci set network.personal.device='br-personal-wired'  # CHANGE (v4)

# --- Kids bridge (VLAN 30) ---
uci set network.br_kids=device
uci set network.br_kids.type='bridge'
uci set network.br_kids.name='br-kids'
uci add_list network.br_kids.ports="${TRUNK_IF}.30"

uci set network.kids=interface
uci set network.kids.proto='none'
uci set network.kids.device='br-kids'

# --- IoT bridge (VLAN 20) ---
uci set network.br_iot=device
uci set network.br_iot.type='bridge'
uci set network.br_iot.name='br-iot'
uci add_list network.br_iot.ports="${TRUNK_IF}.20"

uci set network.iot=interface
uci set network.iot.proto='none'
uci set network.iot.device='br-iot'

# --- WDS trunk bridge (carries tagged V20+V30 to/from Marble) ---
# IoT_Backhaul's WDS peer joins this bridge. VLAN sub-interfaces
# on the WDS peer interface route frames to the correct per-VLAN bridges.
# We need a hotplug script to create VLAN sub-interfaces when the
# WDS peer connects. See /etc/hotplug.d/net/99-wds-vlan below.
uci set network.br_wds_trunk=device
uci set network.br_wds_trunk.type='bridge'
uci set network.br_wds_trunk.name='br-wds-trunk'

uci set network.wds_trunk=interface
uci set network.wds_trunk.proto='none'
uci set network.wds_trunk.device='br-wds-trunk'

uci commit network

# --- DHCP: all disabled ---
for iface in mgmt personal kids iot; do
    uci set dhcp.${iface}=dhcp
    uci set dhcp.${iface}.interface="${iface}"
    uci set dhcp.${iface}.ignore='1'
done
uci set dhcp.@dnsmasq[0].port='0'
uci set dhcp.@dnsmasq[0].localuse='0'
uci commit dhcp

# --- WiFi radios ---
uci set wireless.radio0.disabled='0'
uci set wireless.radio1.disabled='0'

uci set wireless.radio0.channel='auto'
uci set wireless.radio0.band='2g'
uci set wireless.radio0.htmode='HE40'
uci set wireless.radio0.country='US'

uci set wireless.radio1.channel='auto'
uci set wireless.radio1.band='5g'
uci set wireless.radio1.htmode='HE80'  # CHANGE (v4): stability-first
uci set wireless.radio1.country='US'

# --- Clear defaults ---
uci delete wireless.default_radio0 2>/dev/null
uci delete wireless.default_radio1 2>/dev/null

# --- Personal (5GHz, VLAN 40) ---
uci set wireless.personal=wifi-iface
uci set wireless.personal.device='radio1'
uci set wireless.personal.mode='ap'
uci set wireless.personal.ssid='Personal'
uci set wireless.personal.encryption='sae-mixed'
uci set wireless.personal.key='PLACEHOLDER_PERSONAL_KEY'
uci set wireless.personal.network='personal'
uci set wireless.personal.ieee80211r='0'  # CHANGE (v4): disable 11r initially
uci set wireless.personal.ft_over_ds='0'
uci set wireless.personal.ft_psk_generate_local='1'

# --- IoT_Backhaul (5GHz, WDS trunk for Marble — carries V20+V30) ---
# Maps to wds_trunk bridge initially. Hotplug script moves WDS peer
# VLAN sub-interfaces to br-iot (V20) and br-kids (V30).
uci set wireless.iot_backhaul=wifi-iface
uci set wireless.iot_backhaul.device='radio1'
uci set wireless.iot_backhaul.mode='ap'
uci set wireless.iot_backhaul.ssid='IoT_Backhaul'
uci set wireless.iot_backhaul.encryption='sae-mixed'
uci set wireless.iot_backhaul.key='PLACEHOLDER_IOT_KEY'
uci set wireless.iot_backhaul.network='wds_trunk'
uci set wireless.iot_backhaul.wds='1'
uci set wireless.iot_backhaul.hidden='1'

# --- StarBase (2.4GHz, VLAN 30) ---
uci set wireless.starbase=wifi-iface
uci set wireless.starbase.device='radio0'
uci set wireless.starbase.mode='ap'
uci set wireless.starbase.ssid='StarBase'
uci set wireless.starbase.encryption='sae-mixed'
uci set wireless.starbase.key='PLACEHOLDER_KIDS_KEY'
uci set wireless.starbase.network='kids'
uci set wireless.starbase.ieee80211r='0'  # CHANGE (v4): disable 11r initially
uci set wireless.starbase.ft_over_ds='0'
uci set wireless.starbase.ft_psk_generate_local='1'

# --- IoT_Net (2.4GHz, VLAN 20, hidden) ---
uci set wireless.iot_net=wifi-iface
uci set wireless.iot_net.device='radio0'
uci set wireless.iot_net.mode='ap'
uci set wireless.iot_net.ssid='IoT_Net'
uci set wireless.iot_net.encryption='sae-mixed'
uci set wireless.iot_net.key='PLACEHOLDER_IOT_KEY'
uci set wireless.iot_net.network='iot'
uci set wireless.iot_net.hidden='1'

uci commit wireless

# --- Hotplug: bridge WDS peer VLANs to correct bridges ---
# When Marble connects via WDS, a peer interface (wlan1-1 or similar) appears.
# Untagged frames from Marble → br-iot (VLAN 20: NVR, IoT_Net clients, Marble mgmt)
# Tagged VID 30 from Marble → br-kids (VLAN 30: StarBase clients)
mkdir -p /etc/hotplug.d/net
cat > /etc/hotplug.d/net/99-wds-vlan << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "add" ] || exit 0
case "$INTERFACE" in
    wlan1-*)
        logger -t wds-vlan "WDS peer $INTERFACE detected"

        # Remove from whatever default bridge
        for br in $(ls /sys/class/net/*/brif/"$INTERFACE" 2>/dev/null | cut -d/ -f5); do
            brctl delif "$br" "$INTERFACE" 2>/dev/null
        done

        # Untagged → br-iot (VLAN 20)
        brctl addif br-iot "$INTERFACE" 2>/dev/null

        # Tagged VID 30 → br-kids
        ip link add link "$INTERFACE" name "${INTERFACE}.30" type vlan id 30
        ip link set "${INTERFACE}.30" up
        brctl addif br-kids "${INTERFACE}.30" 2>/dev/null

        logger -t wds-vlan "$INTERFACE→br-iot(V20), ${INTERFACE}.30→br-kids(V30)"
        ;;
esac
HOTPLUG
chmod +x /etc/hotplug.d/net/99-wds-vlan

reload_config
```

### Flash Procedure — Flint 2

1. Build custom image via Firmware Selector (add packages + script above)
2. **Replace all PLACEHOLDER passwords before building**
3. Download **sysupgrade.bin**
4. GL.iNet Admin → System → Upgrade → Local Upgrade
5. Upload .bin, **UNCHECK "Keep Settings"**
6. Wait ~2-3 min for reboot
7. Set PC to 10.0.50.x/24, access LuCI at 10.0.50.5

**Fallback (U-Boot):** Hold reset + power, static IP 192.168.1.2/24, browse to 192.168.1.1

### Post-Flash Verification

```bash
ssh root@10.0.50.5

# Radios + SSIDs
iwinfo
# Should show: Personal (5GHz), IoT_Backhaul (5GHz), StarBase (2.4GHz), IoT_Net (2.4GHz)

# Network
ip addr show br-mgmt        # 10.0.50.5/24
# Verify VLAN sub-interfaces (trunk may be eth0 or eth1 depending on DSA)
ip link | grep -E '\.(20|30|40|50)@'   # All 4 VLAN sub-interfaces UP
brctl show                   # 5 bridges: br-mgmt, br-personal, br-kids, br-iot, br-wds-trunk

# Hotplug script installed
cat /etc/hotplug.d/net/99-wds-vlan  # Should exist

# Connectivity
ping -c 3 10.0.50.1         # OPNsense
ping -c 3 1.1.1.1           # Internet

# No local services
ps | grep dnsmasq            # Not running
iptables -t nat -L           # Empty

# After Marble connects, verify WDS VLAN bridging:
logread | grep wds-vlan      # Should show hotplug triggered
brctl show br-iot            # Should include wlan1-1
brctl show br-kids           # Should include wlan1-1.30
```

---

## 9. Marble — Multi-SSID VLAN Bridge + WDS Client

The Marble extends WiFi coverage with the same SSIDs as the Flint 2.
The WDS uplink carries tagged VLAN traffic (trunk), and the Marble
bridges each VLAN to the appropriate local SSID and LAN ports.

**Marble SSID/VLAN layout:**

| Interface | Band | SSID | VLAN | Network |
|-----------|------|------|------|---------|
| wds_client (5GHz) | 5GHz | IoT_Backhaul | trunk (20+30) | — |
| starbase (2.4GHz) | 2.4GHz | StarBase | 30 | kids |
| iot_net (2.4GHz) | 2.4GHz | IoT_Net (hidden) | 20 | iot |
| LAN ports | wired | — | 20 | iot |

**Management:** 10.0.20.15 on IoT VLAN (br-iot)

**WDS trunk design:** The WDS link (4addr/WDS mode) creates a transparent
L2 tunnel. We create VLAN sub-interfaces on top of the WDS interface
(wlan1 → wlan1.20, wlan1.30) and bridge each to the matching local bridge.
This is the same pattern as the Flint 2's eth0.XX trunking but over wireless.

**Firmware Selector URL:**
`https://firmware-selector.openwrt.org/?version=25.12.0-rc4&target=qualcommax/ipq50xx&id=glinet_gl-b3000`

**Packages:** `luci luci-ssl`

**Script:**

```bash
#!/bin/sh

# ============================================
# Marble (GL-B3000) — Multi-SSID VLAN Bridge
# OpenWRT 25.12.0-rc4
# WDS client → Flint 2 "IoT_Backhaul" (5GHz)
# 2.4GHz APs: StarBase (V30), IoT_Net (V20)
# LAN ports: NVR + cameras (VLAN 20)
# Management: 10.0.20.15 (IoT VLAN)
# ============================================

# CHANGE (v4): do NOT delete root password. Set a strong password + SSH keys.

uci set system.@system[0].hostname='marble-bridge'
uci set system.@system[0].timezone='EST5EDT,M3.2.0,M11.1.0'
uci set system.@system[0].zonename='America/New_York'
uci commit system


# --- SSH hardening (CHANGE v4) ---
# 1) Set a strong root password interactively before/after running this script:
#    passwd
# 2) Install your SSH public key(s) for Dropbear:
mkdir -p /etc/dropbear
cat > /etc/dropbear/authorized_keys << 'EOF'
PLACEHOLDER_SSH_PUBKEY_1
# PLACEHOLDER_SSH_PUBKEY_2
EOF
chmod 600 /etc/dropbear/authorized_keys

# IMPORTANT: Do NOT disable password auth until key-auth is verified from at least 2 admin devices.
# Once confirmed, uncomment the lines below:
# uci set dropbear.@dropbear[0].PasswordAuth='off'
# uci set dropbear.@dropbear[0].RootPasswordAuth='off'
# uci commit dropbear
# /etc/init.d/dropbear restart

/etc/init.d/firewall disable
/etc/init.d/firewall stop
/etc/init.d/dnsmasq disable

# --- Network: delete defaults ---
uci delete network.wan 2>/dev/null
uci delete network.wan6 2>/dev/null
uci delete network.lan 2>/dev/null

# --- WDS uplink interface (raw, no IP — trunk carrier) ---
# The WDS client creates wlan1. We VLAN-tag on top of it.
# wlan1 itself joins no bridge — only its VLAN sub-interfaces do.

# VLAN sub-interfaces on WDS uplink (created after WiFi is up)
# These are defined here but won't activate until wlan1 exists.
uci set network.wds_v20=device
uci set network.wds_v20.type='8021q'
uci set network.wds_v20.ifname='wlan1'
uci set network.wds_v20.vid='20'
uci set network.wds_v20.name='wlan1.20'

uci set network.wds_v30=device
uci set network.wds_v30.type='8021q'
uci set network.wds_v30.ifname='wlan1'
uci set network.wds_v30.vid='30'
uci set network.wds_v30.name='wlan1.30'

# --- IoT bridge (VLAN 20) — NVR + IoT_Net + WDS VLAN 20 ---
uci set network.br_iot=device
uci set network.br_iot.type='bridge'
uci set network.br_iot.name='br-iot'
uci add_list network.br_iot.ports='wlan1.20'
uci add_list network.br_iot.ports='eth0'
uci add_list network.br_iot.ports='eth1'

uci set network.iot=interface
uci set network.iot.proto='static'
uci set network.iot.ipaddr='10.0.20.15'
uci set network.iot.netmask='255.255.255.0'
uci set network.iot.gateway='10.0.20.1'
uci set network.iot.dns='10.0.20.1'
uci set network.iot.device='br-iot'

# --- Kids bridge (VLAN 30) — StarBase + WDS VLAN 30 ---
uci set network.br_kids=device
uci set network.br_kids.type='bridge'
uci set network.br_kids.name='br-kids'
uci add_list network.br_kids.ports='wlan1.30'

uci set network.kids=interface
uci set network.kids.proto='none'
uci set network.kids.device='br-kids'

uci commit network

# --- DHCP: all disabled ---
for iface in iot kids; do
    uci set dhcp.${iface}=dhcp
    uci set dhcp.${iface}.interface="${iface}"
    uci set dhcp.${iface}.ignore='1'
done
uci set dhcp.@dnsmasq[0].port='0'
uci set dhcp.@dnsmasq[0].localuse='0'
uci commit dhcp

# --- WiFi radios ---
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.band='2g'
uci set wireless.radio0.htmode='HE40'
uci set wireless.radio0.country='US'

uci set wireless.radio1.disabled='0'
uci set wireless.radio1.channel='auto'
uci set wireless.radio1.band='5g'
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.country='US'

uci delete wireless.default_radio0 2>/dev/null
uci delete wireless.default_radio1 2>/dev/null

# --- WDS client uplink (5GHz → Flint 2 IoT_Backhaul) ---
# network='iot' so wlan1 is created; VLAN sub-interfaces ride on top
uci set wireless.wds_client=wifi-iface
uci set wireless.wds_client.device='radio1'
uci set wireless.wds_client.mode='sta'
uci set wireless.wds_client.ssid='IoT_Backhaul'
uci set wireless.wds_client.encryption='sae-mixed'
uci set wireless.wds_client.key='PLACEHOLDER_IOT_KEY'
uci set wireless.wds_client.network='iot'
uci set wireless.wds_client.wds='1'

# --- StarBase (2.4GHz, VLAN 30, Kids) ---
uci set wireless.starbase=wifi-iface
uci set wireless.starbase.device='radio0'
uci set wireless.starbase.mode='ap'
uci set wireless.starbase.ssid='StarBase'
uci set wireless.starbase.encryption='sae-mixed'
uci set wireless.starbase.key='PLACEHOLDER_KIDS_KEY'
uci set wireless.starbase.network='kids'
uci set wireless.starbase.ieee80211r='0'  # CHANGE (v4): disable 11r initially
uci set wireless.starbase.ft_over_ds='0'
uci set wireless.starbase.ft_psk_generate_local='1'

# --- IoT_Net (2.4GHz, VLAN 20, hidden) ---
uci set wireless.iot_net=wifi-iface
uci set wireless.iot_net.device='radio0'
uci set wireless.iot_net.mode='ap'
uci set wireless.iot_net.ssid='IoT_Net'
uci set wireless.iot_net.encryption='sae-mixed'
uci set wireless.iot_net.key='PLACEHOLDER_IOT_KEY'
uci set wireless.iot_net.network='iot'
uci set wireless.iot_net.hidden='1'

uci commit wireless

reload_config
```

**IMPORTANT — WDS VLAN trunking caveat:**

VLAN tagging over WDS (wlan1.20, wlan1.30) requires the WDS link to support
frames larger than 1500 bytes (VLAN header adds 4 bytes). This is normally
fine on ath11k but worth verifying after flash. If VLAN-tagged frames don't
pass over WDS, the fallback is:

**Fallback approach:** Instead of VLAN trunking over WDS, use the Flint 2's
IoT_Backhaul SSID mapped to a dedicated "marble-trunk" bridge that carries
untagged frames. Then on both sides, use ebtables or bridge VLAN filtering
to separate traffic. This is more complex — try the VLAN-over-WDS approach
first.

**Alternative fallback:** Create TWO WDS links — one for each VLAN. Marble's
5GHz radio connects to IoT_Backhaul (VLAN 20) for IoT traffic, and a second
hidden SSID "Kids_Backhaul" (VLAN 30) on the Flint 2's 5GHz radio for Kids
traffic. The Marble's 5GHz radio can only do one WDS client connection though,
so this would require the 2.4GHz radio to handle one of the WDS links — not
ideal. Stick with VLAN-over-WDS as primary approach.

### Flash Procedure — Marble

**MUST use factory.img via U-Boot recovery.**

1. Build via Firmware Selector (add packages + script, replace passwords)
2. Download **factory.img** (NOT sysupgrade)
3. Power off Marble
4. Hold reset, power on, hold ~10sec until LED flashes
5. Ethernet from PC to Marble LAN port
6. PC static IP: 192.168.1.2/24
7. Browse to http://192.168.1.1 → U-Boot recovery
8. Upload factory.img
9. Wait ~2-3 min
10. Change PC to 10.0.20.x/24
11. Access LuCI at 10.0.20.15

**Flash Marble AFTER Flint 2 is up and broadcasting IoT_Backhaul.**

### Post-Flash Verification

```bash
ssh root@10.0.20.15

# Radios + SSIDs
iwinfo
# Should show: wds_client (5GHz, IoT_Backhaul), StarBase (2.4GHz), IoT_Net (2.4GHz)

# WDS signal quality
iwinfo wlan1 info | grep Signal  # Should be > -65 dBm

# Bridges
brctl show
# br-iot: eth0 + eth1 + wlan1.20 + wlan0-1 (IoT_Net)
# br-kids: wlan1.30 + wlan0 (StarBase)

# Management IP
ip addr show br-iot              # 10.0.20.15/24

# VLAN sub-interfaces on WDS
ip link show wlan1.20            # VLAN 20 over WDS — UP
ip link show wlan1.30            # VLAN 30 over WDS — UP

# Connectivity
ping -c 3 10.0.20.1             # OPNsense (IoT gateway)
ping -c 3 10.0.50.5             # Flint 2 (should FAIL — inter-VLAN blocked)
ping -c 3 1.1.1.1               # Internet (if IOT rules allow)

# Test Kids VLAN path
# Connect a device to StarBase near Marble
# Device should get DHCP on 10.0.30.x from OPNsense
```

---

## 10. OPNsense ix0 → Proxmox Configuration

### OPNsense Side (bridge-only for VLAN 50)

**CHANGE (v4):** do **not** run two interfaces in the same 10.0.50.0/24.

1. **Interfaces > Assignments** — ensure you have:
   - `igb1` (OPT1 trunk to Flint) unnumbered
   - `igb1_vlan50` (igb1.50) created as VLAN 50 subif (no IP)
   - `ix0` present (no IP)
2. **Interfaces > Other Types > Bridge**
   - Create `bridge0` with members = `igb1_vlan50` + `ix0`
3. **Interfaces > Assignments**
   - Assign `bridge0` as `INFRA_BR`
   - Set `INFRA_BR` = `10.0.50.1/24`
4. **System > Settings > Tunables**
   - `net.link.bridge.pfil_member=0`
   - `net.link.bridge.pfil_bridge=1`
5. Apply **all** VLAN 50 firewall rules on `INFRA_BR` only.

### Proxmox Side (management + dedicated storage /30)

Proxmox uses AQC113 as management on VLAN 50 (via ix0/bridge0), plus a dedicated storage NIC on 10.0.60.0/30.

```bash
# /etc/network/interfaces (on Proxmox)
auto lo
iface lo inet loopback

# AQC113 10Gb → OPNsense ix0 (member of bridge0 via VLAN 50)
auto enp_aqc113    # actual interface name varies — check with: ip link
iface enp_aqc113 inet manual

auto vmbr0
iface vmbr0 inet static
    address 10.0.50.10/24
    gateway 10.0.50.1
    bridge-ports enp_aqc113
    bridge-stp off
    bridge-fd 0

# Dedicated storage NIC → TrueNAS (10.0.60.0/30, no gateway)
auto enp_storage    # actual interface name varies
iface enp_storage inet static
    address 10.0.60.1/30
    # No gateway — storage traffic only
```

TrueNAS storage NIC:
- IP: `10.0.60.2/30`
- No gateway
- Mount/export NFS/iSCSI using `10.0.60.2`

**Mount target (v4):**
- NFS/iSCSI initiators use `10.0.60.2` (not 10.0.50.x)

Get actual interface names:
```bash
ip link | grep -E "^[0-9]" | awk '{print $2}' | tr -d ':'
```

---

## 11. Casting (PERSONAL ↔ KIDS)

Same as v2 doc. After all VLANs are live:

1. Install os-mdns-repeater + os-udpbroadcastrelay on OPNsense
2. mdns-repeater: interfaces PERSONAL + KIDS
3. UDP broadcast relay: port 1900 (SSDP), interfaces PERSONAL + KIDS
4. Firewall rules already in Section 7a (rules 15-17)

---

## 12. DNS Filtering (Kids VLAN 30)

**CHANGE (v4): DNS path**
- Clients on all VLANs use **AdGuardHome on Flint 2** (`DNS_ADGUARD = 10.0.50.5`) as their DNS server (DHCP option).
- AdGuardHome upstream forwards to **Unbound on OPNsense** for recursive resolution (privacy), or to your chosen upstreams via Unbound.

### A) DHCP options (OPNsense)

For each VLAN DHCP scope, set:
- DNS server 1: `10.0.50.5` (AdGuardHome / Flint 2)
- DNS server 2 (optional fallback): that VLAN gateway (10.0.x.1 running Unbound)

### B) Enforcing “Kids can’t bypass DNS”

1. On **KIDS (VLAN 30)**:
   - Block DoT: TCP/UDP 853
   - Block QUIC: UDP 443
   - Block known DoH endpoints on TCP 443 (`DOH_ENDPOINTS`)
2. Keep **only** DNS to `10.0.50.5` allowed (53/tcp+udp).
3. Expand `DOH_ENDPOINTS` as you observe.

Optional hard enforcement (if needed later):
- NAT redirect all outbound 53 from KIDS → `10.0.50.5` (forces hardcoded DNS back to AdGuard).

### C) Unbound (OPNsense) — upstream recursion

Services > Unbound DNS:
- Enable Unbound
- Enable DNSSEC (optional, recommended)
- Add your blocklists here **only if** you want layered protection beyond AdGuardHome.
- Restrict listening interfaces as desired (typically all internal, or at least VLAN 50 for Flint).

### D) AdGuardHome (Flint 2)

Install and bind AdGuardHome to listen on `10.0.50.5:53` (and optionally `0.0.0.0:53`).

Minimum policies to implement:
- Kids: SafeSearch / Parental filtering / category blocks as desired
- Logging enabled (at least during commissioning)

**Log retention:** you mentioned Splunk on `10.0.50.208`; plan to ship:
- OPNsense firewall logs (syslog)
- AdGuard query logs (if supported / or periodic export)

---

## 13. Implementation Order

### Phase 1: OPNsense Core
- [ ] Assign ix0, create bridge (igb1.50 + ix0) as INFRA
- [ ] Create VLANs 20, 30, 40 on igb1
- [ ] Configure interfaces + DHCP for each VLAN
- [ ] Create all aliases
- [ ] Add PERSONAL (VLAN 40) firewall rules FIRST
- [ ] Test: device on VLAN 40 gets internet
- [ ] Add INFRA, KIDS, IOT, HASS rules
- [ ] Test each VLAN

### Phase 2: Proxmox Migration
- [ ] Reconfigure Proxmox networking to use AQC113 → ix0
- [ ] Verify Proxmox management at 10.0.50.10
- [ ] Verify Proxmox internet access (updates)
- [ ] Verify Proxmox ↔ TrueNAS storage link still works

### Phase 3: Flash Flint 2
- [ ] Build firmware (replace PLACEHOLDER passwords)
- [ ] Flash via GL.iNet admin panel
- [ ] Connect Flint 2 WAN → OPNsense igb1
- [ ] Verify 4 SSIDs broadcasting
- [ ] Test: Personal → VLAN 40 → internet
- [ ] Test: StarBase → VLAN 30 → filtered internet
- [ ] Test: IoT_Net → VLAN 20 → limited internet

### Phase 4: Flash Marble
- [ ] Build firmware (replace PLACEHOLDER passwords)
- [ ] Flash via U-Boot recovery (factory.img)
- [ ] Verify WDS connects to IoT_Backhaul
- [ ] Plug NVR into Marble LAN
- [ ] Test: NVR gets DHCP on 10.0.20.x
- [ ] Test: NVR internet (Blink cloud)
- [ ] Test: Marble management at 10.0.20.15

### Phase 5: Home Assistant
- [ ] Verify PERSONAL VLAN GUI access
- [ ] Reassign igb0 from LAN to HASSVLAN (10.0.10.1/24)
- [ ] Configure HA on 10.0.10.x
- [ ] Add HASS firewall rules
- [ ] Test: HA dashboard from Personal
- [ ] Test: HA → IoT device control

### Phase 6: Casting + Cleanup
- [ ] mdns-repeater + udpbroadcastrelay
- [ ] Test casting: Personal phone → Kids TV
- [ ] Kill 172.16.x.x subnets
- [ ] Set root passwords on all devices
- [ ] Backup everything
- [ ] Monitor deny-all logs 48hrs

---

## 14. Rollback

### Flint 2
U-Boot recovery: hold reset + power → 192.168.1.1 → upload GL.iNet stock .img

### Marble
U-Boot recovery: same procedure → upload GL.iNet stock .img

### OPNsense
System > Configuration > Backups > Restore from backup taken before changes

### Proxmox
Edit /etc/network/interfaces to restore old NIC config, reboot

Both GL.iNet devices have intact U-Boot — cannot be bricked by bad firmware.

---

## 15. Future Expansion

When needed:
- **TrueNAS second NIC → ix1:** Direct 10Gb to OPNsense for management/updates
- **GS305E:** Insert between igb1 and Flint 2 when more wired devices needed
- **Additional VLANs:** Guest WiFi, lab network, etc.
- **Proxmox VM VLANs:** Enable VLAN-aware bridging on vmbr0, tag VMs onto 20/30/40

---

## 16. Suricata IPS — Placement, Enablement Checklist, and Future-Proofing

### Background

Suricata IPS uses netmap for inline packet capture. Netmap attaches directly to physical NIC drivers — it cannot reliably attach to bridge or VLAN virtual interfaces. OPNsense Issue #8949 (closed NOT_PLANNED) confirms bridge0 IPS is unsupported. The correct strategy is to enable IPS on **physical parent interfaces only**.

### IPS Coverage Map

| Interface | Driver | Suricata IPS | Covers | Notes |
|-----------|--------|-------------|--------|-------|
| igb0 | igb | **YES** | VLAN 10 (Home Assistant) | Native netmap |
| igb1 | igb | **YES** | VLANs 20, 30, 40, 50 (all trunk traffic) | Native netmap, enable promiscuous mode |
| ix0 (X540) | ix | **NO** | — | Confirmed broken: memory alloc failures, network freezes (#7151, #7405) |
| ix0 (X710) | ixl | **YES** (after swap) | Proxmox → bridge0 ingress | Native netmap confirmed on ixl |
| bridge0 | — | **NEVER** | — | Emulated netmap, drops traffic (#8949) |
| igb1.20/.30/.40/.50 | — | **NEVER** | — | Virtual VLAN interfaces = emulated netmap, slow |

**Coverage gap (current):** L2-local traffic on bridge0 between Proxmox (ix0) and Flint VLAN 50 (igb1.50) that stays within the bridge is not inspected. Routed traffic (internet, inter-VLAN) traverses igb1 and IS inspected. Gap closes when X710 replaces X540.

### Phase A — Pre-requisites (before enabling anything)

- [ ] **A1.** Interfaces > Settings — disable ALL hardware offloading:
  - [ ] Hardware CRC: OFF
  - [ ] Hardware TSO: OFF
  - [ ] Hardware LRO: OFF
  - [ ] VLAN Hardware Filtering: OFF
  - **REBOOT after changing these.** Offloads interfere with netmap packet capture.
  - **Pass:** After reboot, `ifconfig igb1 | grep options` shows no `RXCSUM`, `TXCSUM`, `TSO4`, `TSO6`, `LRO`, `VLAN_HWFILTER`
  - **Fail:** If offloads persist, check System > Settings > Tunables for overrides

- [ ] **A2.** System > Settings > Tunables — verify:
  - `net.link.bridge.pfil_member=0` (already set for bridge0)
  - `net.link.bridge.pfil_bridge=1` (already set for bridge0)
  - `dev.netmap.admode` — leave at default (do NOT force emulation)
  - **Pass:** `sysctl dev.netmap.admode` returns default value
  - **Fail:** If set to 2, remove the override

- [ ] **A3.** Verify netmap is loaded:
  - SSH to OPNsense: `kldstat | grep netmap`
  - **Pass:** Shows `netmap.ko` loaded
  - **Fail:** `kldload netmap` and investigate why it's not auto-loaded

- [ ] **A4.** Verify igb driver netmap capability:
  - `sysctl dev.igb` — confirm queues exist
  - `ifconfig igb1` — confirm interface is UP with VLANs
  - **Pass:** Interface is up, VLANs are passing traffic normally

- [ ] **A5.** Take OPNsense config backup:
  - System > Configuration > Backups > Download
  - **This is your rollback point.** If Suricata breaks traffic, restore this backup.

### Phase B — Enable on igb1 (VLANs 20/30/40/50) — IDS First

- [ ] **B1.** Services > Intrusion Detection > Administration
  - Enabled: ✓
  - IPS mode: OFF (start as IDS — alert only, no blocking)
  - Promiscuous mode: ✓ (required for VLAN trunk inspection)
  - Pattern matcher: Hyperscan
  - Interfaces: select **igb1** only (the parent, NOT individual VLANs)
  - Home networks: `10.0.20.0/24,10.0.30.0/24,10.0.40.0/24,10.0.50.0/24`
  - **Pass:** Settings save without error
  - **Fail:** If igb1 not listed, check Interfaces > Assignments

- [ ] **B2.** Services > Intrusion Detection > Administration > Download
  - Enable rulesets:
    - ET Open (free, comprehensive baseline)
    - Abuse.ch SSL Blacklist
    - Abuse.ch URLhaus
  - Click "Download & Update Rules"
  - **Pass:** Rules download completes, rule count > 30,000
  - **Fail:** Check DNS resolution and internet access from OPNsense

- [ ] **B3.** Rule categories to enable (Services > Intrusion Detection > Rules):
  - **Enable all ET Open categories initially** — tune down later
  - Priority categories for home network:
    - `emerging-malware` — malware C2, droppers
    - `emerging-trojan` — trojans, RATs
    - `emerging-exploit` — exploitation attempts
    - `emerging-scan` — port scans, recon
    - `emerging-dos` — DoS patterns
    - `emerging-web_server` — if running any web services
    - `emerging-dns` — DNS abuse
    - `emerging-policy` — policy violations (P2P, TOR, etc.)
  - Categories to consider disabling if noisy:
    - `emerging-games` — generates alerts for normal gaming (Kids VLAN)
    - `emerging-chat` — chat protocol detection (may be noisy)
    - `emerging-info` — informational, high volume
  - **Pass:** Categories selected, Apply clicked without error

- [ ] **B4.** Apply and verify IDS mode:
  - Click Apply
  - SSH: `pgrep suricata` — confirm running
  - SSH: `sockstat | grep suricata` — confirm bound to igb1
  - Monitor: Services > Intrusion Detection > Log File
  - **Pass:** Suricata running, alerts appearing in log, NO traffic disruption
  - **Fail:** If traffic drops, immediately disable Suricata (uncheck Enabled, Apply)
  - **Wait 48 hours in IDS mode** before proceeding to IPS

- [ ] **B5.** Performance baseline (while in IDS mode):
  - From a Personal VLAN device: run speed test, note throughput
  - SSH: `top -b | grep suricata` — note CPU usage
  - Compare to pre-Suricata baseline
  - **Pass:** Throughput within 10% of baseline, CPU < 60%
  - **Fail:** If significant degradation, check rule count and consider disabling noisy categories

- [ ] **B6.** Review alerts and build suppression list (48hr window):
  - Services > Intrusion Detection > Alerts
  - Identify false positives (normal traffic flagged)
  - For each false positive: click the ✕ to create a suppression entry
  - Common home network false positives:
    - DNS queries to public resolvers (if AdGuard upstream uses them)
    - mDNS/SSDP cast traffic
    - Game server connections
    - Smart TV telemetry
  - **Pass:** False positive rate manageable (< 20 per hour)

- [ ] **B7.** Switch to IPS mode (inline blocking):
  - Services > Intrusion Detection > Administration
  - IPS mode: ON
  - Apply
  - **Immediately test:**
    - Personal device: browse internet, run speed test
    - Kids device: browse, run a game
    - IoT: verify cameras/NVR still connect
  - **Pass:** All VLANs functional, alerts still logging, some blocks appearing
  - **Fail:** Disable IPS mode (set back to IDS), review what was blocked in Alerts tab
  - **Rollback:** If catastrophic, uncheck Enabled entirely

### Phase C — Enable on igb0 (VLAN 10 / Home Assistant)

- [ ] **C1.** Add igb0 to Suricata interfaces:
  - Services > Intrusion Detection > Administration
  - Interfaces: add **igb0** alongside igb1
  - Add to Home networks: `10.0.10.0/24`
  - Apply
  - **Pass:** Suricata restarts, both interfaces listed in `sockstat | grep suricata`

- [ ] **C2.** Verify HA connectivity:
  - Access HA dashboard from Personal VLAN
  - Confirm HA → IoT device control works
  - Confirm HA integrations (internet) work
  - **Pass:** All HA functions operational
  - **Fail:** Remove igb0 from Suricata interfaces, investigate alerts

### Phase D — Future: Enable on ix0 after X710 Swap

**Do not start Phase D until X540 is physically replaced with X710.**

- [ ] **D1.** After physical NIC swap, verify ixl driver loads:
  - SSH: `dmesg | grep ixl` — confirm X710 detected
  - SSH: `ifconfig ix0` — confirm interface UP
  - SSH: `sysctl dev.ixl.0` — confirm driver parameters
  - **Pass:** ixl driver loaded, ix0 is UP, bridge0 still works
  - **Fail:** Check PCIe slot, BIOS settings, FreeBSD HCL

- [ ] **D2.** Verify netmap capability on ixl:
  - SSH: `dmesg | grep "netmap queues"` — should show TX/RX queue counts for ixl
  - **Pass:** Shows `netmap queues/slots: TX 8/1024, RX 8/1024` (or similar)
  - **Fail:** Verify OPNsense stock ixl driver (not Intel custom driver)

- [ ] **D3.** Verify bridge0 still functional:
  - Ping 10.0.50.10 (Proxmox) from OPNsense
  - Ping 10.0.50.1 from Proxmox
  - Verify Proxmox UI accessible at 10.0.50.10:8006
  - **Pass:** Bridge traffic flows normally
  - **Fail:** Check `ifconfig bridge0`, verify ix0 is still a member

- [ ] **D4.** Verify hw.ixl.enable_head_writeback is disabled:
  - SSH: `sysctl hw.ixl.enable_head_writeback`
  - **Pass:** Returns 0 (OPNsense default)
  - **Fail:** Add tunable: System > Settings > Tunables > `hw.ixl.enable_head_writeback=0`

- [ ] **D5.** Add ix0 to Suricata interfaces:
  - Services > Intrusion Detection > Administration
  - Interfaces: add **ix0** alongside igb0 and igb1
  - Start in IDS mode first (disable IPS temporarily)
  - Apply
  - **Pass:** Suricata restarts, three interfaces in `sockstat | grep suricata`
  - **Fail:** If traffic drops on bridge0, immediately remove ix0 from Suricata

- [ ] **D6.** Validate bridge0 traffic with Suricata on ix0:
  - Ping flood test: `ping -f -c 1000 10.0.50.10` from OPNsense
  - Sustained transfer: scp a large file to/from Proxmox
  - Monitor: `top -b | grep suricata` — CPU check
  - **Pass:** No packet loss, bridge stable, CPU acceptable
  - **Fail:** Remove ix0 from Suricata, file OPNsense bug report with ixl/netmap details

- [ ] **D7.** Re-enable IPS mode with ix0 included:
  - Switch IPS mode back ON
  - Test all three paths: internet via igb1, HA via igb0, Proxmox via ix0
  - **Pass:** Full IPS coverage on all physical ingress points
  - **Fail:** Fall back to IDS on ix0 only, keep IPS on igb0+igb1

### Phase E — Rule Tuning and Maintenance

- [ ] **E1.** Schedule automatic rule updates:
  - Services > Intrusion Detection > Administration > Schedule
  - Set to daily update (recommended: 03:00 local time)
  - Enable "Update and reload on schedule"

- [ ] **E2.** Suppression list management:
  - Services > Intrusion Detection > Administration > User defined tab
  - Export suppression list periodically (backup)
  - Review and prune monthly

- [ ] **E3.** Splunk syslog integration:
  - System > Settings > Logging > Targets
  - Add target: 10.0.50.208, UDP/514 (or TCP/514)
  - Transport: UDP (or TCP for reliability)
  - Applications: select `suricata`
  - Also enable: firewall filter logs
  - For EVE JSON output (richer data):
    - Services > Intrusion Detection > Administration
    - Enable "Eve syslog output"
  - **Pass:** Splunk receiving events from OPNsense
  - **Fail:** Check network path (VLAN 50 rules must allow Suricata host → 10.0.50.208:514)

- [ ] **E4.** Log retention policy:
  - Local Suricata logs: 7 days (Services > Intrusion Detection > Administration)
  - Splunk retention: set based on license/storage
  - During commissioning: keep verbose logging 30 days minimum
  - After stable: reduce to alerts-only forwarding

- [ ] **E5.** Monthly review cadence:
  - Review top 10 triggered rules — are they real threats or noise?
  - Check Suricata CPU/memory usage trend
  - Update suppression list
  - Review any new ET Open rule categories
  - Test IPS bypass: temporarily disable IPS, run EICAR test download, re-enable, confirm detection
