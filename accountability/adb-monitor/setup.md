# ADB Call Monitoring Setup

## Prerequisites

- Android phone with USB debugging enabled
- ADB installed on monitoring host
- Home Assistant with REST API enabled

## Phone Setup

1. Enable Developer Options on phone (tap Build Number 7 times)
2. Enable USB Debugging in Developer Options
3. Connect phone via USB and authorize debugging

## Enable Wireless ADB

```bash
# With USB connected
adb tcpip 5555

# Disconnect USB, then connect wirelessly
adb connect 10.0.50.XXX:5555

# Verify
adb devices
```

## Install Dependencies

```bash
apt install adb python3-pip
pip install requests
```

## Configure Script

Edit `call_monitor.py`:

1. Set `HA_URL` to your Home Assistant URL
2. Generate a Long-Lived Access Token in HA (Profile → Security → Create Token)
3. Set `HA_TOKEN` to your token
4. Set `PHONE_IP` to your phone's IP
5. Add phone numbers to `TARGET_NUMBERS` dict

## Create Cron Job

```bash
# Run every 15 minutes
cat > /etc/cron.d/call-monitor << 'EOF'
*/15 * * * * root /opt/accountability/call_monitor.py
EOF
```

## Test

```bash
# Test ADB connection
adb -s 10.0.50.XXX:5555 shell content query --uri content://call_log/calls --projection number:date:duration:type

# Run script manually
python3 call_monitor.py
```

## Home Assistant Sensors

The script creates sensors like:
- `sensor.call_task_lawyer`
- `sensor.call_task_therapist`
- `sensor.call_task_school`

Use these in automations and dashboards.
