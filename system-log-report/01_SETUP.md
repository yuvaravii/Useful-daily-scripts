# 01 — First-Time Setup

Do this **once** per laptop. It takes about 5 minutes.

← [Back to README](../README.md) · Next: [02 Run Checklist](02_RUN_CHECKLIST.md)

---

## 1. Check Your Windows Version

1.1. Press `Win + R`, type `winver` and press **Enter**.
1.2. Make sure the window says **Windows 10** or **Windows 11**.

## 2. Make the Script Folder

2.1. Open **File Explorer**.
2.2. Go to `C:\`.
2.3. Make a new folder and name it `Scripts`.

- Result: `C:\Scripts`

## 3. Download the Script

3.1. Download `Get-UptimeReport.ps1` from this repository.
   - On GitHub: open the file, click **Download raw file** (the ⤓ icon).
3.2. Move the file into `C:\Scripts`.

### 3.3 Check the file name — important

Windows can hide file extensions. A file that looks correct can be `Get-UptimeReport.ps1.txt`.

3.3.1. In File Explorer, click **View** → **Show** → **File name extensions**.
3.3.2. Make sure the name is exactly `Get-UptimeReport.ps1`.
3.3.3. If the name ends in `.txt`, rename the file and remove `.txt`.

### 3.4 If you copy the script from a web page into Notepad

3.4.1. Paste the full script into Notepad.
3.4.2. Click **File** → **Save As**.
3.4.3. Set **Save as type** to **All files (\*.\*)**.
3.4.4. Set **Encoding** to **UTF-8**.
3.4.5. Set **File name** to `C:\Scripts\Get-UptimeReport.ps1`.

## 4. Open PowerShell

4.1. Press the **Start** key and type `PowerShell`.
4.2. Click **Windows PowerShell**. You do **not** need "Run as administrator".

## 5. Check That PowerShell Can See the File

Type this and press **Enter**:

```powershell
dir C:\Scripts
```

- **Expected:** `Get-UptimeReport.ps1` is in the list.
- **Not there?** Go back to step 3.

## 6. Do a Test Run

Paste this as **one line** and press **Enter**:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1"
```

6.1. At `Start date`, press **Enter** to use the first day of this month.
6.2. At `End date`, press **Enter** to use today.
6.3. Wait. Reading the log can take 10–60 seconds.

### Expected result

- A cyan line: `Reading System log ...`
- A table, one row per day
- A **Summary** block
- `Files written:` followed by 5 paths
- The HTML report opens in your browser

**If you see red text:** go to [04 Troubleshooting](04_TROUBLESHOOTING.md).

## 7. Optional — Make a Shortcut

Create a file `C:\Scripts\Run-UptimeReport.bat` that contains this line:

```bat
powershell -NoExit -ExecutionPolicy Bypass -File "C:\Scripts\Get-UptimeReport.ps1"
```

- Double-click the file to run the report. It asks for the dates.
- `-NoExit` keeps the window open, so you can read the result.

## 8. Optional — Keep More Log History

By default, Windows keeps about 20 MB of System log. On a busy laptop, that is a few weeks. To keep more:

8.1. Open PowerShell **as Administrator**.
8.2. Run:

```powershell
wevtutil sl System /ms:104857600   # 100 MB
```

---

✅ Setup is complete. From now on, use [02 Run Checklist](02_RUN_CHECKLIST.md) every time.
