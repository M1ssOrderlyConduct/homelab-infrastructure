# Life Operating System Design

## Executive Summary

A Home Assistant-based life management system implementing **Separation of Concerns** through two distinct subsystems:

- **The Enforcer (Home Assistant)**: Hard boundaries, state management, physical control. Cannot be negotiated with.
- **The Coach (LLM)**: Personalized interaction, task verification, escalation. Cannot change system state.

This architecture prevents future-self sabotage by separating enforcement from interaction.

---

## Part 1: System Architecture

### 1.1 The Two Brains Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER (Tim)                               │
└─────────────────────────────────────────────────────────────────┘
                    │ Voice / Physical │
                    ▼                   ▼
┌───────────────────────────┐   ┌───────────────────────────────┐
│   BRAIN 1: THE ENFORCER   │   │    BRAIN 2: THE COACH         │
│   (Home Assistant)        │   │    (LLM - llama.cpp/vllm)     │
│                           │   │                               │
│ • State machine owner     │   │ • Voice interface             │
│ • Timer enforcement       │   │ • Task verification           │
│ • Network control         │   │ • Contextual reminders        │
│ • Physical actuators      │   │ • Escalation decisions        │
│ • Cannot be reasoned with │   │ • Cannot change states        │
└───────────────────────────┘   └───────────────────────────────┘
         │                                    │
         │         ┌──────────────┐           │
         └────────►│   SHARED     │◄──────────┘
                   │   CONTEXT    │
                   │              │
                   │ • Notion API │
                   │ • Calendar   │
                   │ • GitHub     │
                   │ • State vars │
                   └──────────────┘
```

### 1.2 Golden Rules

1. **The Coach can inform, encourage, and personalize** - but only the Enforcer can change states or lift restrictions.
2. **If you say "skip the break"** - the Coach says "I hear you, but break starts in 2 minutes regardless."
3. **Configuration changes require cooldown** - changes apply tomorrow, not now.
4. **Emergency override exists** - physical button only, logged, reviewed weekly.

---

## Part 2: Operational Modes

### 2.1 Mode Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    ASF: ABSOLUTE SURVIVAL FLOOR                  │
│         The true minimum. If these happen, day is not failure.  │
├─────────────────────────────────────────────────────────────────┤
│                    MVDB: MINIMUM VIABLE DAY                      │
│              Good enough on hard days. Success floor.           │
├─────────────────────────────────────────────────────────────────┤
│                       NORMAL OPS                                 │
│                  Standard sustainable operation                  │
├─────────────────────────────────────────────────────────────────┤
│                       SURGE MODE                                 │
│         High output. Child-absent only. Energy required.        │
├─────────────────────────────────────────────────────────────────┤
│                      RECOVERY MODE                               │
│              After crisis. Mandatory rest protocol.             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 ASF - Absolute Survival Floor

**These are non-negotiable. The Enforcer protects these.**

| Task | Enforcement Method |
|------|-------------------|
| Children physically safe when present | Presence monitoring, alerts |
| Medications taken (if risk from skipping) | Timed reminder, escalation |
| Calories consumed (any means) | Evening check-in |
| Sleep occurs (any duration) | No enforcement, Coach check-in |
| Custody exchange compliance | Calendar alerts, documentation prompt |
| No irreversible data loss | Backup monitoring, alerts |
| Home secured before sleep | Automation + checklist |

**ASF Completion = Day is not a failure.** Everything else is optional.

### 2.3 MVDB - Minimum Viable Day

**Attempted only after ASF is satisfied.**

**MVDB-Core (Max 3 items on crisis days):**
- Basic hygiene (brush teeth)
- One intentional hydration
- Legal/custody incident capture (if one occurred)

**MVDB-Extended (Normal hard days):**
- Second meal
- 10-20 minute environment reset
- Device charging
- Calendar review (next 24h)

### 2.4 Normal Ops

Standard sustainable routine. See Section 4 for daily templates.

### 2.5 Surge Mode

**Requirements:**
- Custody State = Child-Absent
- Energy State = High
- No active Recovery Mode

**Allowed:**
- Multi-hour deep work blocks
- Technical migrations/builds
- Legal strategy drafting
- Deep cleaning projects

**Cooldown Rule:** After Surge Mode use, next day must be Normal Ops maximum.

### 2.6 Recovery Mode

**Triggers:**
- Missed ASF for any day
- Sleep < 6 hours for 2+ consecutive nights
- Emotional overwhelm / burnout signs
- Post-illness
- Post-crisis (legal, technical, family)

**Protocol:**
- Operate from ASF only for 24-72 hours
- No Surge Mode for 7 days minimum
- Coach check-ins increase frequency
- All optional commitments auto-cancelled

---

## Part 3: State Machine

### 3.1 Primary States

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   MORNING   │────►│    WORK     │────►│   BREAK     │
│   STARTUP   │     │             │     │  (FORCED)   │
└─────────────┘     └─────────────┘     └─────────────┘
      ▲                   │                   │
      │                   │                   │
      │                   ▼                   │
      │             ┌─────────────┐           │
      │             │  WIND_DOWN  │◄──────────┘
      │             └─────────────┘
      │                   │
      │                   ▼
      │             ┌─────────────┐
      └─────────────│     OFF     │
                    └─────────────┘
```

### 3.2 State Definitions

| State | Trigger In | Duration | Trigger Out | Custody Aware |
|-------|------------|----------|-------------|---------------|
| `morning_startup` | Scheduled time OR manual | 15-30 min | "Ready to work" OR timer | Yes |
| `work` | Exit startup | Configurable (60-120 min blocks) | Timer → forced break | Yes |
| `break` | Work timer expires | 10-15 min ENFORCED | Timer only (cannot skip) | No |
| `wind_down` | Scheduled time | 30 min | Timer → off | Yes |
| `off` | Wind-down complete OR manual | Until next trigger | Next morning OR manual | Yes |

### 3.3 Custody State Modifier

```yaml
custody_state:
  kids_home:
    allowed_modes: [ASF, MVDB, Normal_Ops]
    forbidden_modes: [Surge]
    tech_policy: "read_only"  # Monitoring only, no changes
    legal_policy: "documentation_only"  # Log events, no strategy
    work_block_max: 90  # minutes

  kids_away:
    allowed_modes: [ASF, MVDB, Normal_Ops, Surge]
    forbidden_modes: []
    tech_policy: "read_write"  # Full access
    legal_policy: "full"  # Strategy, drafting, calls
    work_block_max: 240  # minutes
```

### 3.4 Legal State Modifier

```yaml
legal_state:
  quiet:
    # No active deadlines, no hearings scheduled
    daily_requirement: "event_triggered_logging_only"
    weekly_requirement: "consolidation_review"
    coach_mentions: false

  active:
    # Ongoing process, no imminent deadline
    daily_requirement: "proactive_logging"
    weekly_requirement: "evidence_organization"
    coach_mentions: true  # "Remember to log today's exchange"

  deadline:
    # Filing/hearing within 14 days
    daily_requirement: "structured_documentation"
    weekly_requirement: "preparation_milestones"
    surge_allowed: true  # Even on some child-present days with childcare
    coach_priority: "legal_first"
```

---

## Part 4: Daily Templates

### 4.1 Custody Day Template (Kids Present)

```
0600-0630  Wake, meds, water, 5-min legal log (previous day)
0630-0800  Kids up, breakfast, dress, school prep
0800-0830  School transport
0830-1500  WORK BLOCK (3yo requires childcare solution)
           ├── First 90 min: Top priority (PROTECTED)
           ├── Coach check-in at 45 min mark
           ├── FORCED BREAK at 90 min (15 min, enforced)
           └── Remaining: Meetings, reactive work, admin batch
1500-1530  School pickup
1530-1730  Homework (9yo), play supervision, snacks
1730-1830  Dinner (batch-cooked or simple)
1830-1930  Family time, activity, outside
1930-2030  Bath rotation, bedtime routine, stories
2030-2100  3yo settle, older kids reading
2100-2130  Shutdown: dishes, bags prepped, quick tidy
2130-2145  Legal documentation (5 min, custody log)
2145-2200  Infrastructure glance (dashboard alerts only)
2200       In bed, screens off

FORBIDDEN: Deep technical work, complex legal strategy, new projects
ALLOWED: Parenting, maintaining, monitoring, logging
```

### 4.2 Non-Custody Day Template (Kids Away)

```
0700-0730  Wake, meds, water, review day plan
0730-0800  Hygiene, breakfast
0800-1200  DEEP WORK BLOCK 1 (4 hours protected)
           ├── Technical projects, complex coding
           ├── Phone on DND, no email
           ├── Coach check-in at 2-hour mark
           └── FORCED BREAK at end (15 min)
1200-1300  Lunch, walk, break (MANDATORY)
1300-1600  DEEP WORK BLOCK 2 OR Admin/Legal block
           ├── Legal strategy, evidence organization
           └── OR continued technical work
1600-1700  Administrative batch (bills, emails, scheduling)
1700-1800  Physical activity (20-30 min minimum)
1800-1900  Dinner, personal
1900-2100  Flexible: social, hobby, project continuation, rest
2100-2130  Shutdown routine
2130-2145  Legal log (habit maintenance even if no events)
2145-2200  Infrastructure check
2200       In bed

SURGE MODE AVAILABLE: If energy is high and no recent Surge use
```

### 4.3 Transition Day Template (Custody Exchange)

Custody exchanges are high-friction. Plan for **50% capacity**.

**Receiving Kids:**
- Morning: Prep house, food stocked, rooms ready
- Exchange window: Buffer 30 min before/after
- Post-exchange: Mode 1 (Custody Day) kicks in
- Document: Exchange time, children's demeanor, any co-parent communication

**Releasing Kids:**
- Complete kid-related tasks before exchange
- Post-exchange: Decompress 1 hour (NOT productive time)
- Remainder: Mode 2 at reduced intensity
- Document: Same as receiving

---

## Part 5: The Enforcer (Home Assistant)

### 5.1 Core Responsibilities

| Function | Implementation |
|----------|----------------|
| State management | Input booleans, automations |
| Timer enforcement | Timer helpers, cannot be cancelled by voice |
| Network control | UniFi API integration |
| Physical control | Smart plugs, lights, locks |
| Break enforcement | Network block + physical indicators |
| Emergency override | Physical button (Zigbee), logged |

### 5.2 Network Enforcement

**During BREAK state:**

```yaml
# UniFi firewall rule triggered by HA
break_mode_blocks:
  - github.com
  - gitlab.com
  - stackoverflow.com
  - reddit.com
  - news.ycombinator.com
  - youtube.com (except music.youtube.com)
  - All work-related domains

break_mode_allows:
  - Meditation apps (Headspace, Calm)
  - Music streaming
  - Weather
  - Health apps
```

### 5.3 Physical Enforcement

| Device | Purpose | Control |
|--------|---------|---------|
| Space heater | Morning warmup | Smart plug, scheduled |
| Busy light (office door) | Status broadcast | Smart bulb: Red=work, Yellow=break, Off=available |
| Workstation | Wake/sleep control | WoL + SSH sleep command |
| Task display | Shows priorities/timer | Dedicated tablet or monitor |

### 5.4 State Transitions (Automations)

```yaml
# Morning Startup Trigger
automation:
  trigger:
    - platform: time
      at: input_datetime.work_start_time
    - platform: state
      entity_id: binary_sensor.office_occupancy
      to: 'on'
      for: '00:05:00'
  condition:
    - condition: state
      entity_id: input_select.system_state
      state: 'off'
    - condition: time
      weekday: [mon, tue, wed, thu, fri]
  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.system_state
      data:
        option: 'morning_startup'
    - service: switch.turn_on
      target:
        entity_id: switch.office_heater
    - service: script.wake_workstation
    - service: notify.coach_llm
      data:
        message: "trigger_morning_greeting"
```

```yaml
# Forced Break Trigger (Cannot be cancelled)
automation:
  trigger:
    - platform: state
      entity_id: timer.work_block
      to: 'idle'
  condition:
    - condition: state
      entity_id: input_select.system_state
      state: 'work'
  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.system_state
      data:
        option: 'break'
    - service: timer.start
      target:
        entity_id: timer.break_duration
      data:
        duration: "{{ states('input_number.break_duration') | int }}:00"
    - service: script.activate_break_mode
    # Network block activates automatically via break state
```

### 5.5 Emergency Override

**Physical button (NOT voice, NOT app):**

```yaml
automation:
  alias: "Emergency Override"
  trigger:
    - platform: state
      entity_id: binary_sensor.emergency_button
      to: 'on'
  action:
    - service: input_select.select_option
      target:
        entity_id: input_select.system_state
      data:
        option: 'off'
    - service: script.disable_all_enforcement
    - service: input_datetime.set_datetime
      target:
        entity_id: input_datetime.last_emergency_override
      data:
        datetime: "{{ now().isoformat() }}"
    - service: counter.increment
      target:
        entity_id: counter.emergency_override_count
    - service: notify.tim_all_channels
      data:
        title: "Emergency Override Activated"
        message: "Override logged at {{ now().strftime('%H:%M') }}. Weekly review required."
```

---

## Part 6: The Coach (LLM)

### 6.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      VOICE PIPELINE                              │
├─────────────┬─────────────┬─────────────┬─────────────┬────────┤
│ Wake Word   │   Whisper   │    LLM      │   Piper     │ Output │
│ OpenWakeWord│    STT      │   Coach     │    TTS      │ Speaker│
│ (NVIDIA VM) │ (NVIDIA VM) │(llama.cpp)  │ (NVIDIA VM) │        │
└─────────────┴─────────────┴─────────────┴─────────────┴────────┘
```

### 6.2 Context Injection

The Coach receives this context with every interaction:

```json
{
  "current_state": "work",
  "time_remaining": "47 minutes",
  "custody_state": "kids_away",
  "legal_state": "quiet",
  "energy_state": "normal",
  "today_priority": "Complete API endpoint",
  "notion_tasks": [
    {"task": "API endpoint", "status": "in_progress", "due": "today"},
    {"task": "Review PR", "status": "pending", "due": "today"}
  ],
  "calendar_next": "Pickup kids at 1530",
  "github_stakes": "This project funds summer camp. Two people waiting on deliverable.",
  "work_blocks_today": 2,
  "breaks_taken": 1,
  "last_check_in": "45 minutes ago",
  "children": ["Ryland (9)", "Mateo (6)", "Mila (3)"]
}
```

### 6.3 Coach Behaviors by Moment

| Moment | Coach Behavior |
|--------|----------------|
| Morning startup | "Good morning. Today you've got 3 tasks. The API deadline is Thursday - two people are waiting on it. Ready when you are." |
| Work check-in (30-45 min) | "How's the API endpoint going? You've been focused for 40 minutes. Break in 50." |
| Pre-break (5 min) | "Wrapping up this block in 5 minutes. Good stopping point coming up." |
| Break start | "Break time. Stand up, roll your shoulders. Network's restricted - let's do 2 minutes of breathing." |
| Break resistance | "I hear you want to keep going. Break happens in 90 seconds regardless. Want to save your work?" |
| Stakes reminder | "Remember: this project funds the kids' summer camp. Ryland, Mateo, and Mila are counting on you." |
| Wind-down | "Solid day. You completed 2 tasks, stayed focused for 4 hours. Shutting down in 15." |
| Transition day | "Exchange at 1700. House is prepped. Remember to document the exchange." |

### 6.4 Coach Limitations (Hardcoded)

The Coach **CANNOT**:
- Change system state
- Extend or skip timers
- Disable network enforcement
- Override break mode
- Cancel wind-down
- Access anything outside defined context

If asked to do forbidden actions:
> "I can't change the break timer. That's enforced by the system, not me. Break ends in 8 minutes. What do you want to focus on when it's over?"

### 6.5 Task Verification (Notion Integration)

**Not just "how's it going?" - actual verification:**

```python
# Coach queries Notion before check-in
def verify_progress(notion_client, task_id):
    task = notion_client.get_task(task_id)
    return {
        "task": task.title,
        "status": task.status,  # Not Started / In Progress / Complete
        "last_updated": task.last_edited,
        "subtasks_complete": task.subtasks_done / task.subtasks_total
    }

# Coach uses this in check-in
if task.status == "Not Started" and time_elapsed > 60:
    response = f"Task '{task.title}' is still marked Not Started. What's blocking you?"
elif task.status == "In Progress" and subtasks_progress < 0.25 and time_elapsed > 90:
    response = f"You're 90 minutes in but only 25% through subtasks. Need to break this down differently?"
```

---

## Part 7: Accountability & Escalation System

### 7.1 Three-Tier Escalation

```
┌─────────────────────────────────────────────────────────────────┐
│ LEVEL 1: COACH (Normal)                                          │
│ • Gentle check-ins                                               │
│ • Task verification                                              │
│ • Stakes reminders                                               │
│ • Contextual encouragement                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                    (If no action after 2 check-ins)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LEVEL 2: MARGARET (Coordinator - Persistent)                     │
│ • Direct, specific language                                      │
│ • "Tim, you committed to X by today - where are we?"            │
│ • Updates Notion status                                          │
│ • Relentless follow-up                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                    (If still no action after 2 more attempts)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ LEVEL 3: GENERAL MATTIS (SITREP - Emergency)                     │
│ • Triple email to ALL THREE addresses                            │
│ • Military-brief format                                          │
│ • Names children specifically                                    │
│ • Cannot be ignored                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Escalation Triggers

| Condition | Escalation |
|-----------|------------|
| Task not started after 60 min of "In Progress" work block | Level 1 → Level 2 |
| 3+ hours on low-priority while deadline looms | Level 2 → Level 3 |
| Multiple Level 2 reminders ignored | Level 3 |
| Break skipped (impossible normally, but via emergency override) | Level 3 |
| Legal documentation missed 2+ days | Level 3 |

### 7.3 General Mattis SITREP Format

**Triple email to:**
- timothypcorcoran@outlook.com
- timothypcorcoran13@gmail.com
- timothypcorcoran@passmail.me

```
SUBJECT: SITREP: 2026-01-20 1400hrs

SITUATION:
You committed to API endpoint completion by 1500. Current time: 1400.
Task status: Not Started. You've spent 90 minutes on documentation
that was already sufficient.

ASSESSMENT:
You have 60 minutes until deadline. API work requires 45 minutes minimum.
You are choosing perfectionism over execution. This delays the deliverable
and breaks your commitment to the team.

STAKES:
Ryland, Mateo, and Mila will be home at 1800. You promised them focused
time tonight. Each delay compounds. Each "just one more thing" steals
minutes from people who won't be children forever.

MISSION:
Close documentation. Start API work now. Ship before pickup.

- General
```

**Rules:**
- Under 200 words
- No exclamation points
- No encouragement
- Children named specifically
- One clear directive

---

## Part 8: Failure Detection & Recovery

### 8.1 Early Warning Signals (Yellow Flags)

| Signal | Detection | Response |
|--------|-----------|----------|
| Dishes piling >24h | Visual (Frigate?) or manual log | Coach mentions in next check-in |
| "I'll document later" | Pattern in responses | Immediate Margaret escalation |
| Skipping showers/meds | Missed check-in confirmations | Coach: "Basic care check - you good?" |
| 3+ days takeout | Manual log or receipt tracking | Coach: "Noticing meal patterns. Energy okay?" |
| Emergency overrides >1/week | Counter in HA | Force Recovery Mode discussion |

### 8.2 Red Flags (Circuit Breakers)

| Event | Automatic Response |
|-------|-------------------|
| Missed legal deadline | Full stop. Recovery Mode. Attorney notification check. |
| Tech outage >24h from neglect | Pause all optional projects. Maintenance sprint. |
| Emotional outburst at children | Recovery Mode. Support network contact suggested. |
| Sleep <6h for 3+ nights | Mandatory reduced schedule. No Surge for 14 days. |
| ASF missed for any day | Recovery Mode activated automatically. |

### 8.3 Recovery Protocol

```yaml
recovery_mode:
  duration: "72_hours_minimum"

  allowed:
    - ASF tasks only
    - MVDB-Core if energy permits

  forbidden:
    - Surge Mode
    - New commitments
    - Deep technical work
    - Complex legal work

  coach_behavior:
    check_in_frequency: "every_4_hours"
    tone: "supportive_not_demanding"
    task_load: "zero_new_tasks"

  exit_criteria:
    - Sleep >7h for 2 consecutive nights
    - ASF completed for 2 consecutive days
    - Self-assessment: "Ready to resume"

  post_recovery:
    - 3 days Normal Ops maximum
    - No Surge for 7 days
    - Review: "What broke and why?"
```

---

## Part 9: Integration Specifications

### 9.1 Notion Integration

**Databases Required:**

1. **Master Task Database**
   - Task Name, Status, Priority, Due Date
   - Time Estimate, Time Deadline (0.75x)
   - Custody State Required, Energy Required
   - ASF/MVDB/Normal/Surge classification

2. **Daily Log**
   - Date, Custody State, Tasks Completed
   - ASF Pass (boolean), MVDB Pass (boolean)
   - Energy Level, Blockers, Wins

3. **Legal Documentation Log**
   - Date, Exchange Time, Children Present
   - Co-parent Communication Summary
   - Notable Events, Compliance Notes

**API Endpoints Used:**
- Query tasks by status and due date
- Update task status
- Create daily log entries
- Query legal log for completeness

### 9.2 Calendar Integration

- Google Calendar or local CalDAV
- Custody schedule as recurring events
- School events imported
- Automatic buffer time around exchanges

### 9.3 GitHub Integration (Stakes Content)

```yaml
# stakes.yaml in private repo
projects:
  api_endpoint:
    stakes: "This project funds summer camp. Two people waiting on deliverable."
    deadline: "2026-01-23"
    people_affected: ["Sarah (PM)", "Dev team"]

  legal_prep:
    stakes: "Documentation quality affects custody stability."
    deadline: "ongoing"
    people_affected: ["Ryland", "Mateo", "Mila"]

reminders:
  during_work:
    - "Every hour focused is an hour earned for your kids."
    - "The people waiting on this work are real. Ship it."
    - "Perfectionism is procrastination in disguise."

  during_break:
    - "Your body needs this. Your brain needs this."
    - "The work will still be there. Recovery is part of the job."
```

### 9.4 Email Integration (SITREP Delivery)

```python
# Via Proton Mail Bridge or SMTP
def send_sitrep(sitrep_content):
    recipients = [
        "timothypcorcoran@outlook.com",
        "timothypcorcoran13@gmail.com",
        "timothypcorcoran@passmail.me"
    ]

    for recipient in recipients:
        send_email(
            to=recipient,
            from_="general@reality-check.mil",  # Alias
            subject=f"SITREP: {datetime.now().strftime('%Y-%m-%d %H%M')}hrs",
            body=sitrep_content
        )
```

---

## Part 10: Physical Components

### 10.1 Required Hardware

| Component | Purpose | Status |
|-----------|---------|--------|
| Raspberry Pi 5 | Home Assistant host | Existing |
| RTX 4070 Ti Super | LLM inference (llama.cpp) | Existing (CT 118) |
| Motion sensors (4-5) | Presence detection, room context | In box - needs setup |
| Smart plugs | Heater, workstation control | Needs procurement |
| Smart bulb (office door) | Busy light status | Needs procurement |
| Physical button (Zigbee) | Emergency override | Needs procurement |
| ESP32-S3 | Voice satellite | Existing |
| Tablet/display | Task display | Optional |

### 10.2 Sensor Placement

```
┌─────────────────────────────────────────┐
│                 OFFICE                   │
│  ┌─────┐                    [SENSOR 1]  │
│  │DESK │                    (Occupancy) │
│  └─────┘                                │
│           [BUSY LIGHT]                  │
│              (Door)                     │
├─────────────────────────────────────────┤
│              HALLWAY         [SENSOR 2] │
├─────────────────────────────────────────┤
│            LIVING ROOM       [SENSOR 3] │
│                              (Kids area)│
├─────────────────────────────────────────┤
│              KITCHEN         [SENSOR 4] │
└─────────────────────────────────────────┘
```

---

## Part 11: Configuration Schema

### 11.1 User-Configurable (During OFF State Only)

```yaml
schedule:
  work_start: "08:30"
  work_end: "17:00"
  work_days: [mon, tue, wed, thu, fri]

work_blocks:
  duration_minutes: 90
  max_per_day: 4

breaks:
  duration_minutes: 15
  activities: ["breathing", "stretching", "walking", "meditation"]

custody:
  calendar_id: "custody_calendar"
  transition_buffer_minutes: 30

escalation:
  level2_after_ignored_checkins: 2
  level3_after_level2_attempts: 2

recovery:
  auto_trigger_on_missed_asf: true
  minimum_duration_hours: 72
```

### 11.2 System-Controlled (Cannot Be Changed by User)

```yaml
enforcement:
  break_skippable: false
  timer_extendable: false
  network_bypassable: false

emergency_override:
  requires_physical_button: true
  logged: true
  weekly_review_required: true

configuration_changes:
  apply_delay: "next_day"
  require_off_state: true
```

---

## Part 12: Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

- [ ] Set up Home Assistant input helpers (states, timers, counters)
- [ ] Create basic state machine automations
- [ ] Install and configure motion sensors
- [ ] Set up busy light automation
- [ ] Create daily schedule automations

### Phase 2: Enforcement (Week 3-4)

- [ ] Configure UniFi API integration for network control
- [ ] Set up break mode network restrictions
- [ ] Configure workstation WoL and sleep control
- [ ] Set up heater automation
- [ ] Install emergency override button
- [ ] Create override logging system

### Phase 3: Voice Interface (Week 5-6)

- [ ] Configure Wyoming pipeline (Whisper, Piper, OpenWakeWord)
- [ ] Set up llama.cpp for Coach responses
- [ ] Create Coach prompt templates
- [ ] Test voice interaction end-to-end
- [ ] Tune response latency

### Phase 4: Intelligence (Week 7-8)

- [ ] Integrate Notion API for task queries
- [ ] Set up calendar integration
- [ ] Create GitHub stakes content
- [ ] Implement task verification logic
- [ ] Create check-in scheduling

### Phase 5: Escalation (Week 9-10)

- [ ] Implement Margaret persona logic
- [ ] Implement General Mattis SITREP generation
- [ ] Configure email delivery (Proton Bridge)
- [ ] Test escalation ladder end-to-end
- [ ] Create escalation logging

### Phase 6: Polish & Testing (Week 11-12)

- [ ] Full system stress test
- [ ] Failure mode testing (what if X breaks?)
- [ ] Recovery protocol testing
- [ ] Documentation completion
- [ ] 2-week live trial with adjustments

---

## Appendix A: Home Assistant Entity Reference

```yaml
# Input Selects
input_select.system_state: [off, morning_startup, work, break, wind_down, recovery]
input_select.custody_state: [kids_home, kids_away, transition]
input_select.legal_state: [quiet, active, deadline]
input_select.energy_state: [low, normal, high]
input_select.operating_mode: [asf, mvdb, normal, surge, recovery]

# Timers
timer.work_block: Work session countdown
timer.break_duration: Break enforcement
timer.wind_down: End of day countdown

# Counters
counter.work_blocks_today: Daily work block count
counter.breaks_taken_today: Daily breaks completed
counter.emergency_override_count: Weekly override tracking
counter.escalation_level: Current escalation tier

# Input Booleans
input_boolean.break_network_block: Network restriction active
input_boolean.recovery_mode: Recovery mode flag
input_boolean.surge_available: Surge mode eligibility

# Input Datetimes
input_datetime.work_start_time: Configurable start
input_datetime.work_end_time: Configurable end
input_datetime.last_emergency_override: Override timestamp

# Input Numbers
input_number.work_block_duration: Minutes per block
input_number.break_duration: Minutes per break
input_number.max_work_blocks: Daily limit

# Sensors
sensor.current_state_duration: Time in current state
sensor.next_transition: When next state change occurs
sensor.asf_completion: ASF tasks done today
sensor.mvdb_completion: MVDB tasks done today
```

---

## Appendix B: Coach Prompt Templates

### Morning Greeting
```
You are the Coach in a life management system. Tim just entered morning_startup state.

Context:
- Custody state: {custody_state}
- Today's top priority: {today_priority}
- Stakes: {github_stakes}
- Calendar: {next_calendar_event}

Generate a brief (2-3 sentences) morning greeting that:
1. Acknowledges the day ahead
2. States the top priority
3. Mentions stakes if deadline is within 3 days
4. Ends with "Ready when you are"

Do NOT use exclamation points. Be direct, not enthusiastic.
```

### Work Check-in
```
You are the Coach. Tim is {time_elapsed} minutes into a work block.

Context:
- Current task: {current_task}
- Task status in Notion: {task_status}
- Subtask progress: {subtask_progress}%
- Break in: {time_to_break} minutes
- Energy state: {energy_state}

Generate a brief check-in (1-2 sentences) that:
1. Acknowledges progress (or lack thereof, factually)
2. Mentions break timing
3. If task is Not Started after 30+ min, ask what's blocking

Do NOT offer to extend time or skip breaks. You cannot do this.
```

### Stakes Reminder
```
You are the Coach delivering a stakes reminder. Tim has been unfocused.

Context:
- Task: {current_task}
- Stakes from GitHub: {github_stakes}
- Children: Ryland (9), Mateo (6), Mila (3)
- Deadline: {deadline}

Generate a reminder (2-3 sentences) that:
1. States what's at stake concretely
2. Mentions who is affected
3. Does NOT moralize or guilt-trip
4. States facts, not opinions

Tone: matter-of-fact, not harsh, not encouraging.
```

---

## Appendix C: SITREP Generation Template

```
You are General James Mattis (retired). Margaret has summoned you because Tim needs a reality check.

Situation provided by Margaret:
{situation_summary}

Generate a SITREP email following this exact structure:

SUBJECT: SITREP: {current_date} {current_time_military}hrs

SITUATION:
[2-3 sentences. Facts only. What is actually happening.]

ASSESSMENT:
[2-3 sentences. What this means. Connect actions to outcomes.]

STAKES:
[2-3 sentences. Frame in terms of Ryland, Mateo, and Mila by name.
Remind that hours spent on nonsense are hours stolen from children
who won't be children forever.]

MISSION:
[1 sentence. One clear directive. No options.]

- General

RULES:
- Under 200 words total
- No exclamation points
- No encouragement ("You can do it")
- No warmth
- Military time
- Name the children
```

---

*Document created: 2026-01-20*
*Status: Design complete, pending implementation*
*Next action: Phase 1 implementation*
