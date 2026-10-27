# IMPLEMENTATION_REPORT — Monthly System Uptime Log (Windows)

- **Date:** 2026-10-26
- **Deliverable:** `Get-MonthlyUptime.ps1` (PowerShell, Windows PowerShell 5.1+ / PowerShell 7)
- **Request:** Script that logs, per month: date, month, start date, start per day, start/end time, hours the system was running.

---

## 1. Summary

- Reads power events from the Windows **System event log**. No background service. No admin rights expected.
- Builds **sessions** (ON → OFF), splits them **per day**, and writes three CSV files plus console output.
- Re-running for the same month **regenerates** the files from the event log (idempotent).

| Event | Provider | ID | Meaning |
|---|---|---|---|
| ON | Microsoft-Windows-Kernel-General | 12 | OS boot |
| ON | Microsoft-Windows-Power-Troubleshooter | 1 | Wake from sleep / hibernate |
| OFF | Microsoft-Windows-Kernel-General | 13 | OS shutdown |
| OFF | Microsoft-Windows-Kernel-Power | 42 | Enter sleep / hibernate |

## 2. Files Changed

| File | Status | Purpose |
|---|---|---|
| `Get-MonthlyUptime.ps1` | New | Script |
| `IMPLEMENTATION_REPORT.md` | New | This report |

- Output (created at run time) in `uptime-logs\` next to the script:
  - `sessions_<yyyy-MM>.csv` — Start, End, Hours, StartReason, EndReason
  - `daily_<yyyy-MM>.csv` — Date, Day, Month, FirstStart, LastEnd, Sessions, HoursOn, SpanHours
  - `summary_<yyyy-MM>.csv` — Month, MonthStartDate, ReportUntil, DaysCovered, ActiveDays, TotalHoursOn, AvgHoursPerActiveDay, Sessions, UncleanStops, Computer, GeneratedAt, Warning

## 3. Behaviour Changes

- New tool. No existing behaviour changed.
- Usage:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Get-MonthlyUptime.ps1              # current month
  powershell -ExecutionPolicy Bypass -File .\Get-MonthlyUptime.ps1 -Month 2026-09
  powershell -ExecutionPolicy Bypass -File .\Get-MonthlyUptime.ps1 -OutDir D:\logs
  ```
- Rules:
  - **HoursOn** = sum of ON time in that day. Sleep time is **not** counted.
  - **SpanHours** = LastEnd − FirstStart (includes breaks / sleep).
    - Example: ON 09:00–13:00, sleep, ON 14:00–18:00 → HoursOn 8.0, SpanHours 9.0.
  - Session crossing midnight → split across both days. `LastEnd = 24:00` means still on at midnight.
  - Session crossing month edge → clipped to the month.
  - Current session (current month) → ends at "now", EndReason `Running now`.
  - Crash / power cut (ON with no OFF) → end = last System event > 2 min before next boot, EndReason `Unclean (estimated)`.
  - Two ON events < 120 s apart → treated as one start.

## 4. Tests Performed

| Test | Result | Basis |
|---|---|---|
| Run on Windows | **Not done** | No Windows / PowerShell runtime in build environment |
| PowerShell syntax parse | **Not done** | `pwsh` not available |
| Code review of logic (session build, midnight split, month clip) | Done | Read |

- **Required before trust:** run on the target laptop and compare 2–3 days against memory / Event Viewer.
  - Event Viewer → Windows Logs → System → Filter Current Log → IDs `12,13,42,1`.

## 5. Assumptions

- **Inferred:** Event IDs above are present on Windows 10/11 by default. Not verified on the target machine.
- **Assumed:** With **Fast Startup** on, a "shutdown" + power-on logs Kernel-General 13 then 12 and/or Power-Troubleshooter 1. Not verified. The 120 s merge window handles a double ON.
- **Assumed:** Reading the System log needs no admin rights (default Windows ACL).
- **Assumed:** Laptop local time zone is the reporting time zone.

## 6. Decisions Made

- **PowerShell over Python** — built into Windows, no install, direct `Get-WinEvent` access.
- **Event log over a running logger** — gives history back to log retention; no task to keep alive.
- **CSV output** — opens in Excel; easy to feed into another tool.
- **Sleep = OFF** — "system running" read as "awake and usable".

## 7. Risks

- **Log retention:** System log is size-capped (default ~20 MB). Old months may be partly lost.
  - Mitigation in code: warning printed + `Warning` column when log starts after month start.
  - Mitigation outside code: increase log size, or schedule the script monthly (see §8).
- **Unclean stops** are estimates; crash-then-quick-reboot (< 2 min) may under-count.
- **Modern Standby (S0)** laptops may log sleep/wake differently → sessions may look longer. Not verified.
- **Day name / month name** use system culture (e.g. Japanese locale gives `月`).

## 8. Suggested Follow-up Tasks

1. Run on the laptop; validate against Event Viewer for 3 days.
2. Add a Task Scheduler entry (e.g. daily 23:55) so data is captured before log rollover.
3. Option: raise System log max size (`wevtutil sl System /ms:104857600`) — needs admin.
4. Option: idle/lock detection (Security log 4800/4801) if "working hours" ≠ "machine on".

## 9. Questions

1. Should this go into the existing `E:\github-personal\system log generator` repo, or stay standalone?
2. Is **sleep** = not running (current choice)? Or should sleep count as ON time?
3. Should locked-screen time be excluded (needs follow-up task 8.4)?
4. CSV enough, or do you want an Excel/HTML monthly view on top?

---
---

# IMPLEMENTATION_REPORT — v2: `Get-UptimeReport.ps1` (2026-10-26)

## 1. Summary

- This is a PowerShell port of the analysis that was run on `system_power_log.csv` (1–26 Oct). It reads the live System log directly.
- **It replaces the logic of v1 (`Get-MonthlyUptime.ps1`). The v1 file is kept and not deleted.**
- New in v2:
  - Real wake time from clock jumps
  - Modern Standby hours
  - Crash detection with the cause
  - Windows Update restarts
  - HTML report

## 2. Files Changed

| File | Status | Purpose |
|---|---|---|
| `Get-UptimeReport.ps1` | New | v2 script |
| `IMPLEMENTATION_REPORT.md` | Appended | This section. The v1 section is unchanged. |
| `Get-MonthlyUptime.ps1` | Unchanged | Superseded. See the v1 defects below. |

- Outputs are written to `uptime-report\`:
  - `daily_`, `segments_`, `crashes_` and `summary_<yyyy-MM>.csv`
  - `report_<yyyy-MM>.html` (opens automatically)

## 3. Behaviour Changes (v1 → v2)

| Topic | v1 | v2 |
|---|---|---|
| Wake time | Power-Troubleshooter 1 (logged only 3× in Oct → most wakes missed) | Clock jump (Kernel-General 1, NewTime − OldTime > 5 min) |
| Modern Standby | Ignored (counted as on) | Separate **Standby** hours (506/507) |
| Crash detection | ON after ON with no OFF | Kernel-Power 41 at boot |
| Crash time | Last event > 2 min before boot | Last System event before boot |
| Crash cause | — | BugcheckCode / PowerButtonTimestamp / SleepInProgress from Event 41 |
| Updates | — | User32 1074 by MoUsoCoreWorker / TrustedInstaller |

## 4. How Each Number Is Calculated

1. **Segments:** sort all state-change events by time. Each gap between two events gets the state of the earlier event (Awake / Standby / Off).
2. **Per day:** split each segment at midnight. Sum the hours per state.
3. **First / Last Active:** the start of the first, and the end of the last, Awake segment that is ≥ 2 min long.
4. **Crash:** a boot with Kernel-Power 41 means Windows did not shut down cleanly. The crash time is the newest System event before that boot.
5. **Cause rules (in order):**
   - BugcheckCode ≠ 0 → blue screen
   - PowerButtonTimestamp ≠ 0 → power button held
   - SleepInProgress → lost power during sleep
   - Else → freeze or power loss

## 5. Tests Performed

| Test | Result | Basis |
|---|---|---|
| Logic on the 1–26 Oct export (Python prototype) | 184.9 h awake, 51.2 h standby, 12 crashes | Verified on the CSV |
| PowerShell run on Windows | **Not done** | No Windows runtime available |
| Crash-cause classification | **Not done** | Event 41 fields were not in the export |

- **Expected differences from the CSV analysis:**
  - Crash "last seen" can be **later**, because v2 reads the full System log and not only the 12 exported IDs.
  - Awake hours can be slightly higher for that reason.

## 6. Assumptions

- **Inferred:** the Kernel-General 1 data fields are named `NewTime` and `OldTime`. Not verified on the target machine. If they are missing, no wakes are found and awake hours become too high.
- **Inferred:** the Event 41 field names (`BugcheckCode`, `PowerButtonTimestamp`, `SleepInProgress`, `LongPowerButtonPressDetected`) match Windows 10/11.
- **Assumed:** the state before the first event in the 14-day look-back is Awake.

## 7. Risks

- Laptops without Modern Standby have no 506/507 events, so standby hours = 0. The logic still works.
- A clock jump caused by a manual time change or a time-zone change looks like a sleep.
  - Example: changing the clock to JST in Japan → about 3.5 h shown as "off".
- 6008 times are ignored on purpose. They conflicted with the log (6 Oct: crash reported at 12:39 for a 09:43 boot).

## 8. Suggested Follow-up Tasks

1. Run on the laptop and compare the result with `daily_2026-10.csv` from the CSV analysis.
2. Read the crash causes. If they show "Power button held" or "Blue screen", open a hardware/driver ticket.
3. Option: lock/unlock (Security 4800/4801) for "user active" hours. Needs admin.

## 9. Questions

1. Should v1 (`Get-MonthlyUptime.ps1`) be marked deprecated in the repo, or removed by you?
2. Which repo is the target: `system log generator`, or standalone?

---
---

# IMPLEMENTATION_REPORT — v2.1: Date-Range Input (2026-10-26)

## 1. Summary

- `Get-UptimeReport.ps1` now takes a **start date** and an **end date** (both inclusive) instead of `-Month`.
- If the dates are not given as parameters, the script **asks** for them (Read-Host). Press Enter to accept the default.

## 2. Files Changed

| File | Change |
|---|---|
| `Get-UptimeReport.ps1` | `-Month` replaced by `-StartDate` and `-EndDate`, plus prompts. The range is used everywhere the month was used. |
| `IMPLEMENTATION_REPORT.md` | This section appended |

## 3. Behaviour Changes

- Usage:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Get-UptimeReport.ps1 -StartDate 2026-10-01 -EndDate 2026-10-26
  powershell -ExecutionPolicy Bypass -File .\Get-UptimeReport.ps1      # asks for both dates
  ```
- Defaults when Enter is pressed:
  - Start date = first day of the current month
  - End date = today
- File names: `<type>_<start>_to_<end>.csv/.html`
  - Example: `daily_2026-10-01_to_2026-10-26.csv`
- Summary: the `Month` column is replaced by `Range`, and a `DaysInRange` column is added.
- `UpdateRestarts` is now limited to the range. In v2 it had no upper bound (fixed).
- Validation errors:
  - Wrong date format
  - End date before the start date
  - Start date in the future
- An end date in the future is allowed. The report stops at "now".
- **Breaking:** `-Month` no longer exists.

## 4. Tests Performed

- **Not run.** No Windows runtime is available. The edits were checked by reading the code.

## 5. Assumptions

- The input format is strictly `yyyy-MM-dd`. This avoids DD/MM versus MM/DD confusion between Windows locales.

## 6. Risks

- Long ranges (several months) make more `Get-WinEvent` calls, so the script runs slower.
- The System log size cap can still drop old data. There is no range warning yet.

## 7. Suggested Follow-up

1. Add a warning when the oldest System event is later than the start date. This existed in v1 but was not carried into v2.

## 8. Questions

1. Should the `-Month` parameter be added back as a shortcut, alongside the dates?

---
---

# IMPLEMENTATION_REPORT — v2.2: Active Hours and Crash Hours per Day (2026-10-26)

## 1. Summary

- Each day now shows **ActiveHours** and **CrashHours**.
- There is a new state, **CRASH**. It runs from the last sign of life before an unclean stop until the next boot. Before this change, that time was counted as OFF.

## 2. Files Changed

| File | Change |
|---|---|
| `Get-UptimeReport.ps1` | New CRASH state. Columns renamed or added. HTML bar has a red crash segment. Console table updated. |
| `IMPLEMENTATION_REPORT.md` | This section appended |

## 3. Behaviour Changes

- `daily_*.csv` columns:
  - `AwakeHours` is renamed to **`ActiveHours`**. **Breaking** for anything that reads the old column.
  - New columns: **`CrashHours`** and `OffHours` (time in sleep or after a clean shutdown).
  - The four hour columns add up to 24 h for a full day (Active + Standby + Crash + Off). The current day stops at "now".
- `summary_*.csv`:
  - `AwakeHours` is renamed to `ActiveHours`.
  - New column: `CrashHours`.
  - `AvgAwakePerActive` is renamed to `AvgActivePerActiveDay`.
- Timeline rule: while the state is CRASH, Sleep and Shutdown events are ignored until the next boot.

## 4. Expected Result for 1–26 Oct (from the CSV analysis)

- Active hours total: 184.9 h. Crash hours total: 132.0 h.
- **CrashHours means the laptop was down after an unclean stop.** It is not lost work time.
  - Example: the 3–4 Oct crash covers the night and most of Sunday, which gives 14.2 h + 18.1 h.

## 5. Tests Performed

- The expected values were calculated in Python from the uploaded CSV. The PowerShell script was not run, because no Windows runtime is available.

## 6. Questions

1. Should "crash hours" be limited to working hours (for example 09:00–18:00), so that overnight down time is not counted?

---
---

# IMPLEMENTATION_REPORT — v2.3: Overtime Calculation (2026-10-26)

## 1. Summary

- Overtime is now calculated automatically for any date range.
- **Rules (as RJ stated them):**
  - Mon–Fri: overtime = ActiveHours above **9 h**.
  - Sat/Sun: overtime = **all** ActiveHours.

## 2. Files Changed

| File | Change |
|---|---|
| `Get-UptimeReport.ps1` | New `-StandardHours` parameter (default 9). New daily columns: `DayType`, `RegularHours`, `OvertimeHours`. New summary fields. New HTML KPIs and columns. Console table updated. |
| `IMPLEMENTATION_REPORT.md` | This section appended |

- Base version: v2.2 (ActiveHours + CrashHours).
  - The attached file is v2.1 (`AwakeHours`, no CrashHours). v2.3 keeps everything that v2.1 has.

## 3. Behaviour Changes

- Daily formulas:
  ```text
  Weekday: RegularHours = min(ActiveHours, 9)   OvertimeHours = max(ActiveHours - 9, 0)
  Weekend: RegularHours = 0                     OvertimeHours = ActiveHours
  ```
- New summary fields: `StandardHoursPerWeekday`, `RegularHours`, `OvertimeHours`, `WeekdayOvertime`, `WeekendOvertime`, `OvertimeDays`.
- HTML report:
  - Overtime is shown in orange.
  - KPI cards: total OT, weekday OT and weekend OT.
- To change the standard day, use `-StandardHours 8`.

## 4. Expected Result for 1–26 Oct (Python on the uploaded CSV)

| Metric | Value |
|---|---|
| Active hours | 184.87 |
| Regular hours | 150.89 |
| **Overtime hours** | **33.98** |
| Weekday OT | 25.06 |
| Weekend OT | 8.92 |
| Days with OT | 19 |

## 5. Tests Performed

- The expected values above were calculated in Python. The PowerShell script was not run, because no Windows runtime is available.

## 6. Assumptions

- **Active hours = laptop on and not in standby.** This is not proof of work. Idle time while the screen is on counts as active.
- The day boundary is midnight in local time. Work that continues past midnight counts toward the next day.

## 7. Risks

- **Public holidays are not handled.** A weekday holiday is treated as a normal weekday.
  - Earlier context: the overtime calendar should be the Japan HQ company holiday calendar. RJ has not uploaded it yet.
- 1 Oct includes about 0.4 h from the start of the log (01:35–01:59). This adds about 0.33 h of OT on 1 Oct, which is an artifact.

## 8. Suggested Follow-up

1. Add `-HolidayFile <csv>`, so that listed dates are treated like weekends (all active hours = OT).

## 9. Questions

1. Should company holidays count as weekend days (all hours = OT)?
2. Is the 9 h limit inclusive of lunch break, or should a break be subtracted?

---
---

# IMPLEMENTATION_REPORT — v2.3-docs: Repository Documentation Set (2026-10-27)

## 1. Summary

- This adds a documentation set for publishing on GitHub. The README is the single entry point, and each docs page links back to it.
- There are no code changes.

## 2. Files Changed

| File | Status | Purpose |
|---|---|---|
| `README.md` | New | Entry point: a "which guide do I need" table, a 30-second run, the repository layout |
| `docs/01_SETUP.md` | New | First-time setup, step by step |
| `docs/02_RUN_CHECKLIST.md` | New | Checklist for before, during and after every run |
| `docs/03_READING_THE_REPORT.md` | New | Meaning of every number, limitations L1–L7, worked example |
| `docs/04_TROUBLESHOOTING.md` | New | Error → cause → fix tables, device checks |
| `docs/05_HOW_IT_WORKS.md` | New | Event IDs, rules R1–R6, formulas, roadmap |
| `docs/06_REFERENCE.md` | New | Parameters, files, all columns, glossary |
| `.gitignore` | New | Keeps reports, CSV files, logs and diagnostics out of git |
| `legacy/Get-MonthlyUptime.ps1` | Moved (copy) | v1, replaced. Kept, not deleted. |
| `docs/IMPLEMENTATION_REPORT.md` | Moved + appended | Change history |
| `docs/USAGE_HEALTH_METRICS_PROPOSAL.md` | Moved | Health proposal |

## 3. Tests Performed

| Test | Result |
|---|---|
| All relative links and `#anchors` resolve | Pass (scripted check) |
| Script has ASCII only (safe to save in Notepad) | Pass |
| Rendering on GitHub | Not checked |

## 4. Assumptions

- The script is placed in `C:\Scripts`. All commands in the docs use this path.
- The documented error messages are the ones seen during setup on TSI005. Their wording can change between PowerShell versions.

## 5. Questions

1. Licence: none added. Should it be MIT?
2. Target repository: the existing `system log generator`, or a new one?
