#!/usr/bin/env bash
# Phase 14 hosted-CI gate: waits for the workflow runs of one pushed SHA on one
# branch, then asserts job conclusions and log lines.
#
# Derived line by line from .planning/phases/12-renderbackend-seam/tools/ci_gate.sh
# (set -euo pipefail, FIND_POLLS/POLL_SECONDS, the one-shot infra rerun, exit
# codes 0/1/2/3/4 and every assertion are unchanged). Three differences:
#   1. The branch comes from CI_GATE_BRANCH (default feat/mpv-master-upgrade);
#      the "pushed" check is `git fetch origin <branch>` + "is the SHA an
#      ancestor of origin/<branch>". Scratch branches (ci/14-*) work the same.
#   2. --workflow <file> (repeatable) selects the workflows to wait for. Without
#      it the gate waits for native-verify.yml and flutter-plugin.yml as before.
#   3. The evidence file comes from CI_GATE_EVIDENCE (default
#      <script dir>/../evidence/ci-runs.txt) and every record line carries a
#      `branch=<branch>` field.
#
# usage:
#   [CI_GATE_BRANCH=<branch>] [CI_GATE_SHA=<sha>] [CI_GATE_EVIDENCE=<file>] \
#   bash .planning/phases/14-windows-native-d3d11-backend/tools/ci_gate.sh \
#     [--workflow <file>]... \
#     [--jobs-success <job-name ERE>]... \
#     [--log <job-name ERE> <line ERE>]...
#
#   dispatching a workflow first (release.yml has no push trigger on feat):
#     gh workflow run release.yml --ref <branch>
#     CI_GATE_BRANCH=<branch> bash .../ci_gate.sh --workflow release.yml ...
#   (a dispatch run's headSha is the branch tip, so push first, then dispatch,
#   then call the gate with CI_GATE_SHA unset or equal to that tip.)
#
#   CI_GATE_BRANCH       branch whose runs are judged (default feat/mpv-master-upgrade)
#   CI_GATE_SHA          target commit (default: git rev-parse HEAD)
#   CI_GATE_EVIDENCE     evidence file to append record lines to
#   CI_GATE_RERUN_INFRA  set to 1 ONLY after reading --log-failed and judging
#                        the failure an infrastructure flake (runner lost,
#                        network to a package mirror, ...): the failed jobs
#                        are rerun once with `gh run rerun --failed`. Test
#                        failures are never rerun.
#
#   --workflow WF      wait for this workflow file (repeatable; replaces the
#                      default pair).
#   --jobs-success RE  at least one job (any waited workflow) whose name matches
#                      RE, and every matching job concluded `success`
#                      (skipped/cancelled/failure all fail the gate).
#   --log JRE LRE      in `gh run view <id> --log` (format: job<TAB>rest),
#                      at least one line whose job field matches JRE and
#                      whose rest matches LRE (grep -E search, not a full
#                      line match).
#
# Every workflow result is appended to the evidence file as
#   sha=<sha> branch=<branch> workflow=<wf> run=<id> conclusion=<c>
# and an infra rerun adds a `rerun sha=... branch=... run=<id> attempt=<n>`
# line before the rerun's own result line, so both attempts stay on record.
#
# exit codes:
#   0  CI-GATE ok: every waited workflow succeeded and every expectation held
#   2  CI-GATE not pushed: the SHA is not on origin/<branch>
#   3  a --jobs-success or --log expectation is not met
#   4  no run for the SHA appeared within 20 minutes
#   1  a workflow concluded anything other than success / usage error
set -euo pipefail

readonly BRANCH=${CI_GATE_BRANCH:-feat/mpv-master-upgrade}
readonly DEFAULT_WORKFLOWS=(native-verify.yml flutter-plugin.yml)
# 40 polls x 30 s = the 20-minute ceiling for a run to be created.
readonly FIND_POLLS=40
readonly POLL_SECONDS=30

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE=${CI_GATE_EVIDENCE:-$SCRIPT_DIR/../evidence/ci-runs.txt}

workflows=()
jobs_success=()
log_jobs=()
log_lines=()
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow)
      [ $# -ge 2 ] || { echo "CI-GATE usage: --workflow <file>" >&2; exit 1; }
      workflows+=("$2"); shift 2 ;;
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
[ ${#workflows[@]} -gt 0 ] || workflows=("${DEFAULT_WORKFLOWS[@]}")

SHA=$(git rev-parse "${CI_GATE_SHA:-HEAD}")

# The gate can only judge what hosted CI saw: refuse unpushed commits.
git fetch --quiet origin "$BRANCH"
if ! git merge-base --is-ancestor "$SHA" "origin/$BRANCH"; then
  echo "CI-GATE not pushed sha=$SHA branch=$BRANCH"
  exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$EVIDENCE")"

record() { echo "$*" >> "$EVIDENCE"; }

# Prints the newest run id of workflow $1 whose headSha is $SHA, or nothing.
# `gh run list --workflow <file>` cannot resolve a workflow file that exists
# only on a non-default branch (scratch probes); in that case fall back to the
# Actions REST API, filtered by branch + head_sha, matching the run's `path`.
find_run() {
  local id
  if id=$(gh run list --branch "$BRANCH" --workflow "$1" --limit 50 \
    --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$SHA\") | .databaseId" 2>/dev/null); then
    printf '%s\n' "$id" | head -1
    return 0
  fi
  gh api "repos/{owner}/{repo}/actions/runs?branch=$BRANCH&head_sha=$SHA&per_page=100" \
    --jq ".workflow_runs[] | select(.path | startswith(\".github/workflows/$1\")) | .id" \
    2>/dev/null | head -1 || true
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
for wf in "${workflows[@]}"; do
  id=''
  for _ in $(seq 1 "$FIND_POLLS"); do
    id=$(find_run "$wf")
    [ -n "$id" ] && break
    sleep "$POLL_SECONDS"
  done
  if [ -z "$id" ]; then
    echo "CI-GATE no run sha=$SHA branch=$BRANCH workflow=$wf"
    exit 4
  fi
  conclusion=$(watch_run "$id")
  record "sha=$SHA branch=$BRANCH workflow=$wf run=$id conclusion=$conclusion"
  if [ "$conclusion" != success ] && [ "${CI_GATE_RERUN_INFRA:-0}" = 1 ]; then
    gh run rerun "$id" --failed
    attempt=$(gh run view "$id" --json attempt --jq .attempt)
    record "rerun sha=$SHA branch=$BRANCH workflow=$wf run=$id attempt=$attempt reason=infra"
    # The rerun is allowed once per invocation; never chain more.
    CI_GATE_RERUN_INFRA=0
    sleep "$POLL_SECONDS"
    conclusion=$(watch_run "$id")
    record "sha=$SHA branch=$BRANCH workflow=$wf run=$id conclusion=$conclusion"
  fi
  echo "CI-GATE workflow=$wf run=$id conclusion=$conclusion"
  [ "$conclusion" = success ] || failed=1
  run_ids+=("$id")
  gh run view "$id" --json jobs \
    --jq '.jobs[] | [.name, (.conclusion // "")] | @tsv' >> "$WORK/jobs.tsv"
done

if [ "$failed" -ne 0 ]; then
  echo "CI-GATE fail sha=$SHA branch=$BRANCH (workflow conclusion)"
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
  echo "CI-GATE fail sha=$SHA branch=$BRANCH (expectations)"
  exit 3
fi
echo "CI-GATE ok sha=$SHA"
