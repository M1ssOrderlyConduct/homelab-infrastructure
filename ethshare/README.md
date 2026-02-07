# EthShare

System tray app to toggle WiFi-to-Ethernet internet sharing with DHCP, DNS, NAT, and port forwarding to a KVM guest.

## What it does

- Shares the WiFi connection (`wlp7s0`) through the Ethernet port (`eno1`) to a KVM at `192.168.8.158`
- Runs a DHCP/DNS server (dnsmasq) on the Ethernet subnet `192.168.8.0/24`
- Applies iptables MASQUERADE so sharing survives WiFi network/VLAN changes
- Port-forwards `<host>:2222` → `KVM:22` for SSH access from other WiFi machines
- Switches NetworkManager between a static profile (sharing) and DHCP profile (normal use)

## Variants

| Directory | Desktop | Dependencies |
|-----------|---------|-------------|
| `gnome/`  | GNOME (GTK3 + AyatanaAppIndicator3) | `gir1.2-ayatanaappindicator3-0.1` |
| `kde/`    | KDE Plasma (PyQt5 + QSystemTrayIcon) | `python3-pyqt5` |

## Files

- `helper.sh` - Privileged bash script (runs via sudo) that manages iptables, ip_forward, dnsmasq, NM profiles
- `gnome/ethshare` - GNOME system tray app (Python3)
- `kde/ethshare` - KDE system tray app (Python3)
- `ethshare.desktop` - Desktop entry (app drawer + autostart)
- `ethshare-sudoers` - sudoers.d drop-in for passwordless helper execution

## Install (per-user, GNOME)

```bash
cp helper.sh ~/.local/share/ethshare/helper.sh
cp gnome/ethshare ~/.local/bin/ethshare
chmod +x ~/.local/bin/ethshare ~/.local/share/ethshare/helper.sh
sudo cp ethshare-sudoers /etc/sudoers.d/ethshare
# Edit sudoers to use per-user path: /home/$USER/.local/share/ethshare/helper.sh
cp ethshare.desktop ~/.local/share/applications/
cp ethshare.desktop ~/.config/autostart/
# Edit Exec= paths in desktop files to ~/.local/bin/ethshare
```

## Install (system-wide, KDE/ISO)

```bash
sudo cp helper.sh /usr/local/share/ethshare/helper.sh
sudo cp kde/ethshare /usr/local/bin/ethshare
sudo chmod +x /usr/local/bin/ethshare /usr/local/share/ethshare/helper.sh
sudo cp ethshare-sudoers /etc/sudoers.d/ethshare
sudo cp ethshare.desktop /usr/share/applications/
sudo cp ethshare.desktop /etc/xdg/autostart/
```

## Configuration

Edit variables at the top of `helper.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `WIFI_IFACE` | `wlp7s0` | WiFi interface |
| `ETH_IFACE` | `eno1` | Ethernet interface |
| `ETH_IP` | `192.168.8.10` | Static IP for sharing mode |
| `DHCP_RANGE` | `192.168.8.100,192.168.8.200,24h` | DHCP range for clients |
| `KVM_IP` | `192.168.8.158` | KVM guest IP |
| `PORT_FORWARDS` | `2222:22` | `local_port:kvm_port` mappings |
| `NM_PROFILE_STATIC` | `Profile 1` | NM profile for static/sharing mode |
| `NM_PROFILE_DHCP` | `Profile 2` | NM profile for normal DHCP mode |

## Access KVM from WiFi

With sharing enabled, from any machine on the WiFi network:

```bash
# Port forward (direct)
ssh -p 2222 user@<host-wifi-ip>

# Jump host (transparent)
ssh -J user@<host-wifi-ip> user@192.168.8.158

# Static route (router-level, optional)
# Add on router: destination 192.168.8.0/24, gateway <host-wifi-ip>
# Then: ssh user@192.168.8.158
```
