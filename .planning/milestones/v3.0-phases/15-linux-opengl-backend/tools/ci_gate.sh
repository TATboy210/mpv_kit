#!/usr/bin/env bash
# Phase 15 copy of the Phase 12 hosted-CI gate (CI_GATE_EVIDENCE overrides the record file): waits for the native-verify and flutter-plugin runs
# of one pushed SHA, then asserts job conclusions and log lines.
#
# usage:
#   bash .planning/phases/12-renderbackend-seam/tools/ci_gate.sh \
#     [--jobs-success <job-name ERE>]... \
#     [--log <job-name ERE> <line ERE>]...
#
#   CI_GATE_SHA          target commit (default: git rev-parse HEAD)
#   CI_GATE_RERUN_INFRA  set to 1 ONLY after reading --log-failed and judging
#                        the failure an infrastructure flake (runner lost,
#                        network to a package mirror, ...): the failed jobs
#                        are rerun once with `gh run rerun --failed`. Test
#                        failures are never rerun.
#
#   --jobs-success RE  at least one job (either workflow) whose name matches
#                      RE, and every matching job concluded `success`
#                      (skipped/cancelled/failure all fail the gate).
#   --log JRE LRE      in `gh run view <id> --log` (format: job<TAB>rest),
#                      at least one line whose job field matches JRE and
#                      whose rest matches LRE (grep -E search, not a full
#                      line match).
#
# Every workflow result is appended to evidence/ci-runs.txt as
#   sha=<sha> workflow=<wf> run=<id> conclusion=<c>
# and an infra rerun adds a `rerun sha=... run=<id> attempt=<n>` line before
# the rerun's own result line, so both attempts stay on record.
#
# exit codes:
#   0  CI-GATE ok: both workflows succeeded and every expectation held
#   2  CI-GATE not pushed: the SHA is not on origin/feat/mpv-master-upgrade
#   3  a --jobs-success or --log expectation is not met
#   4  no run for the SHA appeared within 20 minutes
#   1  a workflow concluded anything other than success / usage error
set -euo pipefail

readonly BRANCH=feat/mpv-master-upgrade
readonly WORKFLOWS=(native-verify.yml flutter-plugin.yml)
# 40 polls x 30 s = the 20-minute ceiling for a run to be created.
readonly FIND_POLLS=40
readonly POLL_SECONDS=30

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE="${CI_GATE_EVIDENCE:-$SCRIPT_DIR/../evidence/ci-runs.txt}"

jobs_success=()
log_jobs=()
log_lines=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-success)
      [ $# -ge 2 ] || { echo "CI-GATE usage: --jobs-success <re>" >&2; exit 1; }
      jobs_success+=("$2"); shift 2 ;;
    --log)
      [ $# -ge 3 ] || { echo "CI-GATE usage: --log <job-re> <line-re>" >&2; exit 1; }
      log_jobs+=("$2"); log_lines+=("$3"); shift 3 ;;
    *)
      echo "CI-GATE usage: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

SHA=$(git rev-parse "${CI_GATE_SHA:-HEAD}")

# The gate can only judge what hosted CI saw: refuse unpushed commits.
git fetch --quiet origin "$BRANCH"
if ! git merge-base --is-ancestor "$SHA" "origin/$BRANCH"; then
  echo "CI-GATE not pushed sha=$SHA"
  exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$EVIDENCE")"

record() { echo "$*" >> "$EVIDENCE"; }

# Prints the newest run id of workflow $1 whose headSha is $SHA, or nothing.
find_run() {
  gh run list --branch "$BRANCH" --workflow "$1" --limit 50 \
    --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$SHA\") | .databaseId" | head -1
}

# Waits for run $1 to finish; prints its conclusion.
watch_run() {
  # --exit-status only shortens the wait on failure; the verdict comes from
  # the conclusion read afterwards.
  gh run watch "$1" --exit-status --interval "$POLL_SECONDS" >/dev/null 2>&1 || true
  gh run view "$1" --json conclusion --jq .conclusion
}

failed=0
run_ids=()
for wf in "${WORKFLOWS[@]}"; do
  id=''
  for _ in $(seq 1 "$FIND_POLLS"); do
    id=$(find_run "$wf")
    [ -n "$id" ] && break
    sleep "$POLL_SECONDS"
  done
  if [ -z "$id" ]; then
    echo "CI-GATE no run sha=$SHA workflow=$wf"
    exit 4
  fi
  conclusion=$(watch_run "$id")
  record "sha=$SHA workflow=$wf run=$id conclusion=$conclusion"
  if [ "$conclusion" != success ] && [ "${CI_GATE_RERUN_INFRA:-0}" = 1 ]; then
    gh run rerun "$id" --failed
    attempt=$(gh run view "$id" --json attempt --jq .attempt)
    record "rerun sha=$SHA workflow=$wf run=$id attempt=$attempt reason=infra"
    # The rerun is allowed once per invocation; never chain more.
    CI_GATE_RERUN_INFRA=0
    sleep "$POLL_SECONDS"
    conclusion=$(watch_run "$id")
    record "sha=$SHA workflow=$wf run=$id conclusion=$conclusion"
  fi
  echo "CI-GATE workflow=$wf run=$id conclusion=$conclusion"
  [ "$conclusion" = success ] || failed=1
  run_ids+=("$id")
  gh run view "$id" --json jobs \
    --jq '.jobs[] | [.name, (.conclusion // "")] | @tsv' >> "$WORK/jobs.tsv"
done

if [ "$failed" -ne 0 ]; then
  echo "CI-GATE fail sha=$SHA (workflow conclusion)"
  exit 1
fi

unmet=0
for re in ${jobs_success[@]+"${jobs_success[@]}"}; do
  cut -f1 "$WORK/jobs.tsv" | grep -E -- "$re" > "$WORK/match" || true
  if [ ! -s "$WORK/match" ]; then
    echo "CI-GATE unmet --jobs-success '$re': no job matches"
    unmet=1; continue
  fi
  # A job name the regex matched whose conclusion is not success (skipped
  # included) fails the expectation.
  while IFS=$'\t' read -r name concl; do
    if printf '%s\n' "$name" | grep -Eq -- "$re" && [ "$concl" != success ]; then
      echo "CI-GATE unmet --jobs-success '$re': '$name' is '${concl:-none}'"
      unmet=1
    fi
  done < "$WORK/jobs.tsv"
done

if [ ${#log_jobs[@]} -gt 0 ]; then
  for id in "${run_ids[@]}"; do
    gh run view "$id" --log >> "$WORK/log.txt"
  done
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
      echo "CI-GATE unmet --log '$jre' '$lre'"
      unmet=1
    fi
  done
fi

if [ "$unmet" -ne 0 ]; then
  echo "CI-GATE fail sha=$SHA (expectations)"
  exit 3
fi
echo "CI-GATE ok sha=$SHA"
