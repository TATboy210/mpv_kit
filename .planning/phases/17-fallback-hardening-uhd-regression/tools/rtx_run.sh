#!/usr/bin/env bash
# Phase 17 RTX 4060 session wrapper: gate, run, ledger (VER-04, used by 17-04).
#
# This fixes the Phase 12 session discipline (evidence/final-runs.txt "gate",
# "run", "forensics", "standby" lines; docs/perf/renderbackend-seam-regression.md
# Method) in code, so every hardware run of 17-04 is gated, timestamped,
# recorded and never overwritten.
#
# usage (from the repo root, Git Bash on Windows):
#   bash rtx_run.sh gate <run>
#   bash rtx_run.sh run <run> [--vram] [--attempt <n>] -- <command...>
#   bash rtx_run.sh --dry-run
#
# gate <run>   one line on stdout (and exit 3 when any item fails):
#   gate run=<run> result=pass|FAIL desktop=<unlocked|locked> ac=<yes|no|no-battery>
#        disk_free_repo_mib=<n> stray_example=<n> heavy_gpu=<none|proc:pct,...>
#        native_equal=<yes|no|n/a> at=<UTC>
#   Items (source in parentheses):
#     desktop unlocked: no LogonUI process and the foreground process is not
#       LockApp (Phase 12 gate, final-runs.txt)
#     ac: Win32_Battery BatteryStatus 2 (on AC) or no battery at all
#       (Modern Standby / throttling risk on battery, 12 Method)
#     disk_free_repo_mib >= 5632 (the 12-12 precondition: Phases 7 and 9 lost
#       runs to disk pressure on the repo drive)
#     stray_example = 0: no mpv_kit_example process left over
#     heavy_gpu none: no process other than dwm at >= 10% of any GPU engine
#       (Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine, summed per pid)
#     native_equal: when evidence/rtx-prep.txt exists, product code
#       (packages, example/lib, example/integration_test, native) equals its
#       sha= (git diff --quiet); n/a without rtx-prep.txt
#
# run <run> ...   gate first (a failed gate starts nothing, exit 3). The log is
#   evidence/rtx-<run>.log (rtx-<run>-a<n>.log with --attempt n); an existing
#   log is never overwritten (exit 4). Output of the command (stdout+stderr) is
#   written line by line with a UTC ISO-8601 millisecond prefix and echoed.
#   --vram samples the example process' dedicated GPU memory every 1 s through
#   vram_sample.ps1 into evidence/rtx-<run>.vram.csv. The command runs in
#   example/. Afterwards the System log is searched for Kernel-Power 506/507
#   (Modern Standby) and the Application log for 1000/1001 naming
#   mpv_kit_example.exe or flutter_windows.dll, and %LOCALAPPDATA%\CrashDumps
#   for files newer than the start; one ledger line is appended to
#   evidence/rtx-runs.txt:
#   run=<run> attempt=<n> start=<UTC> end=<UTC> exit=<code> log=<file>
#       vram=<file|none> standby_during=<none|506@..,507@..> forensics=<none|..>
#
# --dry-run: gate (result recorded, never aborts), then `run dryrun --vram --
#   sleep 5` with log, CSV and ledger under build/phase17/dryrun/ (git-ignored),
#   then four lines into evidence/dryrun.txt: the gate line, the ledger line,
#   csv_rows=<data rows> and csv_first=<first data row>.
#
# Exit codes: 0 command succeeded, 3 gate failed, 4 refusing to overwrite,
#   anything else is the command's own exit code.
#
# The tool never deletes a file (the sampler's .stop marker is only created)
# and never modifies example/ or packages/.
set -uo pipefail
export TZ=UTC

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE_DIR="$(cd "$TOOLS_DIR/.." && pwd)"
REPO="$(git -C "$PHASE_DIR" rev-parse --show-toplevel)"
EVIDENCE="$PHASE_DIR/evidence"
PREP="$EVIDENCE/rtx-prep.txt"
MIN_DISK_MIB=5632
HEAVY_GPU_PCT=10

# Output locations; --dry-run redirects them to build/phase17/dryrun/.
OUT_DIR="$EVIDENCE"
LEDGER="$EVIDENCE/rtx-runs.txt"
DRY=0

# UTC ISO-8601 with milliseconds from bash's own clock (no fork per call).
utc_ms() {
  local now=${EPOCHREALTIME/./} secs ms
  secs=$((now / 1000000))
  ms=$(((now / 1000) % 1000))
  printf '%(%Y-%m-%dT%H:%M:%S)T.%03dZ' "$secs" "$ms"
}

# Runs a PowerShell script read from stdin (Windows PowerShell, no profile).
# The whole input is compiled as one script block: `-Command -` would execute
# it line by line and break multi-line constructs.
ps() {
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \
    '& ([scriptblock]::Create([Console]::In.ReadToEnd()))' 2>/dev/null | tr -d '\r'
}

# --- gate --------------------------------------------------------------------

# Facts of the machine as key=value lines: desktop, ac, stray, heavy.
gate_facts() {
  ps <<'PS'
Add-Type -Namespace Phase17 -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
'@
$locked = $false
if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) { $locked = $true }
$hwnd = [Phase17.Native]::GetForegroundWindow()
if ($hwnd -ne [System.IntPtr]::Zero) {
  $fgPid = [uint32]0
  [void][Phase17.Native]::GetWindowThreadProcessId($hwnd, [ref]$fgPid)
  $fg = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
  if ($fg -and $fg.ProcessName -eq 'LockApp') { $locked = $true }
}
"desktop=$(if ($locked) { 'locked' } else { 'unlocked' })"
$batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
if ($batteries.Count -eq 0) { 'ac=no-battery' }
elseif ($batteries[0].BatteryStatus -eq 2) { 'ac=yes' }
else { 'ac=no' }
"stray=$(@(Get-Process -Name mpv_kit_example -ErrorAction SilentlyContinue).Count)"
$byPid = @{}
Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine |
  ForEach-Object {
    if ($_.Name -match '^pid_(\d+)_') {
      $byPid[[int]$Matches[1]] = [double]$byPid[[int]$Matches[1]] + [double]$_.UtilizationPercentage
    }
  }
$heavy = @()
foreach ($procId in $byPid.Keys) {
  if ($byPid[$procId] -ge 10) {
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    $name = if ($p) { $p.ProcessName } else { "pid$procId" }
    if ($name -ne 'dwm') { $heavy += ('{0}:{1}' -f $name, [math]::Round($byPid[$procId])) }
  }
}
"heavy=$(if ($heavy.Count -eq 0) { 'none' } else { $heavy -join ',' })"
PS
}

# Prints the gate line for <run>; returns 0 on pass, 3 on FAIL.
gate() {
  local run=$1 facts desktop ac stray heavy disk native='n/a' result=pass sha
  facts=$(gate_facts)
  desktop=$(sed -n 's/^desktop=//p' <<<"$facts")
  ac=$(sed -n 's/^ac=//p' <<<"$facts")
  stray=$(sed -n 's/^stray=//p' <<<"$facts")
  heavy=$(sed -n 's/^heavy=//p' <<<"$facts")
  disk=$(df -Pm "$REPO" | awk 'NR==2 {print $4}')
  if [ -f "$PREP" ]; then
    sha=$(sed -n 's/^sha=//p' "$PREP" | head -n 1)
    if [ -n "$sha" ] && git -C "$REPO" diff --quiet "$sha" -- packages example/lib example/integration_test native; then
      native=yes
    else
      native=no
    fi
  fi
  # An unreadable fact (PowerShell failed) is a failure, never a pass.
  [ "$desktop" = unlocked ] || result=FAIL
  case "$ac" in yes | no-battery) ;; *) result=FAIL ;; esac
  [ "${disk:-0}" -ge "$MIN_DISK_MIB" ] || result=FAIL
  [ "${stray:-1}" = 0 ] || result=FAIL
  [ "${heavy:-unknown}" = none ] || result=FAIL
  [ "$native" != no ] || result=FAIL
  echo "gate run=$run result=$result desktop=${desktop:-unknown} ac=${ac:-unknown} disk_free_repo_mib=${disk:-0} stray_example=${stray:-unknown} heavy_gpu=${heavy:-unknown} native_equal=$native at=$(utc_ms)"
  [ "$result" = pass ]
}

# --- run ---------------------------------------------------------------------

# Prefixes every stdin line with the current UTC time.
stamp_lines() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s %s\n' "$(utc_ms)" "$line"
  done
}

# Event facts between $1 and $2 (UTC ISO strings): standby=..., forensics=...
forensics() {
  local start=$1 end=$2
  {
    printf '$start = [DateTime]::Parse("%s").ToUniversalTime()\n' "$start"
    printf '$end = [DateTime]::Parse("%s").ToUniversalTime()\n' "$end"
    cat <<'PS'
$fmt = "HH:mm:ss'Z'"
$standby = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 506, 507; StartTime = $start; EndTime = $end } -ErrorAction SilentlyContinue |
  Sort-Object TimeCreated | ForEach-Object { '{0}@{1}' -f $_.Id, $_.TimeCreated.ToUniversalTime().ToString($fmt) })
"standby=$(if ($standby.Count -eq 0) { 'none' } else { $standby -join ',' })"
$found = @()
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001; StartTime = $start; EndTime = $end } -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'mpv_kit_example\.exe|flutter_windows\.dll' } |
  ForEach-Object { $found += ('app{0}@{1}' -f $_.Id, $_.TimeCreated.ToUniversalTime().ToString($fmt)) }
$dumps = Join-Path $env:LOCALAPPDATA 'CrashDumps'
if (Test-Path -LiteralPath $dumps) {
  Get-ChildItem -LiteralPath $dumps -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTimeUtc -gt $start } |
    ForEach-Object { $found += ('dump:' + $_.Name) }
}
"forensics=$(if ($found.Count -eq 0) { 'none' } else { $found -join ';' })"
PS
  } | ps
}

# run <run> [--vram] [--attempt n] -- cmd...  (OUT_DIR / LEDGER already set)
run_command() {
  local run=$1 vram=0 attempt=1
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --vram) vram=1 ;;
      --attempt) attempt=$2; shift ;;
      --) shift; break ;;
      *) echo "rtx_run: unknown argument $1" >&2; return 2 ;;
    esac
    shift
  done
  [ $# -gt 0 ] || { echo "rtx_run: no command after --" >&2; return 2; }

  local suffix='' log csv sampler_pid='' start end rc facts standby foren vram_name=none
  [ "$attempt" = 1 ] || suffix="-a$attempt"
  log="$OUT_DIR/rtx-$run$suffix.log"
  csv="$OUT_DIR/rtx-$run$suffix.vram.csv"

  if [ "$DRY" = 1 ]; then
    gate "$run" || true
  else
    gate "$run" || { echo "rtx_run: gate failed, nothing started" >&2; return 3; }
  fi
  # Never overwrite: an existing log or CSV ends the run before it starts.
  if [ -e "$log" ] || { [ "$vram" = 1 ] && [ -e "$csv" ]; }; then
    echo "rtx_run: refusing to overwrite $log or $csv" >&2
    return 4
  fi
  mkdir -p "$OUT_DIR"
  (set -o noclobber; : >"$log") || { echo "rtx_run: cannot create $log" >&2; return 4; }

  if [ "$vram" = 1 ]; then
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
      -File "$(cygpath -w "$TOOLS_DIR/vram_sample.ps1")" \
      -Out "$(cygpath -w "$csv")" -ProcessName mpv_kit_example -IntervalMs 1000 \
      >/dev/null 2>&1 &
    sampler_pid=$!
    vram_name=$(basename "$csv")
  fi

  start=$(utc_ms)
  (cd "$REPO/example" && "$@") 2>&1 | stamp_lines | tee -a "$log"
  rc=${PIPESTATUS[0]}
  end=$(utc_ms)

  if [ -n "$sampler_pid" ]; then
    : >"$csv.stop"
    local waited=0
    while kill -0 "$sampler_pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
      sleep 1
      waited=$((waited + 1))
    done
  fi

  facts=$(forensics "$start" "$end")
  standby=$(sed -n 's/^standby=//p' <<<"$facts")
  foren=$(sed -n 's/^forensics=//p' <<<"$facts")
  echo "run=$run attempt=$attempt start=$start end=$end exit=$rc log=$(basename "$log") vram=$vram_name standby_during=${standby:-unknown} forensics=${foren:-unknown}" >>"$LEDGER"
  tail -n 1 "$LEDGER"
  return "$rc"
}

# --- dry run -----------------------------------------------------------------

dry_run() {
  DRY=1
  OUT_DIR="$REPO/build/phase17/dryrun"
  LEDGER="$OUT_DIR/rtx-runs.txt"
  mkdir -p "$OUT_DIR"
  local gate_line ledger_line rows first
  gate_line=$(gate dryrun || true)
  # A fresh directory per dry run: stale files from an earlier one are never
  # overwritten, so pick a run id that has no log yet.
  local id="dryrun" n=1
  while [ -e "$OUT_DIR/rtx-$id.log" ]; do
    n=$((n + 1))
    id="dryrun$n"
  done
  run_command "$id" --vram -- sleep 5 >/dev/null || true
  ledger_line=$(grep "^run=$id " "$LEDGER" | tail -n 1)
  rows=$(($(wc -l <"$OUT_DIR/rtx-$id.vram.csv") - 1))
  first=$(sed -n '2p' "$OUT_DIR/rtx-$id.vram.csv" | tr -d '\r')
  {
    echo "$gate_line"
    echo "$ledger_line"
    echo "csv_rows=$rows"
    echo "csv_first=$first"
  } >"$EVIDENCE/dryrun.txt"
  cat "$EVIDENCE/dryrun.txt"
}

case "${1:-}" in
  gate)
    [ $# -eq 2 ] || { echo "usage: rtx_run.sh gate <run>" >&2; exit 2; }
    gate "$2" || exit 3
    ;;
  run)
    shift
    [ $# -ge 1 ] || { echo "usage: rtx_run.sh run <run> ... -- <cmd>" >&2; exit 2; }
    run_command "$@"
    exit $?
    ;;
  --dry-run)
    dry_run
    ;;
  *)
    echo "usage: rtx_run.sh gate <run> | run <run> [--vram] [--attempt n] -- <cmd> | --dry-run" >&2
    exit 2
    ;;
esac
