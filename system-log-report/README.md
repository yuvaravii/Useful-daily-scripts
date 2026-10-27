# Windows Uptime & Overtime Report

This tool reads the Windows **System event log** and reports, per day, when the laptop was **active**, in **standby**, or **down after a crash**. It also calculates **overtime**. You can run it for any date range.

- One PowerShell script. Nothing to install. No admin rights.
- Output: CSV files and an HTML report that works offline.

---

## Start Here — Which Guide Do I Need?

| I want to… | Open |
|---|---|
| Run the script for the first time | [docs/01_SETUP.md](docs/01_SETUP.md) |
| Run a report (every time) | [docs/02_RUN_CHECKLIST.md](docs/02_RUN_CHECKLIST.md) |
| Understand the numbers in the report | [docs/03_READING_THE_REPORT.md](docs/03_READING_THE_REPORT.md) |
| Fix an error | [docs/04_TROUBLESHOOTING.md](docs/04_TROUBLESHOOTING.md) |
| Know how the script calculates everything | [docs/05_HOW_IT_WORKS.md](docs/05_HOW_IT_WORKS.md) |
| Look up a parameter or output column | [docs/06_REFERENCE.md](docs/06_REFERENCE.md) |
| See the change history | [docs/IMPLEMENTATION_REPORT.md](docs/IMPLEMENTATION_REPORT.md) |
| See planned health metrics | [docs/USAGE_HEALTH_METRICS_PROPOSAL.md](docs/USAGE_HEALTH_METRICS_PROPOSAL.md) |

---

## 30-Second Version

1. Put `Get-UptimeReport.ps1` in `C:\Scripts`.
2. Open **PowerShell**.
3. Paste this command as **one line** and press **Enter**:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1" -StartDate 2026-10-01 -EndDate 2026-10-31
```

4. The HTML report opens in your browser. All files are in `C:\Scripts\uptime-report\`.

> **Rules to remember**
> - Dates are always `yyyy-MM-dd`, for example `2026-10-01`.
> - Paste the command as **one line**. Do not put `cd` in front of it on the same line.
> - "Active" means **laptop on**. It does not prove that you worked. See [Limitations](docs/03_READING_THE_REPORT.md#5-limitations--read-before-you-trust-a-number).

---

## What You Get

| Per day | Per range |
|---|---|
| First / last active time | Active days, total active hours |
| Active, regular, overtime hours | Total, weekday and weekend overtime |
| Crash hours, standby hours, off hours | Unclean shutdowns, with the likely cause |
| Boots, crashes, update restarts | Windows Update restarts |
| A readable event timeline | Average active hours per active day |

## Overtime Rules (default)

| Day | Overtime |
|---|---|
| Mon–Fri | Active hours **above 9 h** (change with `-StandardHours`) |
| Sat–Sun | **All** active hours |

## Repository Layout

```text
.
├── Get-UptimeReport.ps1          # the script
├── README.md                     # this file - start here
├── .gitignore                    # keeps personal reports out of git
├── docs/
│   ├── 01_SETUP.md               # first-time setup
│   ├── 02_RUN_CHECKLIST.md       # every-run checklist
│   ├── 03_READING_THE_REPORT.md  # what each number means
│   ├── 04_TROUBLESHOOTING.md     # errors and fixes
│   ├── 05_HOW_IT_WORKS.md        # event IDs, rules, formulas
│   ├── 06_REFERENCE.md           # parameters, columns, files
│   ├── IMPLEMENTATION_REPORT.md  # change history
│   └── USAGE_HEALTH_METRICS_PROPOSAL.md
└── legacy/
    └── Get-MonthlyUptime.ps1     # v1, replaced - do not use
```

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1, or PowerShell 7
- Read access to the System log (the default for any user)

## Privacy

Reports contain your **computer name** and a detailed **timeline of when you used your laptop**. **Do not commit them.** The `.gitignore` in this repository already excludes `uptime-report/`, `*.csv` and `report_*.html`.

## Status

- **Version:** v2.3 (date range, crash hours, overtime)
- **Tested on:** one laptop with Modern Standby, India Standard Time
- **Known gaps:** public holidays are not handled. Active hours can include nights when the laptop stayed awake. See [docs/03_READING_THE_REPORT.md §5](docs/03_READING_THE_REPORT.md#5-limitations--read-before-you-trust-a-number).
