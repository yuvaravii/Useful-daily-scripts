# 05 — How It Works

The data source, the rules and the formulas behind every number.

← [04 Troubleshooting](04_TROUBLESHOOTING.md) · [Back to README](../README.md) · Next: [06 Reference](06_REFERENCE.md)

---

## 1. Pipeline

```text
System event log
   │  1. Read events (range start − 14 days → range end + 1 day)
   ▼
State-change events (Boot, Wake, Standby, Sleep, Shutdown, Crash)
   │  2. Sort by time
   ▼
Segments: [start, end, state]
   │  3. Clip to the range
   │  4. Split at midnight
   ▼
Per-day hours per state
   │  5. Apply overtime rules
   ▼
daily / segments / crashes / summary CSV  +  HTML report
```

## 2. Events Used

| Provider | ID | Meaning | Becomes |
|---|---|---|---|
| Microsoft-Windows-Kernel-General | 12 | OS started | **Active** (Boot) |
| Microsoft-Windows-Kernel-General | 1 | System time changed | **Active** (Wake), if the jump is > 5 min |
| Microsoft-Windows-Kernel-Power | 507 | Exit Modern Standby | **Active** |
| Microsoft-Windows-Kernel-Power | 506 | Enter Modern Standby | **Standby** |
| Microsoft-Windows-Kernel-Power | 42 | Enter sleep / hibernate | **Off** (Sleep) |
| Microsoft-Windows-Kernel-General | 13 | OS shutting down | **Off** (Shutdown) |
| Microsoft-Windows-Kernel-Power | 41 | Rebooted without clean shutdown | Marks a **Crash** before this boot |
| User32 | 1074 | Restart started by a process | Update restart, if the process is `MoUsoCoreWorker` or `TrustedInstaller` |

### Events deliberately **not** used

| Event | Why not |
|---|---|
| Kernel-Power 107 "resumed from sleep" | Windows logs it with the **frozen clock**, a few seconds after the sleep. The real wake can be hours later. |
| EventLog 6008 "previous shutdown was unexpected" | Its time often conflicts with the log. Example: it reported 12:39 for a crash before a 09:43 boot. |
| Power-Troubleshooter 1 | Logged for only a small number of wakes |

## 3. Real Wake Time

The clock stops during sleep or hibernate. On wake, Windows corrects the clock and logs **Kernel-General 1**, which has the old time and the new time.

```text
if (NewTime − OldTime) > 5 minutes:
    real wake time = NewTime
```

Example:

| Event | Logged time | Real meaning |
|---|---|---|
| Kernel-Power 42 | 17:05:05 | Went to sleep |
| Kernel-Power 107 | 17:05:12 | ❌ Clock still frozen |
| Kernel-General 1 | Old 17:05 → New **08:14 (next day)** | ✅ Real wake |

## 4. Crash Detection

1. Find every **Kernel-Power 41**. Each one belongs to the boot just before it.
2. **Crash time** = the newest System event of any type before that boot.
3. **Crash hours** = boot time − crash time.
4. **Cause**: checked in this order, and the first match wins:

| Order | Condition (Event 41 field) | Cause |
|---|---|---|
| 1 | `BugcheckCode` ≠ 0 | Blue screen |
| 2 | `PowerButtonTimestamp` ≠ 0 **or** `LongPowerButtonPressDetected` = true | Power button held |
| 3 | `SleepInProgress` ≠ 0 | Lost power during sleep |
| 4 | none of the above | Freeze or power loss |

## 5. Timeline Rules

| # | Rule | Reason |
|---|---|---|
| R1 | Each gap between two events gets the state of the earlier event | Simple state machine |
| R2 | 506 and 507 in the same second are ignored | Momentary wake (for example, a network check) |
| R3 | While **Off** or **Crash**, ignore standby events | Standby noise that Windows logs while asleep |
| R4 | While **Crash**, ignore Sleep and Shutdown events | Old timestamps logged during the boot after a crash |
| R5 | State before the first event = Active | Assumption. The 14-day look-back reduces its effect. |
| R6 | Active periods < `MinActiveMinutes` do not set First/Last | Removes very short wakes |

## 6. Formulas

### Per day

```text
ActiveHours  = Σ Active segment hours in the day
CrashHours   = Σ Crash  segment hours in the day
StandbyHours = Σ Standby segment hours in the day
OffHours     = Σ Off    segment hours in the day

Weekday (Mon–Fri):
    RegularHours  = min(ActiveHours, StandardHours)
    OvertimeHours = max(ActiveHours − StandardHours, 0)
Weekend (Sat–Sun):
    RegularHours  = 0
    OvertimeHours = ActiveHours
```

### Per range

```text
ActiveDays            = count(days where ActiveHours > 0)
AvgActivePerActiveDay = Σ ActiveHours / ActiveDays
WeekdayOvertime       = Σ OvertimeHours where DayType = Weekday
WeekendOvertime       = Σ OvertimeHours where DayType = Weekend
UncleanShutdowns      = count(crashes with boot inside the range)
```

## 7. Roadmap

| Item | Fixes | Status |
|---|---|---|
| Active from lock/unlock (Security 4800/4801) or first logon | L1, L2 (overnight inflation) | Proposed |
| `-HolidayFile` parameter | L3 (public holidays) | Proposed |
| Warning when the log starts after `-StartDate` | L5 | Proposed |
| Health scorecard (green/amber/red) | — | [Proposal](USAGE_HEALTH_METRICS_PROPOSAL.md) |
| Weekly scheduled run → `health_history.csv` | Trend tracking | Proposed |
