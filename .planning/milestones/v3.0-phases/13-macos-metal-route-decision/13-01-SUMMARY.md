---
phase: 13-macos-metal-route-decision
plan: 01
subsystem: macos-video-renderer
tags: [metal, moltenvk, vulkan, reason-reporting, hosted-ci, ci-gate]
status: complete

requires:
  - phase: 12-renderbackend-seam
    provides: RenderBackend 缝隙、Interop::CreateBackend、ADR 0004 reason 语法、Phase 12 ci_gate.sh
provides:
  - macOS 上 Vulkan 胜出时 reason 头写出实际承载驱动（`via MoltenVK`）
  - Phase 13 hosted-CI 门脚本（CI_GATE_WORKFLOWS、按 workflowName 选 run、--log-absent）
  - Phase 13 推送授权记录（evidence/push-authorization.txt）与 CI 记录（evidence/ci-runs.txt）
affects: [13-02, 13-03, 13-04, 13-05, 14-windows-native-d3d11-backend]

actuals:
  tokens: 4300
  tasks: 2
  commits: 3
plan_head_before: 46aa24ddc0a8ca6b47762bc4f94016a2709adff4
plan_head_after: d9d042dacd18747f0f534aa29824cc4abeecf3a5

tech-stack:
  added: []
  patterns:
    - "通过 Interop::CreateBackend 对内置后端做转发包装，只改一个虚函数，不碰共享引擎"
    - "承载驱动名只取自 VkPhysicalDeviceDriverProperties，无法确定时写 unknown Vulkan driver"

key-files:
  created:
    - .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh
    - .planning/phases/13-macos-metal-route-decision/evidence/push-authorization.txt
    - .planning/phases/13-macos-metal-route-decision/evidence/ci-runs.txt
  modified:
    - packages/mpv_kit_video/macos/Classes/metal_interop.h
    - packages/mpv_kit_video/macos/Classes/metal_interop.mm
    - README.md

key-decisions:
  - "用户答复 push-green-only：只向 origin feat/mpv-master-upgrade 快进推送，无 force-push、无其他分支、无故意变红提交"
  - "carrier 在 AcceptDevice 里与既有 vkGetPhysicalDeviceProperties2 同一次调用读出，接受判断逐字不变"
  - "包装后端显式转发 15 个虚函数，含三个有默认实现的 BindThread/UnbindThread/device_failed"

requirements-completed: [MAC-02]
---

# Phase 13 Plan 01: macOS 承载驱动报告（via MoltenVK）Summary

macOS 上 Vulkan 后端胜出时，reason 头现在写出实际加载的 Vulkan 驱动：macos-15 runner 的真实插件 INTEGRATION 行为 `vulkan (gpu-next) on Apple Paravirtual device via MoltenVK`，其他平台与 macOS 行为不变。

## 做了什么

- **Task 1（checkpoint:decision，blocking-human）：** 用户在编排会话中答复 `push-green-only`（2026-10-27T06:51:28Z，当时 HEAD 182a097）。原文与范围写入 `evidence/push-authorization.txt`，该文件的提交（8e2707a）是 ci-runs.txt 第一条记录 SHA（8103beb）的祖先。
- **Task 2（tracer）：**
  - `MetalInterop::AcceptDevice` 把 `VkPhysicalDeviceDriverProperties` 挂在已有的 `VkPhysicalDeviceIDProperties` 之后，仍只调用一次 `vkGetPhysicalDeviceProperties2`；接受判断不变，只在将返回 true 时按设备名记录 carrier（`driverID == VK_DRIVER_ID_MOLTENVK` 写 `MoltenVK`，否则取 `strnlen` 截取的 `driverName`，再否则 `unknown Vulkan driver`）。
  - `MetalInterop::CreateBackend("vulkan")` 仅在 Metal 设备存在时返回 `MetalVulkanBackend`（包装 `CreateVulkanBackend(this)`）；`device_name()` 追加 ` via <carrier>`，其余 14 个虚函数原样转发。其他 api 或无 Metal 时返回 nullptr，走原内置分支与原 trail。
  - `CarrierFor`：同名设备只有一个不同的驱动名时返回它，否则 `unknown Vulkan driver`。
  - README reason bullet 追加 macOS `on <device> via MoltenVK` 一句。
  - `tools/ci_gate.sh`（复制自 Phase 12）：`CI_GATE_WORKFLOWS`、按 `workflowName` 选 run、`--log-absent`、重跑规则登记 `vk-gpu-timeout` golden 抖动。

## 验证结果

| 检查 | 结果 |
|---|---|
| `bash -n ci_gate.sh` + `tools/check_matrix.py` + 三个 grep | 通过（CHECK-MATRIX ok） |
| 源码 grep 断言（驱动属性、包装、三个默认虚函数、README 句子） | 通过 |
| golden 冻结清单 | 通过，使用 Phase 12 的 `golden-freeze.sha256`（Phase 14 的 `golden-freeze-14.sha256` 尚不存在），5 个文件全部 OK |
| `constants_audit.sh` | `CONSTANTS ok` |
| `packages/mpv_kit/lib` 与 API-freeze 测试对 3a5f450 | 无 diff |
| 13-01 提交范围 | 仅允许的文件 |
| 授权先于推送（merge-base） | 通过 |
| 托管 CI，SHA 8103beb | `CI-GATE ok`：native-verify run 40465908724 与 flutter-plugin run 40465908799 均为 success（第 1 次 attempt，无重跑） |

CI 日志里的真实 INTEGRATION 行：

- macos-15：`"backend":"vulkan","reason":"vulkan (gpu-next) on Apple Paravirtual device via MoltenVK"`
- ubuntu-24.04：`"reason":"vulkan (gpu-next) on llvmpipe (LLVM 20.1.2, 256 bits)"`（不以 via 结尾）
- windows-2025：`"backend":"software","reason":"software (sw) on cpu; vulkan/gpu-next unavailable: vkCreateInstance failed; ..."`（不变）
- macos INTEGRATION-SOAK：`cycles 10`、`renderErrors 0`、`deviceLost 0` 由门断言通过；`video_renderer_golden_vk` OK 同样由门断言。

## 与计划的偏差

**1. [Rule 1 - Bug] ci_gate.sh 在 run 未结束时读到空 conclusion**
- **发现于：** 第一次 CI 门调用。`gh run watch` 提前返回，native-verify 的 linux job 仍在运行，conclusion 为空，门报 `fail (workflow conclusion)`。
- **修复：** `watch_run` 在读 conclusion 前轮询 status 直到 `completed`（最多 45 分钟）。该次不是测试失败，也没有重跑任何 workflow。
- **提交：** d9d042d

**2. [Rule 1 - Bug] ci_gate.sh 的数组循环被 bash 当作间接展开**
- **发现于：** 重跑门时 `line 182: ... invalid variable name`。我写的 `${!arr[@]+"${!arr[@]}"}` 写法不对。
- **修复：** 改成 `for ((i = 0; i < ${#arr[@]}; i++))`，`--log` 与 `--log-absent` 两处。
- **提交：** d9d042d

**3. 瞬时网络错误（非偏差）：** 一次 `gh run view --log` 下载 EOF，一次 `git fetch` schannel 握手失败。均未产生结论，重新调用后恢复。ci-runs.txt 末尾有说明行，重复的记录行都对应同一对已完成的 run（attempt 1）。

## 未解决的假设（原样保留）

**MAC-02 edge probe：** 本阶段没有 `-SPEC.md`，确定性 edge probe 对 MAC-02 返回 `unclassified / unresolved`。本计划只证明托管 macos-15 VM（Apple Paravirtual device + 插件自带的 MoltenVK）上的 reason 与行为。多 ICD 开发机上写 `unknown Vulkan driver` 的分支（以及 `CarrierFor` 中同名设备对应多个驱动的分支）没有 CI 环境可演练，保持 unresolved，没有用「backstop」标记为已覆盖。

## Known Stubs

无。

## Threat Flags

无新增的信任边界。T-13-01 至 T-13-04 的缓解均落实：carrier 只来自驱动属性并经 `SanitizeReasonField`；15 个虚函数显式转发；`--log-absent` 与 ci-runs.txt 入账；Task 1 授权先于推送、仅快进。

## 推送记录

本计划把 `9b8acb5..8103beb` 快进推送到 origin `feat/mpv-master-upgrade`。其中包含 Phase 14 的 14 个本地提交（均为 `.planning/` 文档/证据与 `tools/d3d11_probe/d3d11_caps_probe.cpp`；推送前核对过：未改 `.github/workflows/`，无产品代码改动，无工作流引用该 probe）。推送后的 `d9d042d`（ci_gate 修复与 ci-runs 记录，仅 `.planning/`）和本 SUMMARY 提交尚未推送，留给后续计划的推送一并带上。

## Self-Check: PASSED

- 文件存在：`metal_interop.h`、`metal_interop.mm`、`README.md`、`tools/ci_gate.sh`、`evidence/push-authorization.txt`、`evidence/ci-runs.txt`。
- 提交存在于 HEAD 的祖先链：8e2707a、8103beb、d9d042d。
