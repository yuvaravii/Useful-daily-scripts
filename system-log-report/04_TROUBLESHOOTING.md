# 04 — Troubleshooting

Find your error message in the table, then follow the fix.

← [03 Reading the Report](03_READING_THE_REPORT.md) · [Back to README](../README.md) · Next: [05 How It Works](05_HOW_IT_WORKS.md)

---

## 1. Errors When Starting the Script

| Error text (part of it) | Cause | Fix |
|---|---|---|
| `running scripts is disabled on this system` | Windows blocks scripts by default | Use `powershell -ExecutionPolicy Bypass -File "..."` exactly as shown in [02](02_RUN_CHECKLIST.md) |
| `The argument '...ps1' to the -File parameter does not exist` | Wrong path or wrong file name | See [§2](#2-file-not-found) |
| `A parameter cannot be found that matches parameter name 'ExecutionPolicy'` | `cd C:\Scripts` and the command were pasted on **one line** | Paste only the full command, with the path in quotes |
| `Could not find a part of the path '...\Desktop\...'` | Desktop is redirected to OneDrive | Add `-OutDir "C:\Scripts\uptime-report"` |
| `... cannot be loaded. The file ... is not digitally signed` | File is blocked because it was downloaded | Run `Unblock-File "C:\Scripts\Get-UptimeReport.ps1"`, then run again |
| `Unexpected token` / `Missing closing '}'` | The script was copied only in part, or saved with the wrong encoding | Download the file again. If you use Notepad, save as UTF-8 ([01 §3.4](01_SETUP.md#34-if-you-copy-the-script-from-a-web-page-into-notepad)). |

## 2. File Not Found

2.1. Find every copy of the script:

```powershell
Get-ChildItem -Path $env:USERPROFILE -Filter "Get-UptimeReport*" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, LastWriteTime
```

2.2. Pick the **newest** copy.
2.3. Copy it to the correct place:

```powershell
New-Item -ItemType Directory -Path C:\Scripts -Force | Out-Null
Copy-Item "<FULL PATH FROM 2.1>" "C:\Scripts\Get-UptimeReport.ps1" -Force
```

2.4. Run again.

## 3. Errors While the Script Runs

| Error text | Cause | Fix |
|---|---|---|
| `Invalid date '...'. Use yyyy-MM-dd` | Wrong date format | Use `2026-10-01`, not `01-10-2026` or `10/1/2026` |
| `End date ... is before start date` | Dates swapped | Swap `-StartDate` and `-EndDate` |
| `Start date ... is in the future` | Typo in the year or month | Correct the date |
| `Access is denied` on the output folder | No write permission | Use `-OutDir` with a folder you own, for example `"$env:USERPROFILE\Documents\uptime-report"` |

## 4. Wrong or Strange Results

| Symptom | Likely cause | Check / fix |
|---|---|---|
| Very high active hours on one day | Laptop stayed awake overnight ([03 L2](03_READING_THE_REPORT.md#5-limitations--read-before-you-trust-a-number)) | Look for `First = 00:00`. Correct the day by hand. |
| Many days with 0 active at the start of a long range | The System log rolled over | Check the oldest event: `(Get-WinEvent -LogName System -Oldest -MaxEvents 1).TimeCreated` |
| No standby hours at all | Laptop has no Modern Standby (uses S3 sleep) | Normal. Standby hours stay at 0. |
| Sleep shown for a few hours when you changed time zone | A clock change looks like sleep/wake | Expected. Ignore that period. |
| Overtime on a public holiday is too low | Holidays are not supported | Correct by hand |
| HTML did not open | No default browser, or a policy blocks it | Open `report_*.html` by hand from the output folder |
| Script is slow (> 2 min) | Long range or large log | Normal. Use a shorter range. |

## 5. Device Checks for Crashes

When the report shows many **"Lost power during sleep"** crashes, run these built-in Windows reports:

```powershell
# Battery health - capacity and drain history (normal PowerShell)
powercfg /batteryreport /output "$env:USERPROFILE\Desktop\battery.html"
```

```powershell
# Standby drain - what keeps the laptop awake (PowerShell as Administrator)
powercfg /sleepstudy /output "$env:USERPROFILE\Desktop\sleepstudy.html"
```

| Report | Look for | Meaning |
|---|---|---|
| battery.html | **Full charge capacity** much lower than **Design capacity** | Worn battery |
| sleepstudy.html | High **% drain per hour** in a session | An app or device keeps the laptop busy in standby |
| sleepstudy.html | Top offenders list | The component to update or disable |

## 6. Still Stuck?

Open a GitHub issue. Include:

- The full command you ran
- The full red error text
- Output of `$PSVersionTable.PSVersion`
- Output of `winver`, as text

> Do **not** attach your reports. They contain your usage timeline.
