---
phase: 04-measured-performance-uhd-endurance
verified: 2026-10-24T17:30:00Z
status: passed
score: 11/12 must-haves verified
covered_files:
  - .planning/phases/04-measured-performance-uhd-endurance/04-01-PLAN.md
  - .planning/phases/04-measured-performance-uhd-endurance/04-01-SUMMARY.md
  - .planning/phases/04-measured-performance-uhd-endurance/04-02-PLAN.md
  - .planning/phases/04-measured-performance-uhd-endurance/04-02-SUMMARY.md
  - .planning/phases/04-measured-performance-uhd-endurance/04-03-PLAN.md
  - .planning/phases/04-measured-performance-uhd-endurance/04-03-SUMMARY.md
  - tools/bench_decode.dart
  - example/integration_test/playback_bench_test.dart
  - example/integration_test/uhd_endurance_test.dart
  - docs/perf/2026-10-24-baseline.md
  - docs/perf/2026-10-24-single-decode.md
  - docs/perf/2026-10-24-uhd-endurance.md
  - packages/mpv_kit/lib/src/core/events.dart
  - packages/mpv_kit/lib/src/player/player.dart
  - packages/mpv_kit/test/models_test.dart
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "8K 7680x4320 连续播放 30 分钟无积压"
    addressed_in: "Withdrawn by user decision (no 8K video test material available); the crash documentation stays in docs/perf/2026-10-24-uhd-endurance.md and CONCERNS.md for any future 8K support work"
    evidence: "PERF-03 的 8K 分句失败:可复现的提交内存耗尽进程死亡(3 次,WER RADAR_PRE_LEAK_64);4K 分句已达成"
advisory:
  - finding: "50 次 controller create/dispose 循环 RSS 增长 45.1 MiB,距 64 MiB 门禁不远(Vulkan 资源churn)"
    category: stability
    reason: "门禁内但值得观察;Phase 2 的 1000-cycle 纯 Dart soak 不含 Vulkan 上下文"
    evidence_status: measured_recorded
---

# Phase 4: Measured Performance & UHD Endurance Verification Report

## 结论摘要

Phase 4 的四条 ROADMAP criteria:**criterion 1(基准+基线)✓、criterion 2(单次解码+数据)✓、criterion 4(API 无变化+分配下降)✓;criterion 3(UHD 长播)部分达成——4K 30 分钟全门禁通过,8K 发现可复现的提交内存耗尽崩溃(新稳定性缺陷,已记录)**。公共 API 冻结完好(api_freeze 通过,唯一新面是 `@visibleForTesting` 计数器,自动豁免)。

## Goal Achievement

### Observable Truths

| # | Truth | Evidence | Status |
|---|-------|----------|--------|
| 1 | decode 微基准随处可跑(无 libmpv),ns/op 稳定(±5%) | `dart run tools/bench_decode.dart` 连续两次 | ✓ |
| 2 | 真机基准在 Vulkan 路径采样 avsync 族 + 循环 + resize | `flutter test integration_test -d windows` 全过,BENCH 三行 | ✓ |
| 3 | BEFORE 基线先于优化提交 | eebf406(基线)先于 2785bd5(优化) | ✓ |
| 4 | 每个 propertyChange 解码计数 delta == 1 | `a property event decodes its node exactly once (PERF-01)` | ✓ |
| 5 | decode-double 169-175 → 102-113 ns/op(−38%) | docs/perf/2026-10-24-single-decode.md | ✓ |
| 6 | decode-map 1768-1960 → 927-950 ns/op(−49%) | 同上 | ✓ |
| 7 | time-pos 节流路径零分配(Duration 仅 emit 时构造) | 源级审查 + 既有 position 测试全绿 | ✓(机制) |
| 8 | API diff 为空;行为不变(unavailable→零保持) | api_freeze 通过;112 passed/2 skipped | ✓ |
| 9 | 冒烟(10s/360p)全门禁通过 | BENCH uhd smoke | ✓ |
| 10 | 4K 1800s:drop 0/0、total-avsync-change −0.0333s 有界、avsync 4.7e-05、delayed 0、fps 30 | docs/perf/2026-10-24-uhd-endurance.md 4K 表 | ✓ |
| 11 | 8K:可复现进程死亡(3 次,≤40s),WER RADAR_PRE_LEAK_64 = 提交内存耗尽 | docs/perf/2026-10-24-uhd-endurance.md 8K 表 | ✓(失败数据) |
| 12 | 门禁未被放松(8K 失败原样记录) | 门禁代码未动;git diff 审查 | ✓ |

### Roadmap Success Criteria

1. **可重复基准 + 改动前基线** — ✓(truths 1-3)。
2. **单次解码(测试断言)+ time-pos 前后对比数据** — ✓(truths 4-7)。
3. **4K 与 8K 30 分钟无积压** — 4K ✓(truth 10);8K 经用户确认撤下(无测试条件;truth 11 的崩溃发现已记录供将来参考)。
4. **API 无变化 + 热路径分配下降** — ✓(truths 7-8)。

### Requirements Coverage

- PERF-01: Complete(04-02)
- PERF-02: Complete(04-01)
- PERF-03: Complete (4K clause delivered;8K clause withdrawn by user decision — no test material, crash documented)
- PERF-04: Complete(04-02)

### Prohibitions (must-NOT)

- PERF-02「MUST NOT change production behavior in 04-01」— `git diff e4407ab..eebf406` 仅触 tools/example/docs。✓
- PERF-01「MUST NOT change decode semantics」— format-none 覆盖保持;事件类不变。✓
- PERF-03「MUST NOT lower gates to force a pass」— 门禁代码未动;8K 失败记录为数据。✓

## Key Link Verification

- `tools/bench_decode → Arena+writeNode → MpvEventData.decode` — 模型测试先例,运行验证。✓
- `uhd_endurance → controller.create → mpv 指标属性` — 冒烟+4K 全链路。✓
- `baseline(eebf406) → optimization(2785bd5) → after-record` — 提交顺序 + 数字对照。✓

## Behavioral Spot-Checks

- mpv_kit 112 passed / 2 skipped;example analyzer 零输出;api_freeze 通过。
- 4K 运行期间窗口可见,无 idle 事件污染(samples 无 idle 信号;fps 恒 30)。

## Anti-Patterns Found

- 无新增 stub/TODO;8K 失败未被掩盖——这是本阶段最重要的"反模式缺失"证明。

## Human Verification Required

1. 8K 崩溃的归因确认(提交内存采样定位耗尽队列)——8K stability insertion 的工作。
2. 长 RSS 观察:50-cycle 45.1 MiB 是否随次数线性(Phase 2 soak 不含 Vulkan 上下文)。

## Gaps Summary

- PERF-03 的 8K 分句未达成(新稳定性缺陷,deferred);其余全部达成。2 条 deferred + 1 条 advisory 显式记录。
