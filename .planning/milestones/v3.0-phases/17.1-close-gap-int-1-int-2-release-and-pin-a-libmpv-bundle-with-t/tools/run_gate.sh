#!/usr/bin/env bash
# Phase 17.1 one-run gate: judges ONE finished (or running) GitHub Actions run
# by id. Used for release.yml runs (rehearsal dispatch on the branch ref, tag
# run) where ci_gate.sh's "runs of one pushed SHA" selection does not apply.
# Same conventions as ci_gate.sh / release_gate.sh, but it never dispatches,
# reruns or deletes anything (only its own mktemp dir).
#
# usage:
#   RUN_GATE_LABEL=<free text> [RUN_GATE_EXPECT_SHA=<40-hex>] \
#   [RUN_GATE_EVIDENCE=<file>] \
#   bash .planning/phases/17.1-close-gap-int-1-int-2-release-and-pin-a-libmpv-bundle-with-t/tools/run_gate.sh \
#     RUN_ID \
#     [--jobs-success <job-name ERE>]... \
#     [--jobs-skipped <job-name ERE>]... \
#     [--log <job-name ERE> <line ERE>]... \
#     [--log-absent <job-name ERE> <line ERE>]...
#
#   RUN_GATE_LABEL     required; free text written into the record line
#   RUN_GATE_EXPECT_SHA  optional; the run's headSha must equal it
#   RUN_GATE_EVIDENCE  record file (default: ../evidence/release-runs.txt
#                      next to this script)
#
#   --jobs-success RE  at least one job whose name matches RE, and every
#                      matching job concluded `success`.
#   --jobs-skipped RE  at least one job whose name matches RE, and every
#                      matching job concluded `skipped` (proves that the
#                      publish job did not run).
#   --log JRE LRE      in `gh run view <id> --log` (format: job<TAB>rest), at
#                      least one line whose job field matches JRE and whose
#                      rest matches LRE (grep -E search, not a full-line match).
#   --log-absent JRE LRE
#                      at least one job whose name matches JRE, and none of
#                      those jobs has a line matching LRE.
#
# The run is recorded as one line
#   label=<l> run=<id> event=<e> ref=<headBranch> sha=<headSha> conclusion=<c> jobs=<name:conclusion,...>
#
# exit codes:
#   0  RUN-GATE ok
#   1  usage error, or the run concluded anything other than success
#   2  RUN-GATE wrong-sha: headSha differs from RUN_GATE_EXPECT_SHA
#   3  a --jobs-success / --jobs-skipped / --log / --log-absent expectation is not met
set -euo pipefail

# 60 polls x 120 s = the 2-hour ceiling for the run to finish.
readonly MAX_POLLS=60
readonly POLL_SECONDS=120

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE="${RUN_GATE_EVIDENCE:-$SCRIPT_DIR/../evidence/release-runs.txt}"

[ $# -ge 1 ] || { echo "RUN-GATE usage: RUN_ID [expectations]" >&2; exit 1; }
RUN_ID=$1; shift
case "$RUN_ID" in
  ''|*[!0-9]*) echo "RUN-GATE usage: RUN_ID must be numeric" >&2; exit 1 ;;
esac
LABEL="${RUN_GATE_LABEL:-}"
[ -n "$LABEL" ] || { echo "RUN-GATE usage: RUN_GATE_LABEL is required" >&2; exit 1; }

jobs_success=()
jobs_skipped=()
log_jobs=()
log_lines=()
absent_jobs=()
absent_lines=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-success)
      [ $# -ge 2 ] || { echo "RUN-GATE usage: --jobs-success <re>" >&2; exit 1; }
      jobs_success+=("$2"); shift 2 ;;
    --jobs-skipped)
      [ $# -ge 2 ] || { echo "RUN-GATE usage: --jobs-skipped <re>" >&2; exit 1; }
      jobs_skipped+=("$2"); shift 2 ;;
    --log)
      [ $# -ge 3 ] || { echo "RUN-GATE usage: --log <job-re> <line-re>" >&2; exit 1; }
      log_jobs+=("$2"); log_lines+=("$3"); shift 3 ;;
    --log-absent)
      [ $# -ge 3 ] || { echo "RUN-GATE usage: --log-absent <job-re> <line-re>" >&2; exit 1; }
      absent_jobs+=("$2"); absent_lines+=("$3"); shift 3 ;;
    *)
      echo "RUN-GATE usage: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$EVIDENCE")"

# Wait for the run to complete (a finished run returns on the first poll).
status=''
for _ in $(seq 1 "$MAX_POLLS"); do
  status=$(gh run view "$RUN_ID" --json status --jq .status)
  [ "$status" = completed ] && break
  sleep "$POLL_SECONDS"
done
if [ "$status" != completed ]; then
  echo "RUN-GATE timeout run=$RUN_ID status=$status"
  exit 1
fi

conclusion=$(gh run view "$RUN_ID" --json conclusion --jq .conclusion)
head_sha=$(gh run view "$RUN_ID" --json headSha --jq .headSha)
event=$(gh run view "$RUN_ID" --json event --jq .event)
head_branch=$(gh run view "$RUN_ID" --json headBranch --jq .headBranch)
gh run view "$RUN_ID" --json jobs \
  --jq '.jobs[] | [.name, (.conclusion // "")] | @tsv' > "$WORK/jobs.tsv"
jobs_summary=$(awk -F'\t' '{ printf "%s%s:%s", (NR > 1 ? "," : ""), $1, $2 }' "$WORK/jobs.tsv")
echo "label=$LABEL run=$RUN_ID event=$event ref=$head_branch sha=$head_sha conclusion=$conclusion jobs=$jobs_summary" >> "$EVIDENCE"

if [ -n "${RUN_GATE_EXPECT_SHA:-}" ] && [ "$RUN_GATE_EXPECT_SHA" != "$head_sha" ]; then
  echo "RUN-GATE wrong-sha run=$RUN_ID sha=$head_sha expected=$RUN_GATE_EXPECT_SHA"
  exit 2
fi

if [ "$conclusion" != success ]; then
  echo "RUN-GATE fail run=$RUN_ID ($conclusion)"
  exit 1
fi

unmet=0

# check_jobs <expected conclusion> <flag name> <ERE>
check_jobs() {
  local want=$1 flag=$2 re=$3 name concl
  if ! cut -f1 "$WORK/jobs.tsv" | grep -Eq -- "$re"; then
    echo "RUN-GATE unmet $flag '$re': no job matches"
    unmet=1; return
  fi
  while IFS=$'\t' read -r name concl; do
    if printf '%s\n' "$name" | grep -Eq -- "$re" && [ "$concl" != "$want" ]; then
      echo "RUN-GATE unmet $flag '$re': '$name' is '${concl:-none}'"
      unmet=1
    fi
  done < "$WORK/jobs.tsv"
}

for re in ${jobs_success[@]+"${jobs_success[@]}"}; do
  check_jobs success --jobs-success "$re"
done
for re in ${jobs_skipped[@]+"${jobs_skipped[@]}"}; do
  check_jobs skipped --jobs-skipped "$re"
done

if [ ${#log_jobs[@]} -gt 0 ] || [ ${#absent_jobs[@]} -gt 0 ]; then
  gh run view "$RUN_ID" --log > "$WORK/log.txt"
  cut -f1 "$WORK/log.txt" | sort -u > "$WORK/log_jobs"
  for i in "${!log_jobs[@]}"; do
    jre=${log_jobs[$i]}
    lre=${log_lines[$i]}
    hit=0
    while IFS= read -r name; do
      # Exact job-field compare via ENVIRON (no awk escape processing), then
      # grep -E over the rest of each of that job's lines.
      JOB="$name" awk -F'\t' '$1 == ENVIRON["JOB"] { print substr($0, length($1) + 2) }' \
        "$WORK/log.txt" > "$WORK/rest"
      if grep -Eq -- "$lre" "$WORK/rest"; then hit=1; break; fi
    done < <(grep -E -- "$jre" "$WORK/log_jobs" || true)
    if [ "$hit" -ne 1 ]; then
      echo "RUN-GATE unmet --log '$jre' '$lre'"
      unmet=1
    fi
  done
  # --log-absent: some job matches JRE, and no matching job has a line
  # matching LRE.
  for i in "${!absent_jobs[@]}"; do
    jre=${absent_jobs[$i]}
    lre=${absent_lines[$i]}
    grep -E -- "$jre" "$WORK/log_jobs" > "$WORK/absent_match" || true
    if [ ! -s "$WORK/absent_match" ]; then
      echo "RUN-GATE unmet --log-absent '$jre' '$lre': no job matches"
      unmet=1; continue
    fi
    while IFS= read -r name; do
      JOB="$name" awk -F'\t' '$1 == ENVIRON["JOB"] { print substr($0, length($1) + 2) }' \
        "$WORK/log.txt" > "$WORK/rest"
      if grep -Eq -- "$lre" "$WORK/rest"; then
        echo "RUN-GATE unmet --log-absent '$jre' '$lre': '$name' has a matching line"
        unmet=1
      fi
    done < "$WORK/absent_match"
  done
fi

if [ "$unmet" -ne 0 ]; then
  echo "RUN-GATE fail run=$RUN_ID (expectations)"
  exit 3
fi
echo "RUN-GATE ok run=$RUN_ID sha=$head_sha"
