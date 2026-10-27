# 03 — Reading the Report

What each number means, and when **not** to trust it.

← [02 Run Checklist](02_RUN_CHECKLIST.md) · [Back to README](../README.md) · Next: [04 Troubleshooting](04_TROUBLESHOOTING.md)

---

## 1. The Four States

Every minute of every day is in **one** of four states:

| State | Colour in bar | Meaning |
|---|---|---|
| **Active** | Blue | Laptop on and not in standby |
| **Standby** | Orange | Modern Standby: lid closed or screen off, low power, network may run |
| **Crash** | Red | Down after an unclean stop, until the next boot |
| **Off** | Grey (empty) | Sleep, hibernate, or clean shutdown |

- For a full day: `Active + Standby + Crash + Off = 24 h`.
- Today stops at the time you ran the script.

## 2. KPI Cards (top of the HTML report)

| Card | Formula | Example |
|---|---|---|
| Active days | Days with active hours > 0 | 23 |
| Active hours | Σ ActiveHours | 196.46 |
| Overtime hours | Σ OvertimeHours | 42.58 |
| Weekday OT (> 9 h) | Σ OvertimeHours, Mon–Fri | 32.94 |
| Weekend OT | Σ OvertimeHours, Sat–Sun | 9.64 |
| Crash hours | Σ CrashHours | 123.19 |
| Standby hours | Σ StandbyHours | 51.23 |
| Avg awake / active day | Active hours ÷ active days | 8.54 |
| Unclean shutdowns | Count of Kernel-Power 41 boots | 12 |

## 3. Daily Table — How to Read One Row

Example row:

| Date | Day | First | Last | Active | Regular | OT | Crash h | Standby | Crash | Events |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-02 | Fri | 08:14 | 15:44 | 6.75 | 6.75 | 0 | 0.75 | 0 | 1 | Wake 08:14; Crash 10:30; Boot 11:15; Sleep 15:44 |

Read it as:

1. Laptop woke at **08:14**.
2. It stopped without a clean shutdown after **10:30**.
3. It was down for **0.75 h**, until the boot at **11:15**.
4. It went to sleep at **15:44**.
5. Active **6.75 h**, below 9 h, so there is **no overtime**.

### Special values

| You see | Meaning |
|---|---|
| `First = 00:00` | The laptop was already active at midnight, carried over from the day before |
| `Last = 24:00` | The laptop was still active at midnight |
| Empty First/Last | No active period of ≥ 2 min that day |
| `[Update]` in Events | Windows Update restarted the laptop that day |
| Red row | At least one crash that day |

## 4. Unclean Shutdowns Table

| Column | Meaning |
|---|---|
| Last seen | Last event before the stop (the earliest possible crash time) |
| Next boot | When the laptop started again |
| Down h | Next boot − Last seen |
| Likely cause | From Event 41 fields. See below. |

| Cause text | What to do |
|---|---|
| Lost power during sleep (battery?) | Battery drained in standby. Run the battery and sleep reports ([04 §5](04_TROUBLESHOOTING.md#5-device-checks-for-crashes)). |
| Power button held | Someone forced the laptop off. Check if it was frozen. |
| Blue screen (BugcheckCode …) | Driver or hardware fault. Search for the code, or contact IT. |
| Freeze or power loss (no detail) | Hard freeze, or the power was cut |

> **Crash hours are not lost work.** They are the time the laptop was down. Most of it is usually overnight or on a weekend.

## 5. Limitations — Read Before You Trust a Number

| # | Limitation | Effect | How to spot it |
|---|---|---|---|
| L1 | **Active ≠ working** | Idle time with the laptop on counts as active and as overtime | First = `00:00` or very long days (> 12 h) |
| L2 | **Laptop stayed awake overnight** | A night counted as overtime | Active from late evening to early morning with no `Sleep` event |
| L3 | **No public holidays** | Holiday hours count as regular weekday time | Check your calendar for the range |
| L4 | **Log start** | The first day of the log can start at an odd time | First day of the range starts at `00:00`, or at the time the log starts |
| L5 | **Log rolled over** | Old days show as empty | Many empty days at the start of a long range |
| L6 | **Time zone = laptop clock** | Travel days show home time | You were abroad, and the clock stayed on home time |
| L7 | **Crash time = lower bound** | Real stop may be later | Large `Down h` values |

### Worked example of L1/L2

`2026-10-26 Mon | First 00:00 | Active 13.32 | OT 4.32`

| Period | Hours | Real? |
|---|---|---|
| 00:00 → 05:56 | 5.93 | ❌ Laptop awake overnight, no user |
| 05:56 → 09:55 | 3.99 (crash) | Laptop down |
| 09:55 → 17:18 | 7.38 | ✅ Real session |

The real work was about **7.4 h, with no overtime**. Correct this kind of day by hand until lock/unlock tracking is added (see the [Roadmap](05_HOW_IT_WORKS.md#7-roadmap)).

## 6. Quick Health Check

| Signal | Healthy | Look at |
|---|---|---|
| Avg active per weekday | ≤ 9 h | Daily table |
| Days > 12 h | 0 | Daily table |
| Last active after 21:00 | ≤ 2 per month | `Last` column |
| Weekend days used | ≤ 1 per month | Sat/Sun rows |
| Unclean shutdowns | 0 | KPI card |

The full proposal is in [USAGE_HEALTH_METRICS_PROPOSAL.md](USAGE_HEALTH_METRICS_PROPOSAL.md).
