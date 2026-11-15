#!/usr/bin/env bash
# Phase 16 hosted-CI gate (copy of the Phase 13 gate; only the EVIDENCE path is
# overridable via CI_GATE_EVIDENCE): waits for the configured workflow runs (default
# native-verify and flutter-plugin) of one pushed SHA, then asserts job
# conclusions and log lines. Copied from the Phase 12 gate with four changes:
# the workflow list is configurable, runs are picked by workflowName,
# --log-absent exists, and the rerun rule admits the registered golden flake.
#
# usage:
#   bash .planning/phases/16-hardware-decode-zero-copy/tools/ci_gate.sh \
#     [--jobs-success <job-name ERE>]... \
#     [--log <job-name ERE> <line ERE>]... \
#     [--log-absent <job-name ERE> <line ERE>]...
#
#   CI_GATE_SHA          target commit (default: git rev-parse HEAD)
#   CI_GATE_WORKFLOWS    space-separated workflow file names to wait for
#                        (default: native-verify.yml flutter-plugin.yml)
#   CI_GATE_EVIDENCE     evidence file to append run records to (default:
#                        ../evidence/ci-runs.txt next to this script); parallel
#                        plans use their own ci-runs-16-0N.txt
#   CI_GATE_RERUN_INFRA  set to 1 ONLY after reading --log-failed and judging
#                        the failure either an infrastructure flake (runner
#                        lost, network to a package mirror, ...) or exactly
#                        `GOLDEN mismatch scenario=vk-gpu-timeout` in the
#                        macos (macos-15) job (the registered flake, todo
#                        2026-10-27-vk-gpu-timeout-golden-flake-macos.md).
#                        The failed jobs are rerun at most once per
#                        invocation with `gh run rerun --failed`, and both
#                        attempts are recorded. Any other test failure is
#                        never rerun.
#
#   --jobs-success RE  at least one job (either workflow) whose name matches
#                      RE, and every matching job concluded `success`
#                      (skipped/cancelled/failure all fail the gate).
#   --log JRE LRE      in `gh run view <id> --log` (format: job<TAB>rest),
#                      at least one line whose job field matches JRE and
#                      whose rest matches LRE (grep -E search, not a full
#                      line match).
#   --log-absent JRE LRE
#                      at least one job whose name matches JRE, and none of
#                      those jobs has a line matching LRE (same log format).
#
# Every workflow result is appended to evidence/ci-runs.txt as
#   sha=<sha> workflow=<wf> run=<id> conclusion=<c>
# and an infra rerun adds a `rerun sha=... run=<id> attempt=<n>` line before
# the rerun's own result line, so both attempts stay on record.
#
# exit codes:
#   0  CI-GATE ok: both workflows succeeded and every expectation held
#   2  CI-GATE not pushed: the SHA is not on origin/feat/mpv-master-upgrade
#   3  a --jobs-success, --log or --log-absent expectation is not met
#   4  no run for the SHA appeared within 20 minutes
#   1  a workflow concluded anything other than success / usage error
set -euo pipefail

readonly BRANCH=feat/mpv-master-upgrade
# Word splitting of the list is intended.
# shellcheck disable=SC2206
readonly WORKFLOWS=(${CI_GATE_WORKFLOWS:-native-verify.yml flutter-plugin.yml})
# 40 polls x 30 s = the 20-minute ceiling for a run to be created.
readonly FIND_POLLS=40
readonly POLL_SECONDS=30

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE="${CI_GATE_EVIDENCE:-$SCRIPT_DIR/../evidence/ci-runs.txt}"

jobs_success=()
log_jobs=()
log_lines=()
absent_jobs=()
absent_lines=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-success)
      [ $# -ge 2 ] || { echo "CI-GATE usage: --jobs-success <re>" >&2; exit 1; }
      jobs_success+=("$2"); shift 2 ;;
    --log)
      [ $# -ge 3 ] || { echo "CI-GATE usage: --log <job-re> <line-re>" >&2; exit 1; }
      log_jobs+=("$2"); log_lines+=("$3"); shift 3 ;;
    --log-absent)
      [ $# -ge 3 ] || { echo "CI-GATE usage: --log-absent <job-re> <line-re>" >&2; exit 1; }
      absent_jobs+=("$2"); absent_lines+=("$3"); shift 3 ;;
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

# Prints the newest run id of workflow file $1 whose headSha is $SHA, or
# nothing. Selected by workflowName (the file name without .yml) so a
# workflow that is not on the default branch yet is found too.
find_run() {
  gh run list --branch "$BRANCH" --limit 100 \
    --json databaseId,headSha,workflowName \
    --jq ".[] | select(.headSha == \"$SHA\" and .workflowName == \"${1%.yml}\") | .databaseId" | head -1
}

# Waits for run $1 to finish; prints its conclusion.
watch_run() {
  # --exit-status only shortens the wait on failure; the verdict comes from
  # the conclusion read afterwards.
  gh run watch "$1" --exit-status --interval "$POLL_SECONDS" >/dev/null 2>&1 || true
  # `gh run watch` can return early (dropped connection) while the run is
  # still in progress; an empty conclusion must never be judged. Poll the
  # status until completed (at most 90 x 30 s = 45 minutes).
  for _ in $(seq 1 90); do
    [ "$(gh run view "$1" --json status --jq .status)" = completed ] && break
    sleep "$POLL_SECONDS"
  done
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

if [ ${#log_jobs[@]} -gt 0 ] || [ ${#absent_jobs[@]} -gt 0 ]; then
  for id in "${run_ids[@]}"; do
    gh run view "$id" --log >> "$WORK/log.txt"
  done
  cut -f1 "$WORK/log.txt" | sort -u > "$WORK/log_jobs"
  for ((i = 0; i < ${#log_jobs[@]}; i++)); do
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

# --log-absent: some job matches JRE, and no matching job has a line
# matching LRE. Every job's log was gathered above (log_jobs file).
for ((i = 0; i < ${#absent_jobs[@]}; i++)); do
  jre=${absent_jobs[$i]}
  lre=${absent_lines[$i]}
  grep -E -- "$jre" "$WORK/log_jobs" > "$WORK/absent_match" || true
  if [ ! -s "$WORK/absent_match" ]; then
    echo "CI-GATE unmet --log-absent '$jre' '$lre': no job matches"
    unmet=1; continue
  fi
  while IFS= read -r name; do
    JOB="$name" awk -F'\t' '$1 == ENVIRON["JOB"] { print substr($0, length($1) + 2) }' \
      "$WORK/log.txt" > "$WORK/rest"
    if grep -Eq -- "$lre" "$WORK/rest"; then
      echo "CI-GATE unmet --log-absent '$jre' '$lre': '$name' has a matching line"
      unmet=1
    fi
  done < "$WORK/absent_match"
done

if [ "$unmet" -ne 0 ]; then
  echo "CI-GATE fail sha=$SHA (expectations)"
  exit 3
fi
echo "CI-GATE ok sha=$SHA"
