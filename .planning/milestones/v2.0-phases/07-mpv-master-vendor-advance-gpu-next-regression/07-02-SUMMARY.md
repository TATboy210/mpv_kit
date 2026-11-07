---
phase: 07-mpv-master-vendor-advance-gpu-next-regression
plan: 02
subsystem: regression
tags: [seek, endurance, environment]
requires:
  - phase: 07-01
    provides: "The advanced vendor + exact-provenance finding"
provides:
  - "seek_recovery_test.dart: effective seeks recover (position window + frames flowing + no storm), MPV_KIT_SEEK_MEDIA override for both-direction coverage"
  - "Empirically pinned lavfi seek semantics (forward/near-end land; backward/to-zero are no-ops)"
  - "Regression record with build-source justification and the disk-full 4K blocker"
affects: [08-*]
actuals:
  tokens: 52000
  tasks: 2
  commits: 1
tech-stack:
  added: []
  patterns:
    - "Recovery window predicate: pos ∈ [target, target+10s] ∧ fps ≠ null (robust to landing + playback)"
key-files:
  created:
    - example/integration_test/seek_recovery_test.dart
    - docs/perf/2026-10-24-vendor-advance-regression.md
  modified: []
key-decisions:
  - "Build-source justification: local rebuild impossible (no MSYS2/meson; native/out was a CI unpack); the dev.3 hook build's source is byte-identical to the new vendor (except MPV_VERSION) — regression against it IS regression against the new source; CI re-builds from the tree on push"
  - "4K endurance marked environment-blocked (host disk 100%), NOT a code regression: no new WER (unlike v1 8K), same binary passed 4K 30-min earlier the same day, CMakeCache truncation independently reproduced the disk-full signature"
  - "lavfi backward-seek no-op documented as a source property; real-media coverage deferred to MPV_KIT_SEEK_MEDIA (pairs with Phase 8 drag-and-drop)"
patterns-established: []
requirements-completed: []
requirements-partial: [REBASE-02]
coverage:
  - id: D4
    description: "seek_recovery green with RED evidence; semantics pinned; media override hook"
    requirement: REBASE-02
    verification:
      - kind: automated_ui
        ref: "SEEK-RECOVERY OK media=lavfi events=[]; pre-fix run failed (pos outside window)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Full suites + api_freeze + decode bench green; decode within v1 noise band"
    requirement: REBASE-02
    verification:
      - kind: automated
        ref: "112/2, 21, api_freeze, BENCH 130/1088 ns/op"
        status: pass
    human_judgment: false
  - id: D6
    description: "4K 30-min endurance: blocked by host disk full (D: 100%);解除条件与证据记录在 docs/perf — same binary passed the same day"
    requirement: REBASE-02
    verification:
      - kind: automated
        ref: "docs/perf/2026-10-24-vendor-advance-regression.md §4K; disk df evidence; no new WER"
        status: blocked
    human_judgment: true
duration: 95 min
completed: 2026-10-24
status: complete
plan_head_before: 9590dca
plan_head_after: d193173
commits: 1
---

# Phase 07 Plan 02: Regression Summary

**seek 恢复、全套件、基准全绿；4K 30 分钟被宿主磁盘写满阻塞（非代码回归，证据链完整），解除条件已记录。**

## Performance

- Duration: 95 min（含多次 4K 尝试与根因排查）; Tasks: 2/2; Commits: 1
- Token estimate 44000 vs realized ~52000（环境排查）

## Accomplishments

- Build-source decision recorded（dev.3 字节等同论证；CI push 后真实重建）。
- seek_recovery_test.dart：三次迭代收敛（keyframe→exact；模式重排——near-end 必须最后，lavfi 后退为空操作）；RED 证据为首次失败运行。
- 全套件 + api_freeze + decode 基准全绿。
- 4K 尝试 ×4 失败 → 根因定位：**D 盘 100% 满**（CMakeCache 截断复现 + 无新 WER + 同二进制当日 15:56 通过 30 分钟）；回归记录完整落盘。

## Task Commits

1. `d193173` — test(video): seek-recovery regression（含语义钉死与 RED 证据）

## TDD Gate Compliance

| RED | GREEN |
|-----|-------|
| 首次运行（keyframe seek + 错序）pos=11.5 在窗口外失败 | SEEK-RECOVERY OK（三模式精确落位） |

## Deviations from Plan

1. `[Rule 1 - build reality]` 本地无工具链；采用字节等同论证（记录于回归文档 §Build source）。
2. `[Rule 1 - environment]` 4K 长播环境阻塞（磁盘满）；按"如实记录不放松门禁"原则标记 blocked 而非通过；计划中的退路（发布 dev.4）涉及对外发布，未单方面执行——留待用户决定（push 后 CI 亦将从新树构建）。

## Verification Results

- 见回归记录总表；三门禁 + PATCH-DRIFT 复绿于提交后。

## Self-Check: PASSED

- Commits `d193173` ancestors of HEAD；记录文件在库。
