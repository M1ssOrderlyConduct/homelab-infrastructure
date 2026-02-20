Deep Research Review of network-architecture-v4.md
Executive summary
Prioritized action list

Critical: Validate and correct OpenWrt interface naming/DSA assumptions before deploying (the v4 scripts VLAN-tag eth0.*; Flint 2 commonly uses eth1 as WAN/uplink in OpenWrt DSA setups). A wrong uplink device name will break the trunk entirely and strand you off-network. (Evidence: community DSA configs for GL‑MT6000 show WAN on eth1 and LAN ports lan1–lan5.) 
Critical: Decide DNS placement with reliability in mind: AdGuardHome on Flint is operationally convenient but becomes a single point of failure for all VLANs’ DNS. If you keep it on Flint, add an allowed fallback DNS path to the per‑VLAN gateway (Unbound on OPNsense) and confirm rules support that. (Tailscale + DNS and “bypass prevention” goals increase the cost of DNS outages.) 
Critical: Complete the VLAN50 bridge implementation as written: one L3 IP (10.0.50.1/24) on bridge0 only, member interfaces unnumbered, and set the bridge filter tunables exactly as specified. This avoids the “two interfaces in the same /24” ambiguity and matches OPNsense’s own bridge guidance. 
High: Confirm IPS/Suricata placement with VLAN/bridge realities: OPNsense IPS guidance emphasizes interface selection and notes netmap constraints, and when VLANs exist it commonly advises protecting the parent rather than each VLAN. Validate that your intended “full Suricata inspection” actually covers the traffic you care about and does not interfere with bridge/VLAN behavior. 
High: Fix doc inconsistencies and lock in “source of truth”: v4 says “802.11r disabled initially,” yet the SSID map text still claims 11r enabled while the scripts set it disabled. Resolve this so troubleshooting doesn’t become ambiguous. (See network-architecture-v4.md lines 12–13 vs 185–187 and the OpenWrt UCI wifi-iface lines setting ieee80211r='0'.)
High: Tailscale subnet-router vs WireGuard: keep Tailscale if you want “it works from anywhere” across CGNAT with minimal routing pain; use WireGuard if you want no third-party control-plane dependency and tighter, simpler mental model—but accept more NAT/DDNS work. Implement strict “VPN→MGMT_TARGETS only” rules either way. 
High: Validate Dahua NVR ports against manual sources and narrow to the minimum you actually use. Defaults widely documented: TCP 37777, UDP 37778, HTTP 80, HTTPS 443, RTSP 554. Start with the smallest set that supports your workflows (UI + streaming + management tool) and tighten based on observed logs. 
Bottom line

The bridge0 VLAN50 and storage /30 decisions are directionally correct for security + reliability + performance (and explicitly called out in the v4 change log). The biggest practical risk is OpenWrt DSA/uplink device naming and the operational fragility of DNS anchored to an AP plus VLAN trunking over WDS.
Connector coverage and inputs
Enabled connector inventory (Notion)

Notion connector exposes exactly these two read-only tools:
Notion_search
Notion_fetch
Notion workspace check

Workspace searches for network architecture and OPNsense returned no results (no additional internal docs found via Notion).
Local inputs reviewed

network-architecture-v4.md (local sandbox file) was read directly and used as the primary design artifact.
Prior conversation requirements were incorporated (priority ordering: segmentation → uptime → throughput/latency → operational overhead → troubleshooting; admin devices pinned; Dahua NVR model; preference for VPN management; WDS required where cabling isn’t possible).
L2/L3 and routing design review
Bridge0 for VLAN 50
What v4 specifies

v4 formalizes the bridge-only L3 approach: create bridge0 from igb1.50 + ix0, assign 10.0.50.1/24 to INFRA_BR (bridge0) only, leave bridge members with no IPs, and evaluate rules on the bridge interface only (net.link.bridge.pfil_bridge=1 and net.link.bridge.pfil_member=0). (See network-architecture-v4.md lines 109–119.)
This aligns with OPNsense’s own bridging how-to, which explicitly instructs setting net.link.bridge.pfil_bridge=1 and net.link.bridge.pfil_member=0 to make filtering occur on the bridge instead of members. 
Benefits

Eliminates the common failure mode of “two interfaces in the same /24,” which causes intermittent ARP/route selection confusion.
Keeps VLAN50 as one coherent L2 domain spanning the 1Gb trunk side and the 10Gb Proxmox side, simplifying east/west infra traffic and management reachability.
Operationally consistent: “all VLAN50 policy lives in one place” (INFRA_BR).
Risks

Bridging can hide/alter where packet filtering and inspection occurs if tunables are wrong or rules are mistakenly left on member interfaces.
IPS/Suricata inspection coverage can be unintuitive across bridges/VLANs. OPNsense’s IPS docs stress correct interface choice and note that in IPS mode interfaces must support netmap; when VLANs are involved, enabling on the parent is often recommended. 
Bridge MTU becomes the minimum MTU among members (general Linux bridging principle; same concept applies broadly). If you ever introduce nonstandard MTUs/jumbo, bridge behavior must be validated.
Concrete configuration checks (OPNsense UI + CLI)

UI:
Interfaces → Other Types → Bridge: confirm bridge members only igb1.50 and ix0
Interfaces → Assignments: ensure only INFRA_BR has 10.0.50.1/24
System → Settings → Tunables: confirm exactly:
net.link.bridge.pfil_bridge = 1
net.link.bridge.pfil_member = 0 
CLI (OPNsense shell):
Confirm bridge membership:
sh
Copy
ifconfig bridge0
Confirm no IP on members:
sh
Copy
ifconfig igb1.50
ifconfig ix0
Confirm tunables:
sh
Copy
sysctl net.link.bridge.pfil_bridge net.link.bridge.pfil_member
Prioritized remediation

Critical: Ensure no duplicated 10.0.50.1/24 exists anywhere except the bridge interface.
High: Remove/disable any VLAN50 rules accidentally attached to member interfaces.
Medium: Decide whether VLAN50 should allow unrestricted intra-VLAN traffic long-term; right now v4 allows NET_INFRA → NET_INFRA any (broad) for convenience. If segmentation priority is #1, you may later tighten by host/service.
Storage /30 (10.0.60.0/30) and asymmetric routing
What v4 specifies

Storage is moved to a dedicated point-to-point subnet 10.0.60.0/30 with no gateway on either side; Proxmox uses 10.0.60.1/30 and TrueNAS 10.0.60.2/30, and mounts should target 10.0.60.2. (See network-architecture-v4.md lines 30–34 and Proxmox section later.)
Benefits

Cleanly avoids asymmetric routing and “two NICs in the same prefix” problems that frequently occur when you keep storage and management in the same /24.
Simplifies troubleshooting: if storage is slow, you only look at one link/subnet.
Residual risks

If TrueNAS/Proxmox accidentally set a default gateway on the storage NIC, you reintroduce path ambiguity.
If Proxmox mounts still point at 10.0.50.x, storage traffic will traverse the bridge/firewall path and you’ll lose the isolation/performance benefits.
If you later add VLAN-aware VM networks, ensure VMs cannot accidentally reach the storage /30 unless intended.
Concrete configuration checks

Proxmox:
Confirm only one default route (via VLAN50 mgmt):
sh
Copy
ip route show
Confirm storage interface has no gateway:
sh
Copy
ip addr show
ip route show | grep 10.0.60.0/30
TrueNAS:
Verify storage NIC has no default gateway (TrueNAS UI: Network → Interfaces; and default route under Network → Global Configuration).
Verify services bound/listening appropriately (NFS/iSCSI bound to correct interfaces if you choose to restrict).
Prioritized remediation

Critical: No gateway on 10.0.60.1/30 or 10.0.60.2/30.
High: Hardcode mounts/portals to 10.0.60.2 and remove any mounts pointing to 10.0.50.95.
Medium: If you want to strictly prevent accidental use, firewall on TrueNAS/Proxmox host level (not OPNsense) since this link bypasses OPNsense by design.
Remote management and control plane
Tailscale subnet routing vs WireGuard on OPNsense
Your stated goal is “touch all VLANs without being insecure,” and your preferred operational model is VPN-first management.

Key Tailscale facts relevant to your design
Tailscale’s subnet router feature advertises routes (e.g., 10.0.20.0/24) and clients use those routes once approved in the admin console. 
Tailscale device IPs come from 100.64.0.0/10 (CGNAT), aligned with RFC 6598 shared address space. 
By default, subnet routers perform SNAT (masquerade); disabling SNAT is documented as a Linux-only knob, and if SNAT is disabled you must add return routes for Tailscale’s 100.64.0.0/10 range. 
Table: Tailscale subnet routing vs WireGuard on OPNsense
Dimension	Tailscale subnet routing on OPNsense	WireGuard on OPNsense
Cryptography	WireGuard-based transport (same class of primitives as WG)	WireGuard (native protocol)
Control plane dependency	Requires Tailscale coordination/control plane for auth/ACL/routing advertisements	No external control plane required; you manage keys and endpoints
NAT/CGNAT friendliness	Typically “just works” through NAT/CGNAT due to outbound connections + DERP fallback (operationally strong for roaming admin devices)	If OPNsense is behind CGNAT or strict NAT you may need port forwarding / DDNS / NAT traversal workarounds
Routing model	Advertise and approve subnet routes; overlapping routes have caveats (e.g., route preference if router offline). 
Explicit AllowedIPs drive routes; conceptually simpler but more manual
Source IP visibility to LAN targets	Often SNATed (targets may see traffic as coming from the subnet router’s LAN IP, depending on platform behavior); OPNsense can still enforce on VPN interface	Typically preserves individual VPN client IPs end-to-end
Policy enforcement	Strong if you keep “VPN interface → MGMT_TARGETS only” rules (as v4 intends) and also use Tailscale ACLs	Strong if you keep WireGuard interface rules tight; ACLs must be done in OPNsense (or endpoint security)
Operational overhead	Lower day‑to‑day once installed; diagnostics can feel opaque until you learn Tailscale tooling	More deterministic; fewer moving parts; higher initial setup burden (peers, keys, endpoint reachability)
Recommended fit for your priorities	Best if uptime + “manage from anywhere” matters and you accept an external control plane	Best if “minimize dependencies” and “keep everything local” matters more than roaming convenience

WireGuard setup in OPNsense is documented in OPNsense how-tos (instance/peer creation). 

Recommendation given your stated preference and current reality

Keep Tailscale for now (you already use it and want VPN-first), but operationalize it: treat it like a product with explicit checks and a rollback plan to WireGuard.
Maintain WireGuard as your contingency (documented) in case Tailscale integration remains “elusive” or becomes unreliable.
Minimal, auditable management access flow
mermaid
Copy
flowchart LR
  A[Admin device\n10.0.40.10-13] --> B[Tailscale or WireGuard\nVPN tunnel]
  B --> C[OPNsense VPN interface\n(policy enforced here)]
  C --> D[MGMT_TARGETS\nFlint/Marble/Proxmox/TrueNAS/NVR]
Concrete checks and steps

For Tailscale subnet routing:
Ensure advertised routes include all VLANs you want reachable (v4 lists 10/20/30/40/50).
Confirm routes are approved in the Tailscale admin console (Tailscale docs describe approval workflow). 
In OPNsense firewall rules, keep the VPN interface policy narrow (exactly what v4 intends: CGNAT_TAILSCALE → MGMT_TARGETS only).
For WireGuard:
Follow OPNsense instance + peer creation workflow (documented). 
Prioritized remediation

Critical: Verify you can reach each mgmt target via VPN from LTE (phone) before you rely on the design.
High: Add a “break-glass” local path that does not depend on DNS (bookmarked IPs; or a local admin VLAN device) in case DNS filtering interferes.
Medium: Consider syslog-ing VPN auth/access events for auditing (ties into Splunk).
Edge devices and Wi‑Fi review
OpenWrt ethernet/VLAN design (Flint: br-personal-wired + one infra port)
What v4 intends

Flint 2 LAN ports should default into Personal VLAN 40, with one dedicated infra port in VLAN 50. This is explicitly called out in the v4 change log and implemented by:
br-mgmt = VLAN50 + lan5
br-personal-wired = VLAN40 + lan1–lan4 (See network-architecture-v4.md “Flint 2” script section.)
Benefits

Prevents “accidental infra exposure” when you plug a random device into a LAN port.
Supports your stated preference: default to Personal, optional extra infra port.
Primary risk: DSA + device naming mismatch

OpenWrt’s DSA migration guidance shows that VLAN configuration often changes from older eth0.X patterns to bridge-based VLAN subinterfaces (e.g., br0.2) and explicit bridge-vlan sections. 
GL‑MT6000 OpenWrt examples show WAN commonly as eth1 and LAN ports lan1–lan5, and community guidance for VLAN tagging references creating eth1.20 for WAN tagging. 
Your v4 script tags VLANs on eth0.*. If the trunk-uplink is actually eth1 (common), VLAN traffic will not reach OPNsense, breaking all SSID/VLAN mapping.
Concrete configuration checks (run before trusting the scripts) On each OpenWrt AP after flashing, before connecting the trunk to OPNsense:

sh
Copy
ip link
cat /etc/config/network
ubus call system board
Confirm:

Which interface is the physical uplink (WAN port) carrying the trunk (likely eth1 on GL‑MT6000 per common configs). 
Whether DSA “bridge VLAN filtering” is expected for your target release (OpenWrt DSA guidance). 
Prioritized remediation

Critical: If uplink is eth1, change the script’s VLAN devices from eth0 to eth1 (e.g., eth1.50, eth1.40, etc.) and re-test.
High: Consider migrating the config to a DSA-native bridge-vlan style layout if you see instability or inconsistent behavior (OpenWrt’s DSA guidance is explicit about new patterns). 
Medium: Label the physical port reserved for VLAN50 (lan5) and document it in the diagram to reduce operator error.
SSH hardening, LuCI HTTPS, and lockout risks
What v4 intends

Remove empty-root-password behavior (v4 explicitly removed passwd -d root and instructs strong password + SSH keys).
Use Dropbear authorized_keys and optionally disable password auth (script sets PasswordAuth=off and RootPasswordAuth=off).
Keep LuCI over HTTPS with luci-ssl.
Benefits

Eliminates the largest “easy compromise” risk: passwordless root.
Keys-only SSH reduces credential brute-force exposure.
Risks

Keys-only SSH can lock you out if authorized_keys is wrong or permissions are rejected.
OpenWrt community issues show Dropbear can reject authorized_keys due to permissions/ownership constraints, causing fallback to password auth or failure. 
The OpenWrt Dropbear config options PasswordAuth and RootPasswordAuth are real documented UCI options (even if language variants of the doc were retrieved). 
HTTPS-only LuCI depends on correct package availability; OpenWrt’s LuCI SSL FAQ states opkg install luci-ssl enables HTTPS. 
Concrete checks

Confirm Dropbear is accepting keys:
sh
Copy
logread | grep -i dropbear
ls -lah /etc/dropbear/authorized_keys
Confirm LuCI SSL installed (OpenWrt FAQ). 
sh
Copy
opkg list-installed | grep luci-ssl
netstat -lntp | grep :443
Prioritized remediation

Critical: Do not disable password auth until you have verified key-auth login works from at least two admin devices.
High: Add a second SSH pubkey and keep a local console recovery plan per device (U‑Boot recovery is noted in v4).
Medium: Consider restricting LuCI to the mgmt IP only and/or firewalling LuCI access at OPNsense (preferable to any AP-side firewall since AP firewall is disabled).
Wi‑Fi settings: HE80 vs HE160, 802.11r, WDS VLAN trunking
HE80 vs HE160

OpenWrt recognizes htmode values including HE80 and HE160 (documented in LuCI’s WifiDevice API enumeration). 
Real-world driver/ACS issues around HE160 exist (example: mt76 issue reporting HE160 instability). This is relevant because Flint 2 is MediaTek/mt76 family. 
v4’s choice to force HE80 is a reasonable stability-first default when you have unknown RF/DFS conditions and a WDS backhaul dependent on link stability.
802.11r

v4’s scripts disable ieee80211r initially (good given you described it as an unknown).
However, the SSID map prose still claims “802.11r enabled” (doc inconsistency). Fixing the documentation is necessary so troubleshooting isn’t self-contradictory.
WDS VLAN over wireless

HTTP/3/QUIC note: QUIC uses UDP and HTTP/3 endpoints can be served on any UDP port; blocking UDP can force clients back to TCP-based HTTP versions. 

(This matters because your Kids policy blocks UDP/443; it is an intentional trade-off that may affect some apps.)
VLAN tagging adds 4 bytes to frames at L2. Some network vendor docs recommend planning for that overhead (frame size increases by 4 bytes for an 802.1Q tag). 
ath11k VLAN support and AP/VLAN handling has been actively worked on upstream (mailing list patches). While not identical to “VLAN over WDS,” it underscores that VLAN + Wi‑Fi datapath details are driver/firmware sensitive. 
Prioritized remediation

Critical: Validate WDS stability and VLAN tagging behavior with repeatable tests (see test section).
High: If VLAN-over-WDS proves unstable, consider fallback designs (single VLAN for backhaul + local separation; or alternative backhaul mechanisms).
Medium: Keep HE80 until you have stable metrics; only then experiment with HE160.
Policy enforcement: firewall, DNS, NVR, logging, and tests
Firewall rules: Kids UDP high-ports + DoH/DoT/QUIC blocks
What you are doing

Kids VLAN:
Block DoT (853)
Block QUIC (UDP/443)
Block known DoH endpoints on TCP/443
Allow DNS only to AdGuard (53)
Allow TCP 80/443 to internet
Allow UDP 1024–65535 to internet (gaming/voice/chat) (These appear in v4’s firewall tables.)
Protocol validation and rationale

DoT uses TCP port 853 by default: RFC 7858 explicitly states clients desiring DNS-over-TLS privacy “MUST establish a TCP connection to port 853” by default. 
DoH is standardized as DNS over HTTPS (RFC 8484). 
QUIC is UDP-based (RFC 9000) and HTTP/3 runs over QUIC; RFC 9114 explicitly notes UDP blocking can prevent QUIC connections and clients should attempt TCP-based HTTP instead. 
Benefits

Big improvement over “web-only” rules: gaming/voice is realistically supported via broad UDP high ports.
DNS policy becomes enforceable in principle (DoT blocked; QUIC blocked; known DoH blocked).
Risks

Some gaming/voice services use UDP/443 specifically; your QUIC block is a blanket UDP/443 block and may break certain apps. RFC 9114 highlights UDP blocking impacts QUIC connectivity; that’s an intended trade-off but needs validation against your household’s actual usage. 
DoH endpoint blocking via hostname alias is inherently incomplete: browsers can use nonstandard DoH endpoints, CDNs, or enterprise DoH. Expect cat-and-mouse.
If AdGuard is down, Kids DNS fails completely under this policy unless you provide a fallback DNS path.
Concrete configuration checks

Confirm rule order: blocks must precede allows; DNS allow must precede RFC1918 block if AdGuard is on a different VLAN.
Verify alias resolution for DOH_ENDPOINTS (hostname alias must resolve and refresh).
Detect bypass attempts:
OPNsense live logs: filter Kids interface for dest port 853 and dest port 443/udp and dest in DOH_ENDPOINTS.
Prioritized remediation

Critical: Add a tested fallback DNS option (see DNS placement section).
High: If a specific game breaks due to UDP/443, do not disable the entire control—create precise exceptions to known endpoints where possible.
Medium: Consider client-side controls for DoH (managed browser policies) where feasible; firewall-only DoH control is never fully complete.
DNS placement: AdGuard on Flint vs OPNsense
Current v4 posture

v4 routes DNS for all VLANs to AdGuardHome on Flint (10.0.50.5), with Unbound on OPNsense as upstream for recursion/privacy. (See v4 DNS section.)
What the sources say

AdGuardHome supports configurable upstream resolvers and has specific behaviors around private networks and reverse DNS, with knobs like “Use private reverse DNS resolvers” and fields like local_ptr_upstreams and use_private_ptr_resolvers. 
Unbound DNSSEC enablement is documented via auto-trust-anchor-file and unbound-anchor tooling (NLnet Labs docs). 
Tailscale subnet routing + SNAT behavior can affect how internal resolvers see client IPs and may require careful routing design if you ever disable SNAT (Linux-only option). 
Benefits of AdGuard on Flint

Uses otherwise-idle CPU on the AP.
Central place to implement parental filtering.
Risks

Single point of failure: if Flint reboots, upgrades, crashes, or loses VLAN trunk, DNS breaks for every VLAN that relies on it.
Cross-VLAN DNS flow increases policy complexity: Kids/IoT/HASS must talk to a VLAN50 host for DNS, so “block RFC1918” policies require careful exception ordering.
Concrete configuration checks

On OPNsense, confirm each VLAN’s DHCP hands out DNS = 10.0.50.5.
Confirm firewall rules allow DNS to 10.0.50.5 and allow optional fallback DNS to the gateway if you implement it.
On Flint, confirm AdGuard listens on the intended address/port and persists across reboots.
Prioritized remediation

Critical (recommended): Move DNS services onto OPNsense (AdGuard on OPNsense, or Unbound + filtering there) unless you can tolerate AP-as-DNS downtime.
High (if you keep AdGuard on Flint): Implement a real fallback DNS option (gateway Unbound) and ensure firewall rules allow it.
Medium: Consider running AdGuard on a more “always-on” host (Proxmox), but note that makes networking dependent on virtualization; OPNsense-hosted DNS is typically the simplest failure domain.
Dahua NV41AI8P-4K: minimal ports and exact firewall rules
Important note about IP

Your prompt requested assuming 10.0.20.20. The v4 document currently defines the NVR as 10.0.20.10 in aliases (NVR_DAHUA) and static assignments (local file lines 155–158 and 206–217). Decide one IP and make it consistent.
Validated default port set Multiple Dahua-oriented manual sources and port references list these defaults:

TCP 37777
UDP 37778
HTTP 80
HTTPS 443
RTSP 554 
Minimal NVR_PORTS recommendation Use the smallest set that matches what you actually do:

Baseline (UI only): TCP 443 (or TCP 80 if you keep HTTP enabled)
If you use RTSP (VLC/HA/third-party): add TCP 554 (some deployments also use RTSP over TCP; keep it TCP first)
If you use Dahua client tools / private protocol: add TCP 37777 and (only if required) UDP 37778 
So, recommended starting point:

NVR_PORTS_TCP_MIN = 443,554,37777
NVR_PORTS_UDP_MIN = 37778 (only if a tested workflow needs it)
Exact OPNsense firewall rules (using placeholder NVR IP 10.0.20.20) Create aliases:

NVR_DAHUA = 10.0.20.20
NVR_PORTS_TCP_MIN = 443,554,37777
NVR_PORTS_UDP_MIN = 37778 (optional)
ADMIN_CLIENTS = 10.0.40.10-13 (already defined in v4)
CGNAT_TAILSCALE = 100.64.0.0/10 (matches Tailscale docs and RFC6598 range) 
On PERSONAL interface (above any blocks):

Pass TCP: ADMIN_CLIENTS → NVR_DAHUA ports NVR_PORTS_TCP_MIN
Pass UDP (optional): ADMIN_CLIENTS → NVR_DAHUA port NVR_PORTS_UDP_MIN
On TAILSCALE (VPN) interface:

Pass TCP: CGNAT_TAILSCALE → NVR_DAHUA ports NVR_PORTS_TCP_MIN
Pass UDP (optional): CGNAT_TAILSCALE → NVR_DAHUA port NVR_PORTS_UDP_MIN
Then explicitly deny everything else by default.

Prioritized remediation

Critical: Make NVR IP consistent (10.0.20.10 vs 10.0.20.20) across DHCP reservation, aliases, and rules.
High: Start with minimal ports; expand only after you confirm a specific feature breaks.
Logging/retention to Splunk (operational manageability)
OPNsense capability

OPNsense supports remote logging targets via syslog-ng and documents the logging target fields (transport, applications, levels, host, port, TLS cert, etc.). 
OPNsense IPS docs explicitly mention shipping EVE syslog output via logging targets, with “suricata” application filtering. 
Benefits

Centralized audit trail across firewall decisions, VPN access, and IDS/IPS alerts.
Supports your desire to observe longer than 48 hours.
Risks

Log volume can explode (especially with deny-all logging + IPS alerts). Without retention planning, you can flood Splunk/license or storage.
If DNS is enforced tightly, DNS failures may impede name resolution of log targets if you ever use hostnames; prefer IPs.
Concrete configuration checks

OPNsense: System → Settings → Logging / Targets: configure a target to 10.0.50.208 (Splunk syslog receiver) with appropriate transport and filters. 
If sending Suricata EVE alerts, enable “EVE syslog output” and filter by application “suricata” (per OPNsense IPS docs). 
Prioritized remediation

High: Set clear log retention targets (days/weeks) and decide which rules log long-term vs commissioning-only.
Medium: Implement rate limiting or selective logging to avoid constant noise (e.g., stop logging broad deny rules once stable).
Prioritized test plan with pass/fail criteria
Critical tests

Bridge0 VLAN50 ARP/route stability:
From a VLAN50 host:
sh
Copy
ping -c 50 10.0.50.1
arp -an | grep 10.0.50.1
Pass: no intermittent loss; ARP entry stays stable across link flap; no “random” shifts between members.
Storage /30 throughput and path isolation:
On TrueNAS (or a jail/container capable of iperf3): iperf3 -s
On Proxmox:
sh
Copy
iperf3 -c 10.0.60.2 -P 4
Pass: storage traffic uses the storage NIC (interface counters increment there), and performance is consistent with link expectations; no default route appears on 10.0.60.0/30.
VPN reachability to MGMT_TARGETS:
From phone on LTE:
Connect VPN
Hit OPNsense UI, Flint UI, Marble UI, Proxmox UI by IP
Pass: access works only to MGMT_TARGETS; attempts to reach other random LAN hosts fail.
High-value tests

Kids policy functional validation:
Confirm basic browsing works (TCP 80/443).
Confirm at least one known game + voice chat works.
Pass: no repeated DNS failures; logs show blocks on UDP/443 (QUIC) and 853 (DoT) but user experience remains acceptable.
DNS bypass detection:
Attempt browser DoH enablement on a Kids device.
Watch firewall logs for:
TCP/443 to known DoH endpoints (blocked)
TCP/853 attempts (blocked) 
Pass: device cannot quietly bypass policy without generating meaningful logs.
Medium tests

WDS VLAN trunking stability:
On Marble, verify RSSI and interface presence:
sh
Copy
iwinfo wlan1 info
ip link show wlan1.20 wlan1.30
Pass: VLAN subinterfaces stay up across re-associations; no long dropouts; DHCP for Kids/IoT works near Marble.
Primary source URLs used
text
Copy
Access date: 2026-02-19 (America/New_York)

OPNsense bridging / filtering
- https://docs.opnsense.org/manual/how-tos/transparent_bridge.html  (bridge tuneables pfil_bridge/pfil_member)

OPNsense WireGuard
- https://docs.opnsense.org/manual/how-tos/wireguard-s2s.html

OPNsense IPS / Suricata
- https://docs.opnsense.org/manual/ips.html

OPNsense remote syslog targets
- https://docs.opnsense.org/manual/settingsmenu.html

Tailscale subnet routers and SNAT notes
- https://tailscale.com/docs/features/subnet-routers
- https://tailscale.com/kb/1104/enable-ip-forwarding
- https://tailscale.com/docs/reference/reserved-ip-addresses

IETF protocol references
- https://www.rfc-editor.org/rfc/rfc6598  (100.64.0.0/10 shared address space)
- https://www.rfc-editor.org/rfc/rfc7858.html  (DoT, port 853 default)
- https://www.rfc-editor.org/rfc/rfc8484.html  (DoH)
- https://www.rfc-editor.org/rfc/rfc9000.html  (QUIC over UDP)
- https://www.rfc-editor.org/rfc/rfc9114  (HTTP/3 over QUIC; UDP blocking considerations)

Unbound (NLnet Labs)
- https://unbound.docs.nlnetlabs.nl/en/latest/getting-started/configuration.html
- https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound-anchor.html
- https://www.nlnetlabs.nl/documentation/unbound/unbound.conf/

AdGuardHome configuration
- https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration/2a3c9d93771c0a173a88511b978cf8bd2bf1c003

OpenWrt references
- https://openwrt.org/docs/guide-user/network/dsa/converting-to-dsa
- https://openwrt.org/faq/enable_luci_ssl
- https://openwrt.github.io/luci/jsapi/LuCI.network.WifiDevice.html

Dahua port defaults (manual-derived sources)
- https://dahuawiki.com/NVR/Port_Information
- https://dahuawiki.com/images/d/dc/NVR_%2860_and_724_Series%29_User%27s_Manual_V5.1.0_201412.pdf
- https://www.manualslib.com/manual/924194/Dahua-Nvr4108-P.html
- https://manualzilla.com/doc/5850042/nvr-series-user-s-manual