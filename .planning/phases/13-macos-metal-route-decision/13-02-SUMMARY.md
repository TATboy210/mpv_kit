---
phase: 13-macos-metal-route-decision
plan: 02
subsystem: docs-adr
tags: [adr, metal, moltenvk, iosurface, reason-grammar, grounding]
status: complete

requires:
  - phase: 12-renderbackend-seam
    provides: ADR 0004 reason 语法、RenderBackend 缝隙、DefaultCandidates 候选链
  - phase: 13-macos-metal-route-decision
    provides: 13-01 的 via <carrier> 实现与 macos-15 上的真实 INTEGRATION 行（[G19]）
provides:
  - ADR 0005（Status proposed）：三条 macOS 路线八项标准逐格比较、决定 (a)、五条带检查命令的重新评估触发条件
  - ADR 0004 Decision 3 的 `[ " via " carrier ]` 语法后缀、carrier bullet 与 macOS 示例
  - evidence/adr-0005-grounding.txt：19 个 G 记录（命令输出与仓库行号原样摘录）
affects: [13-03, 13-04, 13-05, 13-06, 14-windows-native-d3d11-backend, 16-hwdec]

actuals:
  tokens: 5800
  tasks: 2
  commits: 2
plan_head_before: fc6dec054f322193f023ea3b21e50d24cc0ca066
plan_head_after: af4736b24ddaf754cca37aa2473f7e9323c5e67c

tech-stack:
  added: []
  patterns:
    - "ADR 的每个事实单元格引用 [G<n>]，来源记录与 ADR 分文件存放，由 grep 门强制每个引用可解析"
    - "无法在本项目证明的结论（真机性能、真机 VideoToolbox）一律写 unverified，不引用研究摘要当作验证"

key-files:
  created:
    - docs/adr/0005-macos-metal-route.md
    - .planning/phases/13-macos-metal-route-decision/evidence/adr-0005-grounding.txt
  modified:
    - docs/adr/0004-render-backend-reporting.md

key-decisions:
  - "macOS 保留 MoltenVK→IOSurface（路线 a）；候选链仍为 DefaultCandidates，不新增 macOS 平台候选"
  - "ADR 0005 保持 Status: proposed，由 13-06 在用户确认后改为 accepted"
  - "ADR 0004 的 carrier 只作为 head 的可选后缀追加，按首个 token 解析 api 的约定不变；取设备名的解析方取 ` on ` 与最后一个 ` via ` 之间"

requirements-completed: [MAC-01, MAC-02]

coverage:
  - id: D1
    description: "ADR 0005 含八个二级标题、八行比较表、决定 (a)、五条带 How to check 的触发条件（含 libplacebo tag 检查命令）与验证去向"
    requirement: "MAC-01"
    verification:
      - kind: other
        ref: "13-02-PLAN Task 1 的 automated 检查（标题、八行、libplacebo 命令、via MoltenVK）"
        status: pass
    human_judgment: true
    rationale: "路线决定本身需要用户在 13-06 的检查点确认后才由 proposed 改为 accepted"
  - id: D2
    description: "ADR 0004 Decision 3 追加 via carrier 语法、carrier bullet、macOS 示例并链接 ADR 0005"
    requirement: "MAC-02"
    verification:
      - kind: other
        ref: "13-02-PLAN Task 1 的第二条 automated（四个字符串 grep）；git log -p --grep='(13-02)' 显示 hunk 只在头部 Related 与 Decision 3"
        status: pass
    human_judgment: false
  - id: D3
    description: "grounding 文件 19 个 G 记录，ADR 中全部 19 个 [G<n>] 引用可解析"
    requirement: "MAC-01"
    verification:
      - kind: other
        ref: "13-02-PLAN Task 2 的 automated（引用解析循环、v7.360.1、PL_HANDLE_MTL_TEX）"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-10-27
---

# Phase 13 Plan 02: ADR 0005 macOS Metal 路线与 via carrier 语法 Summary

ADR 0005（proposed）把 macOS 路线定为保留 MoltenVK→IOSurface，并让 ADR 0004 的 reason 语法正式带上 ` via <carrier>`；比较表的每个事实单元格都能追溯到 19 条 G 记录，查不到的写 unverified。

## 做了什么

- **Task 1（tracer）：**
  - 新建 `docs/adr/0005-macos-metal-route.md`：`Status: proposed`、八个逐字二级标题、八行比较表（实施成本、可用渲染器、VideoToolbox 零拷贝、弃用与平台风险、构建与许可证、Flutter 纹理契约、托管 CI 可验证性、上游状态）。
  - 决定 (a)：macOS 不新增候选，链仍是 vulkan/gpu-next → vulkan/gpu → software；VideoToolbox 零拷贝走 mpv 自带的 `hwdec_vt_pl`。
  - 五条重新评估触发条件，每条带 `How to check:`；T1 是 libplacebo 打 tag 发布合入 Metal `pl_gpu`，检查命令列出该 tag 的 `src/` 并找 `metal`。
  - ADR 0004：`Related:` 增加 ADR 0005；Decision 3 的 head 行改为 `head = api " (" renderer ") on " device [ " via " carrier ]`，新增 carrier bullet（`MoltenVK` / driverName / `unknown Vulkan driver`，同 device 清洗），示例块追加 `vulkan (gpu-next) on Apple Paravirtual device via MoltenVK`。
- **Task 2（auto）：**
  - `evidence/adr-0005-grounding.txt` 由脚本从实时仓库文件与实时 `gh api` 查询生成（避免凭记忆填写）：G1 libplacebo 目录、G2/G3 issue #370/#380、G4 mpv `include/mpv`、G5 MoltenVK 固定与最新版本、G6/G7 build.sh 标志、G8 meson 条件、G9 `hwdec_vt_pl.m`、G10 libplacebo `gpu.c` 的 `PL_HANDLE_MTL_TEX` 声明、G11 `metal_interop.mm`、G12 各 render API 的渲染器归属、G13 REQUIREMENTS 排除项、G14/G18 研究来源、G15 Flutter 纹理契约、G16 `-Dcocoa=disabled` 的原因、G17 MoltenVK 许可证、G19 macos-15 真实 INTEGRATION 行。
  - 研究来源的记录（G14、G18）在记录头与 ADR 单元格里都标明是研究级来源，不作为本项目验证过的事实。

## 查询得到的、规划时没有的事实

- libplacebo 最新 tag 已是 v7.387.0（2026-10-25 发布），它的 `src/` 同样没有 `metal`，与 v7.360.1 一致；触发条件 T1 的基线不变，已写入 G1。
- MoltenVK 最新发布仍是 v1.4.2（2026-07-24），与项目固定版本相同；仓库未归档，许可证声明为 Apache-2.0（G5、G17）。
- libplacebo issue #370、#380 与 mpv PR #16818 在查询日（2026-10-27）均为 open、未合入。

## 验证结果

| 检查 | 结果 |
|---|---|
| Task 1 automated（状态行、八标题、八行、libplacebo 命令、via MoltenVK） | 通过 |
| Task 1 automated（ADR 0004 四个串） | 通过 |
| Task 2 automated（19 个不同引用逐个解析、v7.360.1、PL_HANDLE_MTL_TEX） | 通过 |
| Task 2 automated（MAC-F1、Out of Scope、unverified、提交范围） | 通过 |
| ADR 0004 的 hunk 范围 | 只有头部 `Related:` 与 Decision 3（含示例块），Decision 1、2、4、5 未动 |
| 提交范围 | 只含两份 ADR 与 `.planning/` |

## 与计划的偏差

None - plan executed exactly as written.

## 未解决的假设（原样保留）

**MAC-01 edge probe：** 本阶段没有 `-SPEC.md`，确定性 edge probe 对 MAC-01 返回 `unclassified / unresolved`。本计划没有发明比较维度之外的结论：MoltenVK 在真实 Apple GPU 上的性能、Intel Mac 与双 GPU Mac 的行为、IINA 分支 libplacebo Metal 后端的质量都没有证据，保持 unresolved，并在 ADR 中写成 unverified，没有用「backstop」标记为已覆盖。ADR 保持 `proposed`，等待 13-06 的用户确认。

## Known Stubs

无。

## Threat Flags

无新增的信任边界。T-13-05（每格带 G 引用、不可证明者写 unverified、引用可解析门通过）、T-13-06（ADR 0004 只追加可选后缀与一条 bullet）、T-13-SC（只运行只读 `gh api` 查询，未安装任何包）均已落实。

## Self-Check: PASSED

- 文件存在：`docs/adr/0005-macos-metal-route.md`、`docs/adr/0004-render-backend-reporting.md`、`evidence/adr-0005-grounding.txt`。
- 提交存在于 HEAD 的祖先链：074eae2、af4736b。
