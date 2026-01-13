# ASRock X870 Taichi Creator Network Setup Guide

This guide addresses network interface configuration for the ASRock X870 Taichi Creator motherboard in Proxmox VE, specifically dealing with the RTL8126 5GbE and Aquantia AQC113 10GbE NICs.

## Network Hardware Overview

The X870 Taichi Creator features dual ethernet:

| NIC | Speed | Chip | Linux Driver | Kernel Status |
|-----|-------|------|--------------|---------------|
| 10GbE | 100/1000/2500/5000/10000 Mbps | Marvell/Aquantia AQC113CS | `atlantic` | In-tree since 5.8 |
| 5GbE | 10/100/1000/2500/5000 Mbps | Realtek RTL8126 | `r8126` | **Out-of-tree** (not in kernel until ~6.14+) |
| WiFi 7 | 802.11be 2x2 + BT 5.4 | MediaTek MT7925 (likely) | `mt7925e` | In-tree since 6.5 |

## The Problem

When installing or upgrading Proxmox VE on the X870 Taichi Creator:

1. **RTL8126 5GbE**: Not detected during installation - requires out-of-tree `r8126` driver
2. **AQC113 10GbE**: Should work with `atlantic` driver in kernel 5.8+, but may have stability issues
3. **WiFi 7**: Typically requires kernel 6.5+ for MediaTek WiFi 7 modules

### Proxmox Kernel Versions

| Proxmox Version | Default Kernel | RTL8126 Support | AQC113 Support |
|-----------------|----------------|-----------------|----------------|
| PVE 8.x | 6.5 / 6.8 | No (needs DKMS) | Yes (atlantic) |
| PVE 9.0 | 6.14.8 | No (needs DKMS) | Yes (atlantic) |
| PVE 9.1 | 6.17.2 | Likely yes (check) | Yes (atlantic) |

---

## Solution 1: Use AQC113 10GbE During Installation

The 10GbE port (Aquantia AQC113) uses the `atlantic` driver, which is included in the Linux kernel. This port should work out-of-the-box on Proxmox 8.x and 9.x.

### Steps

1. **Connect ethernet to the 10GbE port** (not the 5GbE) during Proxmox installation
2. Verify the interface is detected:
   ```bash
   ip link show
   lspci | grep -i aquantia
   dmesg | grep atlantic
   ```
3. Proceed with installation using the 10GbE interface

### Expected output:
```
atlantic 0000:0c:00.0: Firmware version: x.x.x
atlantic 0000:0c:00.0 enp12s0: renamed from eth0
```

---

## Solution 2: Install RTL8126 DKMS Driver

After Proxmox is installed (using 10GbE), install the out-of-tree `r8126` driver for the 5GbE port.

### Method A: DKMS Package (Recommended)

Using the community-maintained [realtek-r8126-dkms](https://github.com/awesometic/realtek-r8126-dkms):

```bash
# Install build dependencies
apt update
apt install -y dkms build-essential linux-headers-$(uname -r)

# Download latest release
wget https://github.com/awesometic/realtek-r8126-dkms/releases/download/10.016.00/realtek-r8126-dkms_10.016.00_amd64.deb

# Install
dpkg -i realtek-r8126-dkms_10.016.00_amd64.deb

# Blacklist r8169 to prevent conflicts
cat > /etc/modprobe.d/blacklist-r8169.conf << 'EOF'
# Prevent r8169 from loading for RTL8126
# r8126 driver provides better support for 5GbE
blacklist r8169
EOF

# Update initramfs and reboot
update-initramfs -u
reboot
```

### Method B: Build from Source

```bash
# Install dependencies
apt update
apt install -y git build-essential linux-headers-$(uname -r)

# Clone and build
git clone https://github.com/awesometic/realtek-r8126-dkms.git
cd realtek-r8126-dkms
./dkms-install.sh

# Blacklist r8169
cat > /etc/modprobe.d/blacklist-r8169.conf << 'EOF'
blacklist r8169
EOF

update-initramfs -u
reboot
```

### Verify RTL8126 is Working

```bash
# Check module is loaded
lsmod | grep r8126

# Check interface exists
ip link show | grep -E "enp[0-9]+s0"

# Check dmesg for r8126
dmesg | grep r8126
```

---

## Solution 3: Upgrade to Proxmox 9.1 (Kernel 6.17)

Proxmox VE 9.1 ships with kernel 6.17.2, which may include native RTL8126 support. Upgrading eliminates the need for DKMS drivers.

### Upgrade Path from Proxmox 8.x

```bash
# Backup first!
# Then follow official upgrade guide:
# https://pve.proxmox.com/wiki/Upgrade_from_8_to_9

# Update current system
apt update && apt dist-upgrade

# Change repositories
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-enterprise.list

# Update to Proxmox 9
apt update
apt dist-upgrade

# Reboot
reboot
```

### Switch to 6.17 Kernel (if on 9.0)

```bash
# Install 6.17 kernel
apt update
apt install proxmox-kernel-6.17

# Set as default
proxmox-boot-tool kernel pin 6.17.2-1-pve

# Reboot
reboot
```

---

## Network Configuration

### Recommended Configuration

Use the 10GbE (AQC113) as the primary/management interface and 5GbE (RTL8126) for specific purposes like VM traffic or storage.

Example `/etc/network/interfaces`:

```
auto lo
iface lo inet loopback

# 10GbE - Management and storage (Aquantia AQC113)
auto enp12s0
iface enp12s0 inet manual

# 5GbE - VM bridge (Realtek RTL8126)
auto enp13s0
iface enp13s0 inet manual

# Management bridge (10GbE)
auto vmbr0
iface vmbr0 inet static
    address 10.0.30.10/24
    gateway 10.0.30.1
    bridge-ports enp12s0
    bridge-stp off
    bridge-fd 0

# VM traffic bridge (5GbE)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports enp13s0
    bridge-stp off
    bridge-fd 0
```

### Interface Naming

The actual interface names depend on PCIe slot position. Find them with:

```bash
# List all network interfaces
ip link show

# Show PCIe devices
lspci | grep -i ethernet

# Show driver binding
ls -la /sys/class/net/*/device/driver
```

---

## Known Issues

### AQC113 Stability Issues

Some users report PCIe AER errors with AQC113 under certain kernel versions:

```
atlantic 0000:0c:00.0: PCIe Bus Error: severity=Correctable
```

**Mitigation:**
```bash
# Add kernel parameter to disable AER reporting
# Edit /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT="quiet pci=noaer"

# Update grub
update-grub
proxmox-boot-tool refresh
reboot
```

### RTL8126 / r8169 Conflict

If the 5GbE interface is detected but not working properly:

```bash
# Check which driver is loaded
ethtool -i enp13s0

# If r8169, blacklist it
echo "blacklist r8169" >> /etc/modprobe.d/blacklist-r8169.conf
update-initramfs -u
reboot
```

### WiFi 7 (if needed)

The X870 Taichi Creator includes WiFi 7 (802.11be). If you need wireless:

```bash
# Check if detected
lspci | grep -i wireless
dmesg | grep mt79

# WiFi 7 requires kernel 6.5+ with mt7925 driver
# Should work on Proxmox 9.x out-of-box
```

Note: WiFi is typically not recommended for server/hypervisor use.

---

## GPU Passthrough Considerations

When configuring GPU passthrough on X870 Taichi Creator with these NICs:

1. **IOMMU groups**: Verify NICs are in separate IOMMU groups from GPUs
   ```bash
   for d in /sys/kernel/iommu_groups/*/devices/*; do
     n="${d#*/iommu_groups/}"; n="${n%%/*}"
     printf 'IOMMU Group %s: ' "$n"
     lspci -nns "${d##*/}"
   done | sort -V
   ```

2. **ACS override**: May be needed if devices share IOMMU groups
   ```bash
   # Add to kernel cmdline if needed
   pcie_acs_override=downstream,multifunction
   ```

---

## Verification Checklist

After setup, verify everything is working:

```bash
# 1. Check both NICs are present
ip link show

# 2. Verify drivers
lsmod | grep -E "atlantic|r8126"

# 3. Test 10GbE connectivity
ping -I enp12s0 <gateway>

# 4. Test 5GbE connectivity (if driver installed)
ping -I enp13s0 <gateway>

# 5. Check link speeds
ethtool enp12s0 | grep Speed
ethtool enp13s0 | grep Speed

# 6. Check for errors
dmesg | grep -iE "atlantic|r8126|error"
```

---

## References

- [Proxmox Forum: RTL8126 NIC/Driver Issues](https://forum.proxmox.com/threads/problem-with-rtl8126-nic-driver-dont-know-how-to-get-it-working.150023/)
- [GitHub: realtek-r8126-dkms](https://github.com/awesometic/realtek-r8126-dkms)
- [GitHub: Aquantia AQtion Driver](https://github.com/Aquantia/AQtion)
- [Linux Kernel: Atlantic Driver Docs](https://docs.kernel.org/networking/device_drivers/ethernet/aquantia/atlantic.html)
- [Proxmox: Upgrade from 8 to 9](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9)
- [ASRock X870 Taichi Creator](https://www.asrock.com/mb/AMD/X870%20Taichi%20Creator/index.asp)
