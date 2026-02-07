#!/bin/bash
# EthShare helper - runs privileged network operations via sudo
set -euo pipefail

WIFI_IFACE="wlp7s0"
ETH_IFACE="eno1"
ETH_IP="192.168.8.10"
DHCP_RANGE="192.168.8.100,192.168.8.200,24h"
KVM_IP="192.168.8.158"
PID_FILE="/tmp/ethshare-dnsmasq.pid"
STATE_FILE="/tmp/ethshare.active"
NM_PROFILE_STATIC="Profile 1"
NM_PROFILE_DHCP="Profile 2"

# Port forwards: local_port:kvm_port
PORT_FORWARDS="2222:22"

enable_sharing() {
    # Switch eno1 to static IP profile for sharing
    nmcli con mod "$NM_PROFILE_STATIC" autoconnect yes 2>/dev/null || true
    nmcli con mod "$NM_PROFILE_DHCP" autoconnect no 2>/dev/null || true
    nmcli con up "$NM_PROFILE_STATIC" 2>/dev/null || true

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # NAT masquerade on WiFi interface (idempotent)
    iptables -t nat -C POSTROUTING -o "$WIFI_IFACE" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$WIFI_IFACE" -j MASQUERADE

    # Forward rules (idempotent)
    iptables -C FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -j ACCEPT

    iptables -C FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Start dnsmasq if not already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "dnsmasq already running"
    else
        rm -f "$PID_FILE"
        dnsmasq \
            --interface="$ETH_IFACE" \
            --bind-interfaces \
            --dhcp-range="$DHCP_RANGE" \
            --dhcp-option=3,"$ETH_IP" \
            --dhcp-option=6,"$ETH_IP" \
            --listen-address="$ETH_IP" \
            --pid-file="$PID_FILE" \
            --log-facility=/var/log/ethshare-dnsmasq.log \
            --server=127.0.0.53 \
            --no-resolv
    fi

    # Port forwarding from WiFi to KVM (idempotent)
    for mapping in $PORT_FORWARDS; do
        local_port="${mapping%%:*}"
        kvm_port="${mapping##*:}"
        iptables -t nat -C PREROUTING -i "$WIFI_IFACE" -p tcp --dport "$local_port" -j DNAT --to "$KVM_IP:$kvm_port" 2>/dev/null || \
            iptables -t nat -A PREROUTING -i "$WIFI_IFACE" -p tcp --dport "$local_port" -j DNAT --to "$KVM_IP:$kvm_port"
    done

    touch "$STATE_FILE"
    echo "Sharing enabled"
}

disable_sharing() {
    # Disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward

    # Remove port forwards
    for mapping in $PORT_FORWARDS; do
        local_port="${mapping%%:*}"
        kvm_port="${mapping##*:}"
        iptables -t nat -D PREROUTING -i "$WIFI_IFACE" -p tcp --dport "$local_port" -j DNAT --to "$KVM_IP:$kvm_port" 2>/dev/null || true
    done

    # Remove iptables rules (ignore errors if already gone)
    iptables -t nat -D POSTROUTING -o "$WIFI_IFACE" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

    # Stop dnsmasq
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi

    # Disconnect eno1 and set DHCP as the auto-connect profile
    # NM will auto-activate Profile 2 (DHCP) when plugged into a real network
    nmcli con mod "$NM_PROFILE_STATIC" autoconnect no 2>/dev/null || true
    nmcli con mod "$NM_PROFILE_DHCP" autoconnect yes 2>/dev/null || true
    nmcli dev disconnect "$ETH_IFACE" 2>/dev/null || true

    rm -f "$STATE_FILE"
    echo "Sharing disabled"
}

get_status() {
    local fwd
    fwd=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$fwd" = "1" ] && \
       iptables -t nat -C POSTROUTING -o "$WIFI_IFACE" -j MASQUERADE 2>/dev/null && \
       [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "active"
    else
        echo "inactive"
    fi
}

case "${1:-}" in
    enable)  enable_sharing ;;
    disable) disable_sharing ;;
    status)  get_status ;;
    *)
        echo "Usage: $0 {enable|disable|status}" >&2
        exit 1
        ;;
esac
