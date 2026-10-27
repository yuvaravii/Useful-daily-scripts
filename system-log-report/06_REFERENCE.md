# 06 — Reference

Parameters, output files and every column.

← [05 How It Works](05_HOW_IT_WORKS.md) · [Back to README](../README.md)

---

## 1. Parameters

| Parameter | Type | Default | Example | Notes |
|---|---|---|---|---|
| `-StartDate` | `yyyy-MM-dd` | Asks. Enter = 1st of this month. | `2026-10-01` | Included in the range |
| `-EndDate` | `yyyy-MM-dd` | Asks. Enter = today. | `2026-10-31` | Included. A future date stops at "now". |
| `-StandardHours` | number | `9` | `8` | Weekday hours before overtime starts |
| `-MinActiveMinutes` | integer | `2` | `5` | Shortest active period that counts for First/Last |
| `-OutDir` | path | `<script folder>\uptime-report` | `"D:\Reports"` | Created if it does not exist |

## 2. Command Templates

```powershell
# Ask for dates
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1"

# Fixed range
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1" -StartDate 2026-10-01 -EndDate 2026-10-31

# All options
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1" -StartDate 2026-10-01 -EndDate 2026-10-31 -StandardHours 8 -MinActiveMinutes 5 -OutDir "D:\Reports"
```

## 3. Output Files

| File | One row per | Use it for |
|---|---|---|
| `daily_<start>_to_<end>.csv` | Day | Timesheets, overtime claims, Excel charts |
| `segments_<start>_to_<end>.csv` | State period | Checking one specific day minute by minute |
| `crashes_<start>_to_<end>.csv` | Unclean shutdown | IT tickets, battery diagnosis |
| `summary_<start>_to_<end>.csv` | Range | Monthly totals |
| `report_<start>_to_<end>.html` | — | Reading and sharing (as a screenshot) |

## 4. Columns — `daily_*.csv`

| Column | Type | Description |
|---|---|---|
| `Date` | `yyyy-MM-dd` | Calendar day |
| `Day` | text | `Mon` … `Sun` |
| `DayType` | text | `Weekday` or `Weekend` |
| `FirstActive` | `HH:mm` | Start of the first active period ≥ `MinActiveMinutes` |
| `LastActive` | `HH:mm` | End of the last active period. `24:00` = active at midnight. |
| `ActiveHours` | hours | Laptop on, not in standby |
| `RegularHours` | hours | Active hours inside the standard day |
| `OvertimeHours` | hours | See [05 §6](05_HOW_IT_WORKS.md#6-formulas) |
| `CrashHours` | hours | Down after an unclean stop |
| `StandbyHours` | hours | Modern Standby |
| `OffHours` | hours | Sleep, hibernate, clean shutdown |
| `Boots` | count | Boots that day |
| `Crashes` | count | Crash start times that day |
| `UpdateRestart` | `Yes` / empty | Windows Update restart that day |
| `Events` | text | Timeline, for example `Wake 08:14; Crash 10:30; Boot 11:15` |

## 5. Columns — `segments_*.csv`

| Column | Description |
|---|---|
| `Start`, `End` | `yyyy-MM-dd HH:mm:ss` |
| `State` | `AWAKE`, `STANDBY`, `OFF`, `CRASH` |
| `Hours` | End − Start |

## 6. Columns — `crashes_*.csv`

| Column | Description |
|---|---|
| `LastSeen` | Newest System event before the boot (the crash time) |
| `BootTime` | The boot that logged Kernel-Power 41 |
| `DownHours` | BootTime − LastSeen |
| `Cause` | See [05 §4](05_HOW_IT_WORKS.md#4-crash-detection) |
| `BugcheckCode`, `PowerButtonTimestamp`, `SleepInProgress` | Raw Event 41 fields |

## 7. Columns — `summary_*.csv`

| Column | Description |
|---|---|
| `Range`, `From`, `Until` | Requested range and the actual end time |
| `DaysInRange`, `ActiveDays` | Day counts |
| `ActiveHours`, `CrashHours`, `StandbyHours` | Totals |
| `StandardHoursPerWeekday` | Value of `-StandardHours` |
| `RegularHours`, `OvertimeHours` | Totals |
| `WeekdayOvertime`, `WeekendOvertime` | Overtime split |
| `OvertimeDays` | Days with overtime > 0 |
| `AvgActivePerActiveDay` | ActiveHours ÷ ActiveDays |
| `UncleanShutdowns`, `UpdateRestarts` | Counts |
| `Computer`, `TimeZone`, `GeneratedAt` | Context |

## 8. Glossary

| Term | Meaning |
|---|---|
| **Modern Standby** | A low-power state on new laptops (S0ix). The screen is off, and the network can stay on. |
| **Sleep / Hibernate** | A deeper power state (S3/S4). The clock stops. |
| **Unclean shutdown** | The laptop stopped without Windows shutting down normally |
| **Bugcheck** | Blue screen |
| **Event ID** | The number Windows gives each type of log entry |
