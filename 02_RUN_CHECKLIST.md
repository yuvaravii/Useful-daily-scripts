# 02 — Run Checklist (Every Time)

Follow this list each time you make a report.

← [01 Setup](01_SETUP.md) · [Back to README](../README.md) · Next: [03 Reading the Report](03_READING_THE_REPORT.md)

---

## Before You Run

- [ ] The script is at `C:\Scripts\Get-UptimeReport.ps1` (setup is done).
- [ ] You know the **start date** and the **end date** in `yyyy-MM-dd` format.
- [ ] You know your **standard day**: 9 h is the default.
- [ ] Laptop time zone is correct (**Settings → Time & language → Date & time**).

## Run

### 1. Open PowerShell

Press **Start**, type `PowerShell`, and press **Enter**.

### 2. Paste one command (one line)

Pick the command that matches what you need:

| Need | Command |
|---|---|
| A specific range | `powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1" -StartDate 2026-10-01 -EndDate 2026-10-31` |
| This month up to today | `powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1"` then press **Enter** twice |
| Last week (Mon–Sun) | `powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1" -StartDate 2026-10-19 -EndDate 2026-10-25` |
| 8 h standard day | add `-StandardHours 8` to the end |
| Save somewhere else | add `-OutDir "D:\Reports"` to the end |

> ⚠️ **Do not** type `cd C:\Scripts` and the command on the same line. Use the full path in quotes, as shown above.

### 3. Wait for the result

| You see | Meaning |
|---|---|
| `Reading System log ...` (cyan) | The script is working |
| Daily table | Done reading |
| `Unclean shutdowns:` (yellow) | One or more crashes in the range |
| `Files written:` + 5 paths | Success |
| Red text | Error. See [04 Troubleshooting](04_TROUBLESHOOTING.md). |

## After You Run

- [ ] The HTML report opened. If it did not, open `C:\Scripts\uptime-report\report_<start>_to_<end>.html`.
- [ ] **First / Last active looks right?** Compare with your memory for 2–3 days.
- [ ] **Look for days with 00:00 as First Active.** The laptop stayed on from the day before. Check whether this time is real work.
- [ ] **Look at the red rows (crashes).** Read the cause in the *Unclean shutdowns* table.
- [ ] **Public holidays** in the range? Correct them by hand. The script treats them as weekdays.
- [ ] Before sharing, read [03 §5 Limitations](03_READING_THE_REPORT.md#5-limitations--read-before-you-trust-a-number).

## Where the Files Are

```text
C:\Scripts\uptime-report\
├── daily_<start>_to_<end>.csv
├── segments_<start>_to_<end>.csv
├── crashes_<start>_to_<end>.csv
├── summary_<start>_to_<end>.csv
└── report_<start>_to_<end>.html
```

- Running the same range again **overwrites** these files.
- A different range makes new files.

## Recommended Rhythm

| When | Range | Why |
|---|---|---|
| Every Friday evening | Mon → Fri | Catch long days early |
| First working day of the month | Full previous month | Monthly overtime total |
| After any crash | Last 7 days | See the crash cause while the log still has it |
