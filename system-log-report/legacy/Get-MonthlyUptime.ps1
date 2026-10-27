<#
.SYNOPSIS
    Monthly system uptime log for Windows.

.DESCRIPTION
    Reads power events from the Windows "System" event log and builds three CSV files:
      - sessions_<yyyy-MM>.csv : every ON -> OFF period (boot/wake -> shutdown/sleep)
      - daily_<yyyy-MM>.csv    : one row per day: first start, last end, hours on
      - summary_<yyyy-MM>.csv  : one row for the month
    Also prints the daily table and the summary to the console.

    Events used (System log):
      ON  : Kernel-General 12 (OS boot), Power-Troubleshooter 1 (wake from sleep/hibernate)
      OFF : Kernel-General 13 (OS shutdown), Kernel-Power 42 (enter sleep/hibernate)
    A session with no OFF event (crash, power cut, forced power-off) ends at the last
    System event before the next boot and is marked "Unclean (estimated)".

.PARAMETER Month
    Month to report, format yyyy-MM. Default: current month.

.PARAMETER OutDir
    Output folder. Default: "uptime-logs" next to this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-MonthlyUptime.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-MonthlyUptime.ps1 -Month 2026-09
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
    [string]$Month = (Get-Date -Format 'yyyy-MM'),

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Time window
# ---------------------------------------------------------------------------
if (-not $OutDir) {
    $base   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $OutDir = Join-Path $base 'uptime-logs'
}

$monthStart = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$monthEnd   = $monthStart.AddMonths(1)
$now        = Get-Date

if ($monthStart -gt $now) { throw "Month $Month is in the future." }

$reportEnd = if ($now -lt $monthEnd) { $now } else { $monthEnd }

# Look a few days outside the month so sessions that cross the month edge close correctly.
$queryFrom = $monthStart.AddDays(-7)
$queryTo   = if ($now -lt $monthEnd.AddDays(7)) { $now } else { $monthEnd.AddDays(7) }

$TimeFmt     = 'yyyy-MM-dd HH:mm:ss'
$MergeWindow = [timespan]::FromSeconds(120)   # two ON events closer than this = one start
$CrashMargin = [timespan]::FromMinutes(2)     # ignore boot-time events when estimating crash time

# ---------------------------------------------------------------------------
# 2. Event definitions
# ---------------------------------------------------------------------------
$eventMap = @(
    @{ Provider = 'Microsoft-Windows-Kernel-General';       Id = 12; Kind = 'ON';  Reason = 'Boot' }
    @{ Provider = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1;  Kind = 'ON';  Reason = 'Wake' }
    @{ Provider = 'Microsoft-Windows-Kernel-General';       Id = 13; Kind = 'OFF'; Reason = 'Shutdown' }
    @{ Provider = 'Microsoft-Windows-Kernel-Power';         Id = 42; Kind = 'OFF'; Reason = 'Sleep' }
)

function Get-PowerEvents {
    param([datetime]$From, [datetime]$To)

    $result = foreach ($def in $eventMap) {
        try {
            Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = $def.Provider
                Id           = $def.Id
                StartTime    = $From
                EndTime      = $To
            } -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ Time = $_.TimeCreated; Kind = $def.Kind; Reason = $def.Reason }
            }
        }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
        }
    }
    $result | Sort-Object Time
}

function Get-LastEventBefore {
    # Newest System event between $After and ($Before - margin). Used to estimate crash time.
    param([datetime]$After, [datetime]$Before)
    $limit = $Before - $CrashMargin
    if ($limit -le $After) { return $null }
    try {
        (Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $After; EndTime = $limit } `
                      -MaxEvents 1 -ErrorAction Stop).TimeCreated
    }
    catch { $null }
}

# ---------------------------------------------------------------------------
# 3. Event log retention check
# ---------------------------------------------------------------------------
$oldest = $null
try { $oldest = (Get-WinEvent -LogName System -Oldest -MaxEvents 1 -ErrorAction Stop).TimeCreated } catch { }
$retentionWarning = ''
if ($oldest -and $oldest -gt $monthStart) {
    $retentionWarning = "System log starts at $($oldest.ToString($TimeFmt)). Data before this time is lost."
    Write-Warning $retentionWarning
}

# ---------------------------------------------------------------------------
# 4. Build sessions (ON -> OFF)
# ---------------------------------------------------------------------------
$events   = @(Get-PowerEvents -From $queryFrom -To $queryTo)
$sessions = [System.Collections.Generic.List[object]]::new()
$open     = $null

foreach ($ev in $events) {
    if ($ev.Kind -eq 'ON') {
        if ($open) {
            # Duplicate start signal (e.g. boot + wake logged together) -> keep the first one.
            if (($ev.Time - $open.Start) -lt $MergeWindow) { continue }

            # Previous session has no OFF event -> unclean stop.
            $lastSeen = Get-LastEventBefore -After $open.Start -Before $ev.Time
            $end      = if ($lastSeen -and $lastSeen -gt $open.Start) { $lastSeen } else { $open.Start }
            $sessions.Add([pscustomobject]@{
                Start = $open.Start; End = $end; StartReason = $open.Reason; EndReason = 'Unclean (estimated)'
            })
        }
        $open = @{ Start = $ev.Time; Reason = $ev.Reason }
    }
    else {
        # OFF without an open session (e.g. sleep then shutdown) is ignored.
        if ($open) {
            $sessions.Add([pscustomobject]@{
                Start = $open.Start; End = $ev.Time; StartReason = $open.Reason; EndReason = $ev.Reason
            })
            $open = $null
        }
    }
}

if ($open) {
    # Still open at the end of the query window.
    $isRunning = ($queryTo -eq $now)
    $sessions.Add([pscustomobject]@{
        Start       = $open.Start
        End         = $queryTo
        StartReason = $open.Reason
        EndReason   = if ($isRunning) { 'Running now' } else { 'No end event found' }
    })
}

# ---------------------------------------------------------------------------
# 5. Clip sessions to the month
# ---------------------------------------------------------------------------
$clipped = foreach ($s in $sessions) {
    $st = if ($s.Start -lt $monthStart) { $monthStart } else { $s.Start }
    $en = if ($s.End   -gt $reportEnd)  { $reportEnd }  else { $s.End }
    if ($en -gt $st) {
        [pscustomobject]@{
            Start       = $st
            End         = $en
            Hours       = [math]::Round(($en - $st).TotalHours, 2)
            StartReason = $s.StartReason
            EndReason   = $s.EndReason
        }
    }
}
$clipped = @($clipped)

# ---------------------------------------------------------------------------
# 6. Split sessions per day
# ---------------------------------------------------------------------------
$days = @{}
foreach ($s in $clipped) {
    $cursor = $s.Start
    while ($cursor -lt $s.End) {
        $dayEnd = $cursor.Date.AddDays(1)
        $segEnd = if ($s.End -lt $dayEnd) { $s.End } else { $dayEnd }
        $key    = $cursor.Date

        if (-not $days.ContainsKey($key)) {
            $days[$key] = @{ First = $cursor; Last = $segEnd; Seconds = 0.0; Sessions = 0 }
        }
        $d = $days[$key]
        if ($cursor -lt $d.First) { $d.First = $cursor }
        if ($segEnd -gt $d.Last)  { $d.Last  = $segEnd }
        $d.Seconds  += ($segEnd - $cursor).TotalSeconds
        $d.Sessions += 1

        $cursor = $segEnd
    }
}

# ---------------------------------------------------------------------------
# 7. Daily table (every day of the month up to today)
# ---------------------------------------------------------------------------
$daily = [System.Collections.Generic.List[object]]::new()
for ($day = $monthStart; $day -lt $reportEnd; $day = $day.AddDays(1)) {
    $d = $days[$day]
    if ($d) {
        $lastText = if ($d.Last -eq $day.AddDays(1)) { '24:00' } else { $d.Last.ToString('HH:mm') }
        $daily.Add([pscustomobject]@{
            Date       = $day.ToString('yyyy-MM-dd')
            Day        = $day.ToString('ddd')
            Month      = $day.ToString('MMM yyyy')
            FirstStart = $d.First.ToString('HH:mm')
            LastEnd    = $lastText
            Sessions   = $d.Sessions
            HoursOn    = [math]::Round($d.Seconds / 3600, 2)
            SpanHours  = [math]::Round(($d.Last - $d.First).TotalHours, 2)
        })
    }
    else {
        $daily.Add([pscustomobject]@{
            Date = $day.ToString('yyyy-MM-dd'); Day = $day.ToString('ddd'); Month = $day.ToString('MMM yyyy')
            FirstStart = ''; LastEnd = ''; Sessions = 0; HoursOn = 0; SpanHours = 0
        })
    }
}

# ---------------------------------------------------------------------------
# 8. Month summary
# ---------------------------------------------------------------------------
$activeDays = @($daily | Where-Object { $_.HoursOn -gt 0 }).Count
$totalHours = [math]::Round((($daily | Measure-Object HoursOn -Sum).Sum), 2)
$unclean    = @($clipped | Where-Object { $_.EndReason -like 'Unclean*' }).Count

$summary = [pscustomobject]@{
    Month                = $monthStart.ToString('MMMM yyyy')
    MonthStartDate       = $monthStart.ToString('yyyy-MM-dd')
    ReportUntil          = $reportEnd.ToString($TimeFmt)
    DaysCovered          = $daily.Count
    ActiveDays           = $activeDays
    TotalHoursOn         = $totalHours
    AvgHoursPerActiveDay = if ($activeDays) { [math]::Round($totalHours / $activeDays, 2) } else { 0 }
    Sessions             = $clipped.Count
    UncleanStops         = $unclean
    Computer             = $env:COMPUTERNAME
    GeneratedAt          = $now.ToString($TimeFmt)
    Warning              = $retentionWarning
}

# ---------------------------------------------------------------------------
# 9. Write files + console output
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$sessionFile = Join-Path $OutDir "sessions_$Month.csv"
$dailyFile   = Join-Path $OutDir "daily_$Month.csv"
$summaryFile = Join-Path $OutDir "summary_$Month.csv"

$clipped | Select-Object @{ n = 'Start'; e = { $_.Start.ToString($TimeFmt) } },
                         @{ n = 'End';   e = { $_.End.ToString($TimeFmt) } },
                         Hours, StartReason, EndReason |
    Export-Csv -Path $sessionFile -NoTypeInformation -Encoding UTF8

$daily   | Export-Csv -Path $dailyFile   -NoTypeInformation -Encoding UTF8
$summary | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8

$daily | Format-Table -AutoSize
$summary | Format-List

Write-Host "Files written:" -ForegroundColor Cyan
Write-Host "  $sessionFile"
Write-Host "  $dailyFile"
Write-Host "  $summaryFile"
