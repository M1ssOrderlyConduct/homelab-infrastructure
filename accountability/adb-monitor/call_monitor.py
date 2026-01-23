#!/usr/bin/env python3
"""
ADB Call Log Monitor for Home Assistant
Tracks phone calls to verify task completion (lawyer, therapist, school, etc.)
"""

import subprocess
import json
import re
from datetime import datetime, timedelta
import requests

# Configuration
HA_URL = "http://10.0.50.10:8123"  # Adjust to your HA instance
HA_TOKEN = "YOUR_LONG_LIVED_TOKEN"  # Generate in HA Profile
PHONE_IP = "10.0.50.XXX:5555"  # Your phone's IP after ADB TCP/IP setup

# Target numbers to track - add your contacts
TARGET_NUMBERS = {
    "+1234567890": "lawyer",
    "+0987654321": "therapist",
    "+1122334455": "school",
    # Add more as needed
}

# Minimum call duration (seconds) to count as "completed"
REQUIREMENTS = {
    'lawyer': {'min_duration': 60},
    'therapist': {'min_duration': 300},
    'school': {'min_duration': 30},
}


def get_recent_calls(hours=24):
    """Pull call log via ADB content provider query"""
    cutoff = int((datetime.now() - timedelta(hours=hours)).timestamp() * 1000)

    cmd = f'''adb -s {PHONE_IP} shell content query --uri content://call_log/calls \
        --projection number:date:duration:type \
        --where "date>{cutoff}"'''

    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    calls = []
    for line in result.stdout.strip().split('\n'):
        if 'Row:' in line:
            match = re.search(r'number=([^,]+).*date=(\d+).*duration=(\d+).*type=(\d+)', line)
            if match:
                number, date, duration, call_type = match.groups()
                # Normalize number (remove spaces, dashes)
                number = re.sub(r'[\s\-()]', '', number)
                calls.append({
                    'number': number,
                    'timestamp': int(date),
                    'duration': int(duration),
                    'type': int(call_type),  # 1=incoming, 2=outgoing, 3=missed
                    'label': TARGET_NUMBERS.get(number, 'unknown')
                })
    return calls


def check_required_calls(calls, requirements):
    """
    Check if required calls were made with minimum duration
    Returns dict of {label: {completed: bool, duration: int, timestamp: int}}
    """
    results = {}
    for label, req in requirements.items():
        # Filter to outgoing calls (type=2) with matching label
        matching = [c for c in calls if c['label'] == label and c['type'] == 2]
        if matching:
            longest = max(matching, key=lambda x: x['duration'])
            results[label] = {
                'completed': longest['duration'] >= req.get('min_duration', 0),
                'duration': longest['duration'],
                'timestamp': longest['timestamp']
            }
        else:
            results[label] = {'completed': False, 'duration': 0, 'timestamp': None}
    return results


def push_to_ha(results):
    """Update Home Assistant sensors via REST API"""
    headers = {
        "Authorization": f"Bearer {HA_TOKEN}",
        "Content-Type": "application/json"
    }

    for label, data in results.items():
        sensor_id = f"sensor.call_task_{label}"
        payload = {
            "state": "complete" if data['completed'] else "pending",
            "attributes": {
                "duration_seconds": data['duration'],
                "last_call": data['timestamp'],
                "friendly_name": f"Call Task: {label.title()}"
            }
        }

        try:
            response = requests.post(
                f"{HA_URL}/api/states/{sensor_id}",
                headers=headers,
                json=payload
            )
            response.raise_for_status()
            print(f"Updated {sensor_id}: {payload['state']}")
        except requests.exceptions.RequestException as e:
            print(f"Failed to update {sensor_id}: {e}")


def main():
    print(f"Checking calls from last 24 hours...")
    calls = get_recent_calls(24)
    print(f"Found {len(calls)} calls")

    results = check_required_calls(calls, REQUIREMENTS)
    print(json.dumps(results, indent=2))

    push_to_ha(results)
    print("Done!")


if __name__ == "__main__":
    main()
