---
phase: 13-macos-metal-route-decision
plan: 04
subsystem: macos-hwdec-probe
tags: [macos, videotoolbox, hwdec, zero-copy, p010, hosted-ci-deferred, hwd-04]
status: complete

requires:
  - phase: 13-macos-metal-route-decision
    provides: 13-03 的 macos-route workflow、单控制器路线探针与像素段
provides:
  - "Generate route samples 步骤：Homebrew ffmpeg 现场生成 h264 / hevc 8-bit / hevc Main10 三个 640x360 样本并打印 ROUTE-SAMPLES 行"
  - example 资源目录 integration_test/route_samples/（只跟踪 README，样本不提交）
  - hwdec 段：软件参照 vs hwdec=videotoolbox，三项零拷贝标记 + VO 截图差异 <= 8.0 的判定表
  - 判定函数与 32 个本地单元测试（先红后绿）
affects: [13-05, 13-06]

requirements-partial: [HWD-04]

actuals:
  tokens: 13200
  tasks: 2
  commits: 4
plan_head_before: 4467389f1b4c9a7b07bed60fee7e6bda5101b190
plan_head_after: 3cd71eca73f8e803042a0306da50660c9f3ceddd

tech-stack:
  added: []
  patterns:
    - "同一个 Player 与控制器内以 loadfile 逐文件选项 hwdec 切换解码器，不改全局 hwdec"
    - "结论由三个独立标记加未回落的 VO 截图决定；不可达必须带非截图来源的失败证据行"

key-files:
  created:
    - example/integration_test/route_samples/README.md
    - .planning/phases/13-macos-metal-route-decision/evidence/red-local-13-04-classify.log
  modified:
    - .github/workflows/macos-route.yml
    - example/pubspec.yaml
    - example/integration_test/macos_route_test.dart
    - example/integration_test/macos_route_probe.dart
    - example/test/macos_route_probe_test.dart
    - .planning/phases/13-macos-metal-route-decision/evidence/ci-runs.txt
    - .planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt

key-decisions:
  - "用户决定（2026-10-27）：所有托管 CI 门推迟；本计划不推送、不派发、不轮询。计划的推送前置条件（push-authorization.txt、13-03 的 ROUTE-PARITY run）因此不适用，也没有被满足，只是被推迟取代"
  - "阈值 routeFrameMaxMeanAbsDiff = 8.0 与结论表在任何 CI 结果之前提交，之后不得据结果调整"
  - "截图模块（prefix screenshot）的行不计入失败证据：回落消息含 falling back，但与解码无关"

deferred_ci_gates:
  - task: 1
    purpose: "样本生成、h264 参照有效、被测结论在允许集合内、pre12 的 hwdec 跳过行、13-03 的 parity 不丢"
    command: |
      CI_GATE_WORKFLOWS="native-verify.yml flutter-plugin.yml macos-route.yml" bash .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh --jobs-success '^route-probe' --log '^route-probe' 'ROUTE-SAMPLES ffmpeg=' --log '^route-probe' 'ROUTE-SAMPLES name=hevc-10bit\.mp4 codec=hevc pix_fmt=yuv420p10le' --log '^route-probe' 'ROUTE-HWDEC-REF \{"tree":"head","sample":"h264-8bit".*"valid":true' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"h264-8bit","hwdec":"videotoolbox","outcome":"(zero-copy|zero-copy-render-unverified|unavailable)","gate":true' --log '^route-probe' 'ROUTE-SECTION \{"tree":"pre12","name":"hwdec","skipped":"not-requested"\}' --log '^route-probe' 'ROUTE-PARITY ok head='
    acceptance: "ci-gate: deferred"
  - task: 2
    purpose: "三个样本的被测结论、10-bit 的 p010 字段、默认列表行、flutterFrame 字段、pre12 无 hwdec 行；随后把 ROUTE- 行追加到 evidence/route-runs.txt"
    command: |
      CI_GATE_WORKFLOWS="native-verify.yml flutter-plugin.yml macos-route.yml" bash .planning/phases/13-macos-metal-route-decision/tools/ci_gate.sh --jobs-success '^route-probe' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"h264-8bit","hwdec":"videotoolbox","outcome":"(zero-copy|zero-copy-render-unverified|unavailable)","gate":true' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"hevc-8bit","hwdec":"videotoolbox","outcome":"(zero-copy|zero-copy-render-unverified|unavailable)","gate":true' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"hevc-10bit","hwdec":"videotoolbox","outcome":"(zero-copy|zero-copy-render-unverified|unavailable)","gate":true.*"p010":(true|false)' --log '^route-probe' 'ROUTE-HWDEC \{"tree":"head","sample":"h264-8bit","hwdec":"default","outcome":"[a-z-]+","gate":false' --log '^route-probe' '"flutterFrame":"(match|mismatch|blind)"' --log '^route-probe' 'ROUTE-HWDEC-REF \{"tree":"head","sample":"hevc-10bit".*"valid":true' --log-absent '^route-probe' 'ROUTE-HWDEC \{"tree":"pre12"' --log '^route-probe' 'ROUTE-PARITY ok head='
    follow_up: |
      R=.planning/phases/13-macos-metal-route-decision/evidence/route-runs.txt; for s in h264-8bit hevc-8bit hevc-10bit; do grep -q "ROUTE-HWDEC {\"tree\":\"head\",\"sample\":\"$s\",\"hwdec\":\"videotoolbox\"" "$R" || { echo "missing $s"; exit 1; }; done && grep -q '"hwdec":"default"' "$R"
    acceptance: "ci-gate: deferred"
---

# Phase 13 Plan 04: VideoToolbox 零拷贝探针（本地完成，托管 CI 推迟）Summary

在 13-03 的单控制器路线探针里加入 hwdec 段：同一个 Player 与控制器，对 CI 现场生成的三个样本先以 `hwdec=no` 跑软件参照，再以 `hwdec=videotoolbox` 跑被测，按三项零拷贝标记与 VO 截图对照给出结论。所有本地检查通过；任何需要 macos-15 runner 的验证按用户决定推迟，没有推送，也没有 workflow 被派发或轮询。

## 做了什么

- **Task 1（tracer，4305699）：**
  - `Generate route samples`：`brew install ffmpeg`，要求 libx264/libx265 编码器，生成 `h264-8bit.mp4`、`hevc-8bit.mp4`、`hevc-10bit.mp4`（yuv420p10le、Main10），用 ffprobe 断言 codec/pix_fmt 与 <= 1 MiB，打印 `ROUTE-SAMPLES` 行；HEAD 探针 `MPV_KIT_ROUTE_SECTIONS=pixel,hwdec`，pre12 仍为 `pixel`。
  - `example/pubspec.yaml` 增加资源目录 `integration_test/route_samples/`；目录里只有 README，样本不提交（`git ls-files '*.mp4'` 为空）。
  - `macos_route_probe.dart`：`routeFrameMaxMeanAbsDiff = 8.0`、`routeBgr0Stats`、`routeBgr0MeanAbsDiff`、`RouteFrameCheck`、`routeScreenshotCheck`、`routeHwdecOutcome`、`routeGatedOutcomesAllowed`、证据正则。
  - `macos_route_test.dart`：hwdec 段复用同一 Player 与控制器，样本经 AssetManifest 与 rootBundle 复制到沙盒临时目录，逐文件选项 `hwdec` 打开、暂停在首帧，读 `hwdec-current`、`hwdec-interop`、`video-params/pixelformat`、`hw-pixelformat` 与 `screenshot-raw`，打印 `ROUTE-HWDEC-REF`、`ROUTE-HWDEC-LOG`、`ROUTE-HWDEC`，并对 gate:true 行数做断言。
- **Task 2（TDD，b1ccb4b 红、78a67d5 绿）：**
  - RED：判定表、默认列表与 Flutter 纹理通道的测试先于实现提交，`evidence/red-local-13-04-classify.log` 记录 `routeFlutterFrame` 等函数不存在导致编译失败（exit=1）。
  - GREEN：默认列表规则（软件解码结论为 `software`）、`routeFlutterFrame`（match / mismatch / blind）、`routeRgbaRegion` 与 `routeRgbaMeanAbsDiff`；测试扩到三个样本，h264 额外跑一次默认列表（gate:false，只记录），每个被测行带 `flutterFrame`，参照行带 `textureVisibility`，10-bit 行带 `p010`，段末断言 gate:true 行数等于 3。
- 3cd71ec：evidence/ci-runs.txt 与 route-runs.txt 追加推迟说明，没有编造任何 run ID 或 ROUTE-* 行。

## 本地验证结果

| 检查 | 结果 |
|---|---|
| `flutter analyze --fatal-infos`（example） | No issues found |
| `flutter test test/macos_route_probe_test.dart` | 32 个测试全部通过（含 13-03 的 5 个） |
| RED 证据日志 | 非空，记录实现前编译失败（exit=1） |
| pubspec 资源项 / README / 无提交的 .mp4 / workflow 关键字 / 无 continue-on-error 与 `\|\| true` | 全部满足 |
| workflow YAML 解析、`tools/check_matrix.py` | 通过 |
| `check_route_probe.py --self-test` | cases=14 |
| golden 冻结清单（Phase 14 的 golden-freeze-14.sha256） | 5 个文件全部 OK |

没有 macOS 主机：Dart 集成测试没有在 macOS 上编译或运行（只做了 analyze），workflow 的 ffmpeg 步骤没有在 runner 上执行。tracer 反馈门（HEAD 端到端后再扩展）因此没有真实读数，Task 2 在没有 macOS 读数的情况下继续，这是已接受的风险，不是证据。

## 与计划的偏差

- **推迟（非代码偏差）：** 用户决定推迟所有托管 CI 门。两个任务各自的 `ci_gate.sh` 命令与 route-runs.txt 抽取都没有执行，原样记入 `deferred_ci_gates`，验收项标记 `ci-gate: deferred`。Task 1 的 precondition（push-authorization.txt 与 13-03 的 ROUTE-PARITY run 成功）没有被满足，而是被 CI 推迟取代：本计划不推送。
- **[Rule 1 - 设计后果] 失败证据排除：** 计划写作「prefix 不是 screenshot」。回落消息的 prefix 确实是 `screenshot`（`mp_log_new(..., "screenshot")`），所以按计划即可，没有额外文本过滤。
- **[Rule 1] 判定表字面化：** `hwdec-current == videotoolbox` 且 pixelformat 为 `videotoolbox` 但缺少 `hw-pixelformat` 时，按计划字面进入 `unexpected`（不是 copy-back）；`hw-pixelformat` 为空串视作不存在。
- 没有改动任何阈值、判定表或 libmpv bundle；`dart format` 误改的 7 个无关文件已用 `git checkout -- <file>` 逐个还原，未提交。

## 未解决的假设（原样保留）

**HWD-04 edge probe：** `unclassified / unresolved`。本计划只覆盖三个 640x360 暂停首帧样本；播放中的持续零拷贝、4K、HDR 元数据、多会话并发（Pitfall 14：VM 上并发会话失败）、`hwdec-image-format` 变体都不在此证明，保持 unresolved，没有用「backstop」标记为已覆盖。托管 macos-15 是 Apple Silicon VM，进程内分不清 Apple 硬件解码器与 VideoToolbox 内部软件解码器；即使将来得到 `zero-copy`，证明的也是互操作链（CVPixelBuffer → MTLTexture → VkImage → libplacebo），不是 Apple 媒体引擎，真机结论一律「未验证」。被测 libmpv 是钩子 bundle v0.1.0-dev.3，不是当前 vendored 树的 verify-tier 构建（13-05 写入验证记录）。

## 推迟的证据与 HWD-04

HWD-04 现在没有任何托管 VM 读数：既没有零拷贝结论，也没有带证据的不可达结论。因此记入 `requirements-partial`，没有在 REQUIREMENTS.md 勾选。

## Known Stubs

无。

## Threat Flags

无新增信任边界。T-13-12（三项标记加未回落截图、不可达需非截图失败证据、判定表先红后绿、gate:true 行数断言）与 T-13-15（资源目录只含 README，样本 <= 1 MiB 断言）的缓解均已在代码中落实；T-13-13、T-13-14 按计划接受；`brew install ffmpeg` 是唯一新增的安装，产物不进入 bundle。

## 状态文件说明

STATE.md 的全局计划指针属于 Phase 14，没有运行 `state.advance-plan` 或 `state.begin-phase`。受保护文件（`.planning/config.json`、`.planning/state.json`、`.planning/tmp/`、`.planning/ui-reviews/`、`engine_repo_embedder.cc`）均未暂存、未修改。

## Self-Check: PASSED

- 文件存在：`example/integration_test/route_samples/README.md`、`example/integration_test/macos_route_test.dart`、`example/integration_test/macos_route_probe.dart`、`example/test/macos_route_probe_test.dart`、`.github/workflows/macos-route.yml`、`evidence/red-local-13-04-classify.log`。
- 提交存在于 HEAD 祖先链：4305699、b1ccb4b、78a67d5、3cd71ec。
