---
status: testing
phase: 12-renderbackend-seam
source: [12-VERIFICATION.md]
started: 2026-10-27T04:00:31Z
updated: 2026-10-27T04:00:31Z
---

## Current Test

number: 1
name: 决定 SC1 的「part 2 像素探针读到 nonBlackRatio 0.0 的原因」是否算已交付
expected: |
  要么接受「探针本身可信（三方对照证明 toImage 能看到外部纹理，1266x683 表面已解释），d05 在第二个控制器上读到 0.0 属于带数据记录的既有失败、已转待办」；要么要求在 Phase 12 内查明根因
awaiting: user response

## Tests

### 1. 决定 SC1 的「part 2 像素探针读到 nonBlackRatio 0.0 的原因」是否算已交付
expected: 要么接受「探针本身可信、d05 第二控制器读到 0.0 属于带数据记录的既有失败、已转待办（2026-10-27-diagnose-second-controller-first-frame-stall-in-resize-front）」；要么要求在 Phase 12 内查明根因
result: [pending]

### 2. 决定是否需要一次「真正渲染」的 4K 30 分钟（经 RenderBackend 的 Vulkan 路径）
expected: RTX 4060 上 MPV_KIT_BENCH_RENDER=1 MPV_KIT_BENCH_SIZE=3840x2160 MPV_KIT_BENCH_SECONDS=1800 跑完，drops 0、renderErrors 0、deviceLost false，与 Phase 4 同量级；或接受现有记录（Phase 4 命令不渲染，渲染路径最长真机记录 600 s）
result: [pending]

### 3. 决定在 CR-01 修复提交 025bdad 之后是否在 RTX 4060 上重跑回归
expected: 接受「025bdad 只改软件路径与注释、Vulkan 路径未动、托管 CI 15 个 job 全绿、real_plugin_test 已补跑通过」，或在 025bdad 上重跑 4K 与六组 harness
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
