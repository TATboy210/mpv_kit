---
phase: 13-macos-metal-route-decision
plan: 03
subsystem: macos-route-probe
tags: [macos, pixel-probe, parity, iosurface, hosted-ci-deferred, mac-02]
status: complete

requires:
  - phase: 13-macos-metal-route-decision
    provides: 13-01 的 via MoltenVK reason 与 ci_gate.sh
provides:
  - macos-route workflow（route-probe (macos-15)）：HEAD 插件与 3a5f450 插件的像素探针和 parity 判定
  - 自包含的探针库、真实插件测试、5 个 Dart 单元测试
  - tools/check_route_probe.py：toImage parity、IOSurface 帧 parity、ROUTE-SC2 结论，14 个自检用例
  - macOS 插件私有诊断方法 debugFrameProbe 与 tools/macos_frame_probe.patch
affects: [13-04, 13-05, 13-06]

requirements-completed: [MAC-02]

actuals:
  tokens: 15700
  tasks: 3
  commits: 5
plan_head_before: 8f891c8dfd25665d9ae831e34e3a4ddf645ddf7e
plan_head_after: 206be6657b98d10a05d4df54adda9c4ea1e93c89

tech-stack:
  added: []
  patterns:
    - "同一测试文件复制进 git worktree，比较两棵插件树的读数"
    - "两个像素通道：toImage（容差判定）与插件内 IOSurface 统计（只用 0.01 / 0.5 稳健界）"
    - "先红后绿：自检证据日志 + 单独的 test 提交"

key-files:
  created:
    - .github/workflows/macos-route.yml
    - example/integration_test/macos_route_test.dart
    - example/integration_test/macos_route_probe.dart
    - example/test/macos_route_probe_test.dart
    - tools/check_route_probe.py
    - tools/macos_frame_probe.patch
    - .planning/phases/13-macos-metal-route-decision/evidence/red-local-13-03-parity.log
    - .planning/phases/13-macos-metal-route-decision/evidence/red-local-13-03-frame.log
    - .planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt
  modified:
    - packages/mpv_kit_video/macos/Classes/MpvKitVideoPlugin.mm
    - tools/check_matrix.py
    - .planning/phases/13-macos-metal-route-decision/evidence/ci-runs.txt

key-decisions:
  - "用户决定（2026-10-27）：所有托管 CI 门推迟到全部阶段完成后；本计划不推送、不派发、不轮询任何 run"
  - "parity 阈值（0.02 / 4.0）与 IOSurface 稳健界（0.01 / 0.5）都在任何 CI 运行之前提交，之后不得据结果调整"
  - "自检用例 1 与 3 补入 ROUTE-FRAME 行：缺少 ROUTE-FRAME 记录按计划判为 FAIL，所以不带帧行的日志不再是合法输入"

ci_gates_passed:
  - task: 1
    purpose: "HEAD route probe: bundle identity, via MoltenVK reason, final pixel read; integration-test (macos) success"
    result: "CI-GATE ok (ci_gate.sh of this phase evaluated against the completed runs, 2026-10-28)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041"
  - task: 2
    purpose: "same-runner pre12 reference and toImage parity (ROUTE-PARITY ok head=texture-visible pre12=texture-visible informative=yes)"
    result: "CI-GATE ok (ci_gate.sh of this phase evaluated against the completed runs, 2026-10-28)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041"
  - task: 3
    purpose: "IOSurface second channel, ROUTE-SC2 pixel=proven channel=toImage, unarmed INTEGRATION-SOAK on the same sha"
    result: "CI-GATE ok (ci_gate.sh of this phase evaluated against the completed runs, 2026-10-28)"
    sha: 091228abd70b22fbe2f425fdd1efb75eb8cfcb54
    runs: "native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041"
---

# Phase 13 Plan 03: macOS 路线探针与像素一致性（本地完成，托管 CI 推迟）Summary

新增 `macos-route` workflow 与两个像素通道：同一台 macos-15 runner 上，HEAD 插件与 Phase 12 之前的插件（3a5f450）读同一帧、同一 libmpv bundle，再由 `tools/check_route_probe.py` 判定一致性与 SC2 结论。本计划所有本地检查已通过；所有需要托管 CI 的验证按用户决定推迟，没有推送，也没有任何 workflow 被派发或轮询。

## 做了什么

- **Task 1（tracer）：**
  - `macos_route_probe.dart` 是自包含的纯函数库（只依赖 `dart:typed_data` 与 `package:flutter/painting.dart`）：区域统计、可见性决策表（与 10-08 / 12-02 同序）、探针几何与阈值常量、`routeBundleLibrary`。
  - `macos_route_test.dart`：进程内只有一个 Player 与一个控制器，像素段最先运行；打印 `ROUTE-IDENTITY`（并断言 libmpv 是 `@rpath/mpv.2.framework/mpv.2`，失败时带上全部尝试），对暂停在首帧的 lavfi testsrc2（640x360）做三次相隔 1 s 的 `toImage` 读取，打印 `ROUTE-PIXEL`，最终读数为 `indeterminate` 时失败。所有等待都有上限，配置只走 `--dart-define`。
  - `macos-route.yml`：单个 job `route-probe (macos-15)`，权限 `contents: read`，Flutter 3.47.8，不设任何 libmpv 路径变量，无失败容忍。`tools/check_matrix.py` 增加对它的 continue-on-error 审计（持久守卫，不新增例外）。
- **Task 2（TDD）：**
  - RED：`check_route_probe.py` 先带固定失败的比较函数，6 个自检用例全部失败，日志为 `evidence/red-local-13-03-parity.log`，提交 3ed6e97。
  - GREEN：逐行 `raw_decode` 解析，每个日志取唯一一条 `"final": true` 记录；indeterminate、分类不同、缺少 final、均值或非黑差越界分别 FAIL；两树都不是 `texture-visible` 但分类相同时 `informative=no`。常量 `PARITY_MAX_NONBLACK_DELTA = 0.02`、`PARITY_MAX_MEAN_DELTA = 4.0`。
  - 5 个 Dart 单元测试（全黑、背景绿、控件黑、彩色、越界）本地通过；workflow 增加 `Probe unit tests`、`Parity self-test`、3a5f450 worktree 步骤（断言 40 位 SHA 相等，只复制两份测试文件）与 `Pixel parity`。
- **Task 3（TDD）：**
  - RED：自检增至 14 个用例（用例 7-14），此时没有 ROUTE-FRAME 解析与 SC2 汇总，日志为 `evidence/red-local-13-03-frame.log`，提交 11f1754。
  - GREEN（脚本）：`ROUTE-FRAME-PARITY` 只用两个稳健界 `FRAME_MIN_NONBLACK = 0.01` 与 `FRAME_ROBUST_NONBLACK = 0.5`：两树都 ≥ 0.5 为 `informative=yes`，都 < 0.01 为 `informative=no`（frames-black），其余（一黑一亮或落在 [0.01, 0.5)）为 `FAIL nonblack`；ΔnonBlack 与 ΔmeanMax 只打印、不参与判定。`ROUTE-SC2`：toImage informative → `proven channel=toImage`；否则 IOSurface informative → `proven channel=iosurface`（证明的是交给 Flutter 的帧，合成器采样未被观察）；否则 `not-achieved reason=probe-channels-blind|frames-black`（退出码 0，是结论不是失败；任一 parity FAIL 时不打印 SC2）。
  - 插件：`MpvKitTexture` 增加 `_probeArmed` / `_probeBuffer`（`_mutex` 保护），`copyPixelBuffer` 在 armed 时多保留一份交给 Flutter 的缓冲，未 armed 时只多一次布尔判断；`armFrameProbe` / `readFrameProbe`（只读锁、整帧遍历，只返回聚合统计）；`handleMethodCall:` 的私有方法 `debugFrameProbe {textureId, arm}`；`shutdown` 释放保留的缓冲。不改 `create:`，不进入 Dart 公共 API。
  - `tools/macos_frame_probe.patch` 只含上述诊断改动；workflow 先在 HEAD 上 `git apply --reverse --check`，再正向应用到 pre12 worktree。

**armed 之后读到的统计允许撕裂，只作非黑/近似判断，不可作为精确值。** iosurface 通道的判定只依赖 `FRAME_MIN_NONBLACK = 0.01` 与 `FRAME_ROBUST_NONBLACK = 0.5` 两个稳健界；自检用例 7 证明 6.0 的 meanG 差不会使判定失败。toImage 通道的 0.02 / 4.0 容差不受影响，因为它读的是合成结果，不经过探针保留的缓冲。

## 本地验证结果

| 检查 | 结果 |
|---|---|
| `flutter analyze --fatal-infos`（example，每个任务后） | No issues found |
| `flutter test test/macos_route_probe_test.dart` | 5 个测试全部通过 |
| `python tools/check_route_probe.py --self-test` | Task 2 后 `cases=6`，Task 3 后 `cases=14`，退出 0 |
| RED 证据 | 两份日志非空，均记录实现前自检失败（退出 1） |
| 阈值常量 grep | `PARITY_MAX_MEAN_DELTA = 4.0`、`PARITY_MAX_NONBLACK_DELTA = 0.02`、`FRAME_MIN_NONBLACK = 0.01`、`FRAME_ROBUST_NONBLACK = 0.5` |
| workflow 结构（PyYAML） | runs-on macos-15、名称、`contents: read`、Flutter 3.47.8；无 continue-on-error / `|| true` / `MPV_KIT_LIBMPV_PATH` |
| `python tools/check_matrix.py` | `CHECK-MATRIX: all targets present, no unauthorized continue-on-error`（含 macos-route.yml） |
| `git apply --reverse --check tools/macos_frame_probe.patch` | HEAD 上通过 |
| `git apply --check`（3a5f450 的临时 worktree，用后已删除） | 通过 |
| golden 冻结清单 | 使用 Phase 14 的 `golden-freeze-14.sha256`，5 个文件全部 OK |
| `constants_audit.sh` | `CONSTANTS ok` |
| `packages/mpv_kit/lib` 对 3a5f450 | 无 diff |
| `bash -n ci_gate.sh` | 通过 |

没有 macOS 主机，所以 `MpvKitVideoPlugin.mm` 与 Dart 测试都没有在 macOS 上编译或运行；这一部分只能由推迟的托管 CI 验证（`flutter-plugin` 的 build (macos-15, macos) 与 route-probe）。

## 与计划的偏差

- **推迟（非代码偏差）：** 用户决定把所有托管 CI 门推迟。三个任务各自的 `ci_gate.sh` 命令与证据抽取都没有执行，原样记入 `deferred_ci_gates`，验收项标记 `ci-gate: deferred`。tracer 反馈门（HEAD 探针端到端后再扩展）因此没有真实读数可依据：Task 2 与 Task 3 是在没有 macOS 真实读数的情况下继续的，这是一个已接受的风险，不是证据。
- **推送与证据：** 没有推送；`evidence/route-runs.txt` 只含推迟说明，没有任何 `ROUTE-*` 行；`ci-runs.txt` 追加了两条推迟说明。
- **自检用例调整（Rule 1，设计后果）：** Task 3 的汇总在缺少 `ROUTE-FRAME` 记录时按计划判 FAIL，所以 Task 2 的用例 1 与 3 随之补入帧行；用例 1-6 的判定内容没有变化。
- 阈值、几何、分类规则没有在任何 CI 结果之后改动（也没有任何 CI 结果）。

## 未解决的假设（原样保留）

**MAC-02 edge probe：** `unclassified / unresolved`。本计划只证明首个控制器、暂停首帧、640x360 的一致性；播放中、resize 之后、多控制器下的像素一致性不在此证明，保持 unresolved，没有用「backstop」标记为已覆盖。toImage 能否看到 macOS 外部纹理事先未知：若两树都是 texture-not-composited，结论是「通道看不见」，不是「一致」。`ROUTE-SC2 pixel=not-achieved` 不是通过，由 13-05 写入验证记录、13-06 交给用户裁决。

## 推迟的证据与 MAC-02

- 未 armed 路径不变的间接证据：同一推送 SHA 上 native-verify 的 integration-test (macos) 运行 real_plugin_test（从不调用 debugFrameProbe），其 INTEGRATION 行（reason 以 ` via MoltenVK` 结尾）与 INTEGRATION-SOAK 行（cycles 10、renderErrors 0、deviceLost 0）需以 `unarmed run=<id> sha=<sha> ` 前缀追加到 `evidence/route-runs.txt`。这些行现在不存在，推迟到 CI 运行之后。
- MAC-02 的验收依赖上述推迟的门，所以记入 `requirements-partial`，没有在 REQUIREMENTS.md 勾选。

## Known Stubs

无。

## Threat Flags

无新增信任边界。T-13-08 至 T-13-11、T-13-19、T-13-20 的缓解均在代码中落实：只读权限与无失败容忍、完整 40 位 PRE12_SHA 与断言、阈值常量先于 CI 提交且自检先红后绿、debugFrameProbe 只返回聚合统计且 armed 才保留缓冲、bundle 身份断言。

## 状态文件说明

STATE.md 的全局计划指针属于 Phase 14，没有运行 `state.advance-plan`。工作树中 `.planning/phases/14-windows-native-d3d11-backend/evidence/ci-runs.txt` 有不属于本计划的未提交修改，没有触碰。受保护文件（`.planning/config.json`、`.planning/state.json`、`.planning/tmp/`、`.planning/ui-reviews/`、`engine_repo_embedder.cc`）均未暂存、未修改。

## Self-Check: PASSED

- 文件存在：`.github/workflows/macos-route.yml`、`example/integration_test/macos_route_test.dart`、`example/integration_test/macos_route_probe.dart`、`example/test/macos_route_probe_test.dart`、`tools/check_route_probe.py`、`tools/macos_frame_probe.patch`、`evidence/red-local-13-03-parity.log`、`evidence/red-local-13-03-frame.log`、`evidence/route-runs.txt`。
- 提交存在于 HEAD 祖先链：3fcac3d、3ed6e97、c71c3d9、11f1754、206be66。

## CI backfill (2026-10-28)

The deferred hosted gates were evaluated against the completed milestone runs at feat HEAD 091228abd70b22fbe2f425fdd1efb75eb8cfcb54 (native-verify 40627862148, flutter-plugin 40627862039, macos-route 40627862041; PR #1) with this phase's unmodified `tools/ci_gate.sh` (a gh shim served the cached logs, nothing was dispatched or rerun). All three gates passed; `ROUTE-SC2 pixel=proven channel=toImage` (identical in the two earlier macos-route runs 40617697853 and 40616234145).
Raw lines: `evidence/route-runs.txt`; gate records: `evidence/ci-runs.txt`.
