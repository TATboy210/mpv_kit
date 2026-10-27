#!/usr/bin/env bash
# Phase 15 release-layer gate: dispatches release.yml on the feature BRANCH ref
# (never a tag, so the publish job is skipped), waits for the run, then asserts
# job conclusions and log lines. Same conventions as ci_gate.sh.
#
# usage:
#   bash .planning/phases/15-linux-opengl-backend/tools/release_gate.sh \
#     [--jobs-success <job-name ERE>]... \
#     [--jobs-skipped <job-name ERE>]... \
#     [--log <job-name ERE> <line ERE>]...
#
#   CI_GATE_SHA          target commit (default: git rev-parse HEAD)
#   CI_GATE_EVIDENCE     record file (default: ../evidence/release-runs.txt)
#
#   --jobs-success RE  at least one job whose name matches RE, and every
#                      matching job concluded `success`.
#   --jobs-skipped RE  at least one job whose name matches RE, and every
#                      matching job concluded `skipped` (proves that the
#                      publish job did not run).
#   --log JRE LRE      in `gh run view <id> --log` (format: job<TAB>rest), at
#                      least one line whose job field matches JRE and whose
#                      rest matches LRE (grep -E search, not a full-line match).
#
# The run is recorded in the evidence file as one line
#   sha=<sha> workflow=release.yml run=<id> conclusion=<c> jobs=<name:conclusion,...>
# A release build that fails is recorded as it is; there is no rerun option.
#
# exit codes:
#   0  RELEASE-GATE ok
#   1  usage error
#   2  RELEASE-GATE not pushed: the SHA is not on origin/feat/mpv-master-upgrade
#   3  a --jobs-success / --jobs-skipped / --log expectation is not met
#   4  no matching workflow_dispatch run appeared within 20 minutes
set -euo pipefail

readonly BRANCH=feat/mpv-master-upgrade
readonly WORKFLOW=release.yml
# 40 polls x 30 s = the 20-minute ceiling for the run to appear.
readonly FIND_POLLS=40
readonly POLL_SECONDS=30

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE="${CI_GATE_EVIDENCE:-$SCRIPT_DIR/../evidence/release-runs.txt}"

jobs_success=()
jobs_skipped=()
log_jobs=()
log_lines=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jobs-success)
      [ $# -ge 2 ] || { echo "RELEASE-GATE usage: --jobs-success <re>" >&2; exit 1; }
      jobs_success+=("$2"); shift 2 ;;
    --jobs-skipped)
      [ $# -ge 2 ] || { echo "RELEASE-GATE usage: --jobs-skipped <re>" >&2; exit 1; }
      jobs_skipped+=("$2"); shift 2 ;;
    --log)
      [ $# -ge 3 ] || { echo "RELEASE-GATE usage: --log <job-re> <line-re>" >&2; exit 1; }
      log_jobs+=("$2"); log_lines+=("$3"); shift 3 ;;
    *)
      echo "RELEASE-GATE usage: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

SHA=$(git rev-parse "${CI_GATE_SHA:-HEAD}")

# The gate can only judge what hosted CI saw: refuse unpushed commits.
git fetch --quiet origin "$BRANCH"
if ! git merge-base --is-ancestor "$SHA" "origin/$BRANCH"; then
  echo "RELEASE-GATE not pushed sha=$SHA"
  exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$EVIDENCE")"

# Dispatch on the branch ref only: the publish job is conditioned on a tag ref.
dispatched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh workflow run "$WORKFLOW" --ref "$BRANCH"

# Newest workflow_dispatch run created after the dispatch whose headSha is the
# target SHA, or a descendant of it when the branch moved in the meantime
# (ancestry proven with git; the SHA actually used goes into the record).
RUN_SHA=''
find_run() {
  local rows id head
  rows=$(gh run list --workflow "$WORKFLOW" --branch "$BRANCH" --event workflow_dispatch \
    --limit 20 --json databaseId,headSha,createdAt \
    --jq ".[] | select(.createdAt >= \"$dispatched_at\") | [.databaseId, .headSha] | @tsv")
  while IFS=$'\t' read -r id head; do
    [ -n "$id" ] || continue
    if [ "$head" = "$SHA" ] ||
       { git cat-file -e "$head^{commit}" 2>/dev/null && git merge-base --is-ancestor "$SHA" "$head"; }; then
      RUN_SHA=$head
      echo "$id"
      return 0
    fi
  done <<< "$rows"
  return 0
}

id=''
for _ in $(seq 1 "$FIND_POLLS"); do
  git fetch --quiet origin "$BRANCH" || true
  id=$(find_run)
  [ -n "$id" ] && break
  sleep "$POLL_SECONDS"
done
if [ -z "$id" ]; then
  echo "RELEASE-GATE no run sha=$SHA"
  exit 4
fi

# --exit-status only shortens the wait on failure; the verdict is read from the
# run and its jobs afterwards.
gh run watch "$id" --exit-status --interval "$POLL_SECONDS" >/dev/null 2>&1 || true
conclusion=$(gh run view "$id" --json conclusion --jq .conclusion)
gh run view "$id" --json jobs \
  --jq '.jobs[] | [.name, (.conclusion // "")] | @tsv' > "$WORK/jobs.tsv"
jobs_summary=$(awk -F'\t' '{ printf "%s%s:%s", (NR > 1 ? "," : ""), $1, $2 }' "$WORK/jobs.tsv")
echo "sha=$RUN_SHA workflow=$WORKFLOW run=$id conclusion=$conclusion jobs=$jobs_summary" >> "$EVIDENCE"
echo "RELEASE-GATE run=$id conclusion=$conclusion sha=$RUN_SHA"

# windows/macos jobs are recorded but not judged here, so the run conclusion
# (which includes them) is informational; only the expectations decide.
unmet=0

# check_jobs <expected conclusion> <flag name> <ERE>
check_jobs() {
  local want=$1 flag=$2 re=$3 name concl
  if ! cut -f1 "$WORK/jobs.tsv" | grep -Eq -- "$re"; then
    echo "RELEASE-GATE unmet $flag '$re': no job matches"
    unmet=1; return
  fi
  while IFS=$'\t' read -r name concl; do
    if printf '%s\n' "$name" | grep -Eq -- "$re" && [ "$concl" != "$want" ]; then
      echo "RELEASE-GATE unmet $flag '$re': '$name' is '${concl:-none}'"
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

if [ ${#log_jobs[@]} -gt 0 ]; then
  gh run view "$id" --log > "$WORK/log.txt"
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
      echo "RELEASE-GATE unmet --log '$jre' '$lre'"
      unmet=1
    fi
  done
fi

if [ "$unmet" -ne 0 ]; then
  echo "RELEASE-GATE fail sha=$RUN_SHA (expectations)"
  exit 3
fi
echo "RELEASE-GATE ok sha=$RUN_SHA run=$id"
