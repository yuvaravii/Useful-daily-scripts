<#
.SYNOPSIS
    Laptop uptime report for a date range from the Windows System event log (v2).

.DESCRIPTION
    Rebuilds, per day: first active, last active, active hours, regular hours, overtime hours, crash hours, standby hours, off hours,
    boots, sleeps, wakes, crashes (with cause) and Windows Update restarts.

    Outputs (folder "uptime-report" next to the script):
      daily_<start>_to_<end>.csv     one row per day
      segments_<start>_to_<end>.csv  every Awake / Standby / Off period
      crashes_<start>_to_<end>.csv   every unclean shutdown + likely cause
      summary_<start>_to_<end>.csv   one row for the whole range
      report_<start>_to_<end>.html   visual report (open in browser)

    RULES (see IMPLEMENTATION_REPORT.md for detail)
      ACTIVE  (AWAKE) starts at : Boot (Kernel-General 12), real wake (clock jump, Kernel-General 1),
                          Modern Standby exit (Kernel-Power 507)
      STANDBY starts at : Modern Standby enter (Kernel-Power 506)
      OFF     starts at : Sleep/Hibernate (Kernel-Power 42), Shutdown (Kernel-General 13),
      CRASH   starts at : last System event before a boot that has Kernel-Power 41; ends at that boot
      - Kernel-Power 107 ("resumed from sleep") is NOT used: it is logged with the frozen clock.
      - 506 + 507 in the same second = momentary wake -> state does not change.
      - Awake periods shorter than -MinActiveMinutes are ignored for First/Last Active.

.PARAMETER StartDate
    First day of the report (inclusive), format yyyy-MM-dd.
    If not given, the script asks. Press Enter for the first day of the current month.

.PARAMETER EndDate
    Last day of the report (inclusive), format yyyy-MM-dd.
    If not given, the script asks. Press Enter for today.

.PARAMETER OutDir
    Output folder. Default: "uptime-report" next to the script.

.PARAMETER MinActiveMinutes
    Minimum awake period (minutes) that counts for First/Last Active. Default 2.

.PARAMETER StandardHours
    Normal working hours per weekday (Mon-Fri). Default 9.
    Weekday overtime = ActiveHours above this. Weekend (Sat/Sun) overtime = all ActiveHours.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-UptimeReport.ps1
    powershell -ExecutionPolicy Bypass -File .\Get-UptimeReport.ps1 -StartDate 2026-10-01 -EndDate 2026-10-26
    powershell -ExecutionPolicy Bypass -File .\Get-UptimeReport.ps1 -StartDate 2026-10-01 -EndDate 2026-10-26 -StandardHours 8
#>
[CmdletBinding()]
param(
    [string]$StartDate,
    [string]$EndDate,
    [string]$OutDir,
    [int]$MinActiveMinutes = 2,
    [double]$StandardHours = 9
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# 1. Time window
# =============================================================================
if (-not $OutDir) {
    $base   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $OutDir = Join-Path $base 'uptime-report'
}
$inv        = [Globalization.CultureInfo]::InvariantCulture
$now = Get-Date

function Read-DateInput {
    param([string]$Value, [string]$Prompt, [datetime]$Default)
    if (-not $Value) {
        $Value = Read-Host "$Prompt (yyyy-MM-dd) [Enter = $($Default.ToString('yyyy-MM-dd'))]"
        if (-not $Value) { return $Default.Date }
    }
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Value.Trim(), 'yyyy-MM-dd', $inv, 'None', [ref]$d)) {
        throw "Invalid date '$Value'. Use yyyy-MM-dd, for example 2026-10-01."
    }
    $d.Date
}

$startDay = Read-DateInput $StartDate 'Start date' (Get-Date -Day 1)
$endDay   = Read-DateInput $EndDate   'End date'   $now
if ($endDay -lt $startDay) { throw "End date $($endDay.ToString('yyyy-MM-dd')) is before start date $($startDay.ToString('yyyy-MM-dd'))." }
if ($startDay -gt $now)    { throw "Start date $($startDay.ToString('yyyy-MM-dd')) is in the future." }

$rangeStart = $startDay
$rangeEnd   = $endDay.AddDays(1)                              # end date is inclusive
$Tag        = '{0}_to_{1}' -f $startDay.ToString('yyyy-MM-dd'), $endDay.ToString('yyyy-MM-dd')

$reportEnd = if ($now -lt $rangeEnd) { $now } else { $rangeEnd }
$queryFrom = $rangeStart.AddDays(-14)                         # look back to know the state at range start
$queryTo   = if ($now -lt $rangeEnd.AddDays(1)) { $now } else { $rangeEnd.AddDays(1) }

$JumpMin   = [timespan]::FromMinutes(5)                       # clock jump bigger than this = real wake
$MinActive = [timespan]::FromMinutes($MinActiveMinutes)
$TF        = 'yyyy-MM-dd HH:mm:ss'

# =============================================================================
# 2. Helpers
# =============================================================================
function Get-Ev {
    param([string]$Provider, [int[]]$Ids)
    try {
        @(Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = $Provider; Id = $Ids
            StartTime = $queryFrom; EndTime = $queryTo } -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { @() } else { throw }
    }
}

function Get-EventData {
    # Event fields by name (robust across Windows versions)
    param($Rec)
    $h = @{}
    ([xml]$Rec.ToXml()).Event.EventData.Data | ForEach-Object { $h[$_.Name] = $_.'#text' }
    $h
}

function ConvertTo-Local {
    # Event time strings look like 2026-10-02T02:44:16.500000000Z (9 decimals, UTC).
    # .NET accepts max 7 decimals -> trim, then parse as UTC and convert to local time.
    param([string]$Value)
    $s = ($Value -replace '[^\d\-T:\.Z+]', '') -replace '(\.\d{7})\d+', '$1'
    $dt = [datetime]::Parse($s, $inv, [Globalization.DateTimeStyles]::RoundtripKind)
    if ($dt.Kind -eq [DateTimeKind]::Unspecified) { $dt = [datetime]::SpecifyKind($dt, 'Utc') }
    if ($dt.Kind -eq [DateTimeKind]::Utc) { $dt = $dt.ToLocalTime() }
    $dt
}

function Get-LastSeenBefore {
    # Newest System event (any source) before $Before -> last sign of life before a crash
    param([datetime]$Before)
    try {
        (Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $queryFrom; EndTime = $Before.AddSeconds(-1) } `
                      -MaxEvents 1 -ErrorAction Stop).TimeCreated
    }
    catch { $null }
}

# =============================================================================
# 3. Collect events
# =============================================================================
Write-Host "Reading System log $($queryFrom.ToString('yyyy-MM-dd')) -> $($queryTo.ToString($TF)) ..." -ForegroundColor Cyan

$kg      = Get-Ev 'Microsoft-Windows-Kernel-General' @(1, 12, 13)
$kp      = Get-Ev 'Microsoft-Windows-Kernel-Power'   @(41, 42, 506, 507)
$user32  = Get-Ev 'User32'                           @(1074)

$boots     = @($kg | Where-Object Id -eq 12 | Sort-Object TimeCreated)
$shutdowns = @($kg | Where-Object Id -eq 13)
$sleeps    = @($kp | Where-Object Id -eq 42)

# 3.1 Real wake time = clock jump (Kernel-General 1: NewTime, OldTime)
$wakes = foreach ($e in ($kg | Where-Object Id -eq 1)) {
    $d = Get-EventData $e
    if (-not $d.NewTime -or -not $d.OldTime) { continue }
    $new = ConvertTo-Local $d.NewTime
    $old = ConvertTo-Local $d.OldTime
    if (($new - $old) -gt $JumpMin) {
        [pscustomobject]@{ SleptAt = $old; WokeAt = $new }
    }
}
$wakes = @($wakes)

# 3.2 Crashes = boots that log Kernel-Power 41 ("rebooted without cleanly shutting down")
$crashes = foreach ($e in ($kp | Where-Object Id -eq 41 | Sort-Object TimeCreated)) {
    $boot = $boots | Where-Object { $_.TimeCreated -le $e.TimeCreated } | Select-Object -Last 1
    if (-not $boot) { continue }
    $bootTime = $boot.TimeCreated
    $last     = Get-LastSeenBefore -Before $bootTime
    $d        = Get-EventData $e

    $bug  = [int64]("0" + $d.BugcheckCode)
    $btn  = [int64]("0" + $d.PowerButtonTimestamp)
    $long = ($d.LongPowerButtonPressDetected -eq 'true')
    $slp  = ($d.SleepInProgress -and $d.SleepInProgress -ne '0' -and $d.SleepInProgress -ne 'false')

    $cause = if ($bug -ne 0)          { 'Blue screen (BugcheckCode {0:X})' -f $bug }
             elseif ($btn -ne 0 -or $long) { 'Power button held' }
             elseif ($slp)            { 'Lost power during sleep (battery?)' }
             else                     { 'Freeze or power loss (no detail)' }

    [pscustomobject]@{
        LastSeen     = $last
        BootTime     = $bootTime
        DownHours    = if ($last) { [math]::Round(($bootTime - $last).TotalHours, 2) } else { $null }
        Cause        = $cause
        BugcheckCode = $d.BugcheckCode
        PowerButtonTimestamp = $d.PowerButtonTimestamp
        SleepInProgress      = $d.SleepInProgress
    }
}
$crashes = @($crashes)

# 3.3 Update restarts
$updates = @($user32 | Where-Object { $_.Message -match 'MoUsoCoreWorker|TrustedInstaller' })

# =============================================================================
# 4. Build the state timeline
# =============================================================================
$seq = 0
$ev  = [System.Collections.Generic.List[object]]::new()
function Add-Ev($t, $state, $label) {
    $script:seq++
    $ev.Add([pscustomobject]@{ Time = $t; State = $state; Label = $label; Seq = $script:seq })
}

foreach ($b in $boots)     { Add-Ev $b.TimeCreated 'AWAKE' 'Boot' }
foreach ($s in $shutdowns) { Add-Ev $s.TimeCreated 'OFF'   'Shutdown' }
foreach ($s in $sleeps)    { Add-Ev $s.TimeCreated 'OFF'   'Sleep' }
foreach ($w in $wakes)     { Add-Ev $w.WokeAt      'AWAKE' 'Wake' }
foreach ($c in $crashes)   { if ($c.LastSeen) { Add-Ev $c.LastSeen 'CRASH' 'Crash' } }

# Modern Standby: group by second; a 506+507 pair in one second = momentary wake (ignored)
$kp | Where-Object { $_.Id -in 506, 507 } |
    Group-Object { $_.TimeCreated.ToString($TF) } | ForEach-Object {
        $ids = @($_.Group | Select-Object -ExpandProperty Id -Unique)
        $t   = $_.Group[0].TimeCreated
        if ($ids.Count -eq 1 -and $ids[0] -eq 506) { Add-Ev $t 'STANDBY' 'Standby' }
        elseif ($ids.Count -eq 1 -and $ids[0] -eq 507) { Add-Ev $t 'AWAKE' 'StandbyExit' }
    }

$timeline = $ev | Sort-Object Time, Seq

$segments = [System.Collections.Generic.List[object]]::new()
$state = 'AWAKE'                                   # assumption for the time before the first event
$cur   = $queryFrom
foreach ($e in $timeline) {
    $isDown = ($state -eq 'OFF' -or $state -eq 'CRASH')
    if ($isDown -and $e.State -eq 'STANDBY') { continue }                 # standby noise while off
    if ($isDown -and $e.Label -eq 'StandbyExit') { continue }
    if ($state -eq 'CRASH' -and $e.State -eq 'OFF') { continue }          # stale sleep/shutdown stamps after a crash
    $segments.Add([pscustomobject]@{ Start = $cur; End = $e.Time; State = $state })
    $cur = $e.Time; $state = $e.State
}
$segments.Add([pscustomobject]@{ Start = $cur; End = $queryTo; State = $state })

# Clip to the date range
$segments = @($segments | ForEach-Object {
    $s = if ($_.Start -lt $rangeStart) { $rangeStart } else { $_.Start }
    $e = if ($_.End   -gt $reportEnd)  { $reportEnd }  else { $_.End }
    if ($e -gt $s) { [pscustomobject]@{ Start = $s; End = $e; State = $_.State; Hours = [math]::Round(($e - $s).TotalHours, 2) } }
})

# =============================================================================
# 5. Split per day
# =============================================================================
$days = @{}
foreach ($sg in $segments) {
    $c = $sg.Start
    while ($c -lt $sg.End) {
        $k  = $c.Date
        $de = $k.AddDays(1)
        $e  = if ($sg.End -lt $de) { $sg.End } else { $de }
        if (-not $days.ContainsKey($k)) { $days[$k] = @{ AWAKE = 0.0; STANDBY = 0.0; OFF = 0.0; CRASH = 0.0; First = $null; Last = $null } }
        $r = $days[$k]
        $r[$sg.State] += ($e - $c).TotalHours
        if ($sg.State -eq 'AWAKE' -and ($sg.End - $sg.Start) -ge $MinActive) {
            if (-not $r.First) { $r.First = $c }
            $r.Last = $e
        }
        $c = $e
    }
}

$labels = @{}
foreach ($e in $timeline) {
    if ($e.Label -in 'Boot', 'Shutdown', 'Crash', 'Sleep', 'Wake' -and $e.Time -ge $rangeStart -and $e.Time -lt $reportEnd) {
        $k = $e.Time.Date
        if (-not $labels.ContainsKey($k)) { $labels[$k] = [System.Collections.Generic.List[string]]::new() }
        $labels[$k].Add("$($e.Label) $($e.Time.ToString('HH:mm'))")
    }
}
$updateDays = @($updates | ForEach-Object { $_.TimeCreated.Date } | Sort-Object -Unique)

$daily = [System.Collections.Generic.List[object]]::new()
for ($k = $rangeStart; $k -lt $reportEnd; $k = $k.AddDays(1)) {
    $r   = $days[$k]
    $lbl = if ($labels.ContainsKey($k)) { @($labels[$k]) } else { @() }
    $first = ''; $last = ''
    if ($r -and $r.First) {
        $first = $r.First.ToString('HH:mm')
        $last  = if ($r.Last -eq $k.AddDays(1)) { '24:00' } else { $r.Last.ToString('HH:mm') }
    }
    $activeH   = if ($r) { [math]::Round($r.AWAKE, 2) } else { 0 }
    $isWeekend = ($k.DayOfWeek -eq [DayOfWeek]::Saturday -or $k.DayOfWeek -eq [DayOfWeek]::Sunday)
    if ($isWeekend) { $regularH = 0; $otH = $activeH }
    else {
        $regularH = [math]::Round([math]::Min($activeH, $StandardHours), 2)
        $otH      = [math]::Round([math]::Max($activeH - $StandardHours, 0), 2)
    }
    $daily.Add([pscustomobject]@{
        Date          = $k.ToString('yyyy-MM-dd')
        Day           = $k.ToString('ddd', $inv)
        DayType       = if ($isWeekend) { 'Weekend' } else { 'Weekday' }
        FirstActive   = $first
        LastActive    = $last
        ActiveHours   = $activeH
        RegularHours  = $regularH
        OvertimeHours = $otH
        CrashHours    = if ($r) { [math]::Round($r.CRASH, 2) }   else { 0 }
        StandbyHours  = if ($r) { [math]::Round($r.STANDBY, 2) } else { 0 }
        OffHours      = if ($r) { [math]::Round($r.OFF, 2) }     else { 0 }
        Boots         = @($lbl | Where-Object { $_ -like 'Boot*' }).Count
        Crashes       = @($lbl | Where-Object { $_ -like 'Crash*' }).Count
        UpdateRestart = if ($updateDays -contains $k) { 'Yes' } else { '' }
        Events        = ($lbl -join '; ')
    })
}

# =============================================================================
# 6. Summary
# =============================================================================
$crashesInRange = @($crashes | Where-Object { $_.BootTime -ge $rangeStart -and $_.BootTime -lt $reportEnd })
$active = @($daily | Where-Object { $_.ActiveHours -gt 0 }).Count
$awake  = [math]::Round(($daily | Measure-Object ActiveHours -Sum).Sum, 2)
$crashH = [math]::Round(($daily | Measure-Object CrashHours -Sum).Sum, 2)
$regH   = [math]::Round(($daily | Measure-Object RegularHours -Sum).Sum, 2)
$otAll  = [math]::Round(($daily | Measure-Object OvertimeHours -Sum).Sum, 2)
$otWd   = [math]::Round((@($daily | Where-Object DayType -eq 'Weekday') | Measure-Object OvertimeHours -Sum).Sum, 2)
$otWe   = [math]::Round((@($daily | Where-Object DayType -eq 'Weekend') | Measure-Object OvertimeHours -Sum).Sum, 2)
$otDays = @($daily | Where-Object { $_.OvertimeHours -gt 0 }).Count
$stby   = [math]::Round(($daily | Measure-Object StandbyHours -Sum).Sum, 2)
$summary = [pscustomobject]@{
    Range             = '{0} to {1}' -f $startDay.ToString('yyyy-MM-dd'), $endDay.ToString('yyyy-MM-dd')
    From              = $rangeStart.ToString('yyyy-MM-dd')
    Until             = $reportEnd.ToString($TF)
    DaysInRange       = $daily.Count
    ActiveDays        = $active
    ActiveHours       = $awake
    StandardHoursPerWeekday = $StandardHours
    RegularHours      = $regH
    OvertimeHours     = $otAll
    WeekdayOvertime   = $otWd
    WeekendOvertime   = $otWe
    OvertimeDays      = $otDays
    CrashHours        = $crashH
    StandbyHours      = $stby
    AvgActivePerActiveDay = if ($active) { [math]::Round($awake / $active, 2) } else { 0 }
    UncleanShutdowns  = $crashesInRange.Count
    UpdateRestarts    = @($updates | Where-Object { $_.TimeCreated -ge $rangeStart -and $_.TimeCreated -lt $reportEnd }).Count
    Computer          = $env:COMPUTERNAME
    TimeZone          = [TimeZoneInfo]::Local.Id
    GeneratedAt       = $now.ToString($TF)
}

# =============================================================================
# 7. Write CSV files
# =============================================================================
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$f = @{
    daily    = Join-Path $OutDir "daily_$Tag.csv"
    segments = Join-Path $OutDir "segments_$Tag.csv"
    crashes  = Join-Path $OutDir "crashes_$Tag.csv"
    summary  = Join-Path $OutDir "summary_$Tag.csv"
    html     = Join-Path $OutDir "report_$Tag.html"
}
$daily | Export-Csv $f.daily -NoTypeInformation -Encoding UTF8
$segments | Select-Object @{n='Start';e={$_.Start.ToString($TF)}}, @{n='End';e={$_.End.ToString($TF)}}, State, Hours |
    Export-Csv $f.segments -NoTypeInformation -Encoding UTF8
$crashesInRange | Select-Object @{n='LastSeen';e={ if ($_.LastSeen) { $_.LastSeen.ToString($TF) } }},
    @{n='BootTime';e={$_.BootTime.ToString($TF)}}, DownHours, Cause, BugcheckCode, PowerButtonTimestamp, SleepInProgress |
    Export-Csv $f.crashes -NoTypeInformation -Encoding UTF8
$summary | Export-Csv $f.summary -NoTypeInformation -Encoding UTF8

# =============================================================================
# 8. HTML report (no internet needed)
# =============================================================================
$enc  = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
$maxH = 24
$rows = ($daily | ForEach-Object {
    $aw = [math]::Round($_.ActiveHours / $maxH * 100, 1)
    $ch = [math]::Round($_.CrashHours / $maxH * 100, 1)
    $sb = [math]::Round($_.StandbyHours / $maxH * 100, 1)
    $cr = if ($_.Crashes -gt 0) { " class='crash'" } elseif ($_.DayType -eq 'Weekend') { " class='we'" } else { '' }
    $ot = if ($_.OvertimeHours -gt 0) { "<b class='ot'>$($_.OvertimeHours)</b>" } else { '0' }
    "<tr$cr><td>$($_.Date)</td><td>$($_.Day)</td><td>$($_.FirstActive)</td><td>$($_.LastActive)</td>" +
    "<td class='n'>$($_.ActiveHours)</td><td class='n'>$($_.RegularHours)</td><td class='n'>$ot</td><td class='n'>$($_.CrashHours)</td><td class='n'>$($_.StandbyHours)</td><td class='n'>$($_.Crashes)</td>" +
    "<td><div class='bar'><span class='a' style='width:$aw%'></span><span class='s' style='width:$sb%'></span><span class='x' style='width:$ch%'></span></div></td>" +
    "<td class='ev'>$(& $enc $_.Events)$(if ($_.UpdateRestart) { ' <b>[Update]</b>' })</td></tr>"
}) -join "`n"
$crRows = ($crashesInRange | ForEach-Object {
    "<tr><td>$(if ($_.LastSeen) { $_.LastSeen.ToString($TF) })</td><td>$($_.BootTime.ToString($TF))</td><td class='n'>$($_.DownHours)</td><td>$(& $enc $_.Cause)</td></tr>"
}) -join "`n"

$html = @"
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Uptime $Tag</title>
<style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#e5e5ea;--a:#2f6fdb;--s:#f0a73a;--c:#fdecec}
@media (prefers-color-scheme:dark){:root{--bg:#141416;--fg:#f2f2f7;--mut:#a1a1a6;--line:#2c2c30;--a:#5b8ff0;--s:#e0a040;--c:#3a1f1f}}
body{background:var(--bg);color:var(--fg);font:14px/1.45 Segoe UI,system-ui,sans-serif;margin:0;padding:24px 16px}
h1{font-size:22px;margin:0 0 4px}.mut{color:var(--mut)}
.kpi{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}
.kpi div{border:1px solid var(--line);border-radius:10px;padding:10px 14px;min-width:120px}
.kpi b{display:block;font-size:20px}
table{border-collapse:collapse;width:100%;margin:12px 0 28px}
th,td{border-bottom:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}
th{font-weight:600;color:var(--mut)}td.n{text-align:right}td.ev{font-size:12px;color:var(--mut)}
tr.crash{background:var(--c)}tr.we td:nth-child(2){font-weight:700}.ot{color:#c2410c}
.bar{display:flex;width:160px;height:10px;background:var(--line);border-radius:5px;overflow:hidden}
.bar .a{background:var(--a)}.bar .s{background:var(--s)}.bar .x{background:#d64545}
.lg span{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 4px 0 12px}
.wrap{overflow-x:auto}
</style></head><body>
<h1>Uptime report - $($summary.Range)</h1>
<div class="mut">$($summary.Computer) | $($summary.TimeZone) | until $($summary.Until)</div>
<div class="kpi">
<div><span class="mut">Active days</span><b>$active</b></div>
<div><span class="mut">Active hours</span><b>$awake</b></div>
<div><span class="mut">Overtime hours</span><b class="ot">$otAll</b></div>
<div><span class="mut">Weekday OT (&gt;$StandardHours h)</span><b>$otWd</b></div>
<div><span class="mut">Weekend OT</span><b>$otWe</b></div>
<div><span class="mut">Crash hours</span><b>$crashH</b></div>
<div><span class="mut">Standby hours</span><b>$stby</b></div>
<div><span class="mut">Avg awake / active day</span><b>$($summary.AvgActivePerActiveDay)</b></div>
<div><span class="mut">Unclean shutdowns</span><b>$($summary.UncleanShutdowns)</b></div>
</div>
<div class="mut lg">Bar = 24 h<span style="background:var(--a)"></span>Active<span style="background:var(--s)"></span>Standby<span style="background:#d64545"></span>Crash (down after crash) | red rows = crash</div>
<div class="wrap"><table><tr><th>Date</th><th>Day</th><th>First</th><th>Last</th><th>Active h</th><th>Regular h</th><th>Overtime h</th><th>Crash h</th><th>Standby h</th><th>Crash</th><th>Day bar</th><th>Events</th></tr>
$rows
</table></div>
<h2>Unclean shutdowns</h2>
<div class="wrap"><table><tr><th>Last seen</th><th>Next boot</th><th>Down h</th><th>Likely cause</th></tr>
$crRows
</table></div>
<p class="mut">Active = powered on and not in standby (not proof of user activity). Crash hours = time from last sign of life to the next boot. Overtime: Mon-Fri = active hours above $StandardHours h; Sat/Sun = all active hours. Public holidays are not handled. Crash time = last System event before reboot (lower bound).</p>
</body></html>
"@
Set-Content -Path $f.html -Value $html -Encoding UTF8

# =============================================================================
# 9. Console output
# =============================================================================
$daily | Format-Table Date, Day, FirstActive, LastActive, ActiveHours, RegularHours, OvertimeHours, CrashHours, StandbyHours, Crashes, UpdateRestart -AutoSize
if ($crashesInRange.Count) {
    Write-Host "Unclean shutdowns:" -ForegroundColor Yellow
    $crashesInRange | Format-Table LastSeen, BootTime, DownHours, Cause -AutoSize
}
$summary | Format-List
Write-Host "Files written:" -ForegroundColor Cyan
$f.Values | ForEach-Object { Write-Host "  $_" }
Invoke-Item $f.html
