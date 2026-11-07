# Phase 17 (VER-04) dedicated GPU memory sampler for the RTX session.
#
# usage (Windows PowerShell 5+):
#   powershell -NoProfile -ExecutionPolicy Bypass -File vram_sample.ps1 `
#     -Out <csv> [-ProcessName mpv_kit_example] [-IntervalMs 1000]
#
# Writes one row per sample until the file "<csv>.stop" appears:
#   utc,pid,process_dedicated_mib,adapter_dedicated_mib,foreground,process_local_mib,process_committed_mib
#   utc                     UTC ISO-8601 with milliseconds (the join key to the
#                           SOAK-CHECKPOINT lines of backend_soak_test.dart)
#   pid                     the example process at that moment, empty when it
#                           does not exist
#   process_dedicated_mib   sum of DedicatedUsage over the GPUProcessMemory
#                           instances whose Name starts with "pid_<pid>_"
#                           (one instance per adapter), empty without a pid
#   adapter_dedicated_mib   sum of DedicatedUsage over the GPUAdapterMemory
#                           instances (all adapters of the machine)
#   foreground              process name owning the foreground window, "none"
#                           when there is none (locked desktop, no window)
#   process_local_mib       sum of LocalUsage over the same GPUProcessMemory instances
#                           (device-local segment = VRAM on a discrete GPU), empty
#                           without a pid. Added in 17-04 after attempt 1: with
#                           presented 4K frames DedicatedUsage grows by about one
#                           4K frame per presented frame (1.9 GB/s at 30 fps, to 3.4 TB
#                           in 30 min) while LocalUsage stays flat and plausible, so
#                           process_dedicated_mib is NOT usable for runs that present
#                           frames; use process_local_mib there.
#   process_committed_mib   sum of TotalCommitted over the same instances
# Values are in MiB with one decimal.
#
# Why CIM classes and not Get-Counter: this machine runs a localized Windows,
# and counter PATHS are translated ("\GPU Process Memory(...)\..." differs per
# language), while the CIM class names below are not.
#
# The script only reads; it never deletes or changes anything except the CSV
# and (by the caller) the .stop marker.
param(
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$ProcessName = 'mpv_kit_example',
  [int]$IntervalMs = 1000
)

$ErrorActionPreference = 'Stop'
$stopFile = "$Out.stop"
$mib = 1048576.0

# Foreground window owner via user32 (the same facts the Phase 12 sampler read).
Add-Type -Namespace Phase17 -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
'@

function Get-ForegroundName {
  $hwnd = [Phase17.Native]::GetForegroundWindow()
  if ($hwnd -eq [System.IntPtr]::Zero) { return 'none' }
  $fgPid = [uint32]0
  [void][Phase17.Native]::GetWindowThreadProcessId($hwnd, [ref]$fgPid)
  $proc = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
  if ($null -eq $proc) { return 'none' }
  return $proc.ProcessName
}

# Header once; the caller refuses to reuse an existing CSV, so no overwrite.
'utc,pid,process_dedicated_mib,adapter_dedicated_mib,foreground,process_local_mib,process_committed_mib' |
  Out-File -FilePath $Out -Encoding ascii

while (-not (Test-Path -LiteralPath $stopFile)) {
  $tick = [Diagnostics.Stopwatch]::StartNew()
  $utc = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
  $adapter = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory
  $adapterSum = ($adapter | Measure-Object -Property DedicatedUsage -Sum).Sum
  if ($null -eq $adapterSum) { $adapterSum = 0 }

  $procId = ''
  $procMib = ''
  $localMib = ''
  $commitMib = ''
  $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -ne $proc) {
    $procId = [string]$proc.Id
    $mem = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory |
      Where-Object { $_.Name -like "pid_$($proc.Id)_*" }
    $memSum = ($mem | Measure-Object -Property DedicatedUsage -Sum).Sum
    if ($null -eq $memSum) { $memSum = 0 }
    $procMib = ([math]::Round($memSum / $mib, 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
    $localSum = ($mem | Measure-Object -Property LocalUsage -Sum).Sum
    if ($null -eq $localSum) { $localSum = 0 }
    $localMib = ([math]::Round($localSum / $mib, 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
    $commitSum = ($mem | Measure-Object -Property TotalCommitted -Sum).Sum
    if ($null -eq $commitSum) { $commitSum = 0 }
    $commitMib = ([math]::Round($commitSum / $mib, 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
  }
  $adapterMib = ([math]::Round($adapterSum / $mib, 1)).ToString([Globalization.CultureInfo]::InvariantCulture)
  $row = "$utc,$procId,$procMib,$adapterMib,$(Get-ForegroundName),$localMib,$commitMib"
  Add-Content -LiteralPath $Out -Value $row -Encoding ascii

  # Keep the cadence at IntervalMs regardless of how long the queries took.
  $rest = $IntervalMs - $tick.ElapsedMilliseconds
  if ($rest -gt 0) { Start-Sleep -Milliseconds $rest }
}
