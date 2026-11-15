# Phase 18: 基线与问题验证 - Context

**Gathered:** 2026-11-01（plan-phase 内联确认，未运行 discuss-phase）
**Status:** Ready for planning

<domain>
## Phase Boundary

只测量、不改产品代码：为 dev.4 的依赖体积、运行内存、Dart 事件重复发射与上游泄漏修复状态建立基线，并对 MEM-01..04 的每个候选问题给出 confirmed / not-confirmed 结论（BASE-01..05）。产出 `.planning/phases/18-baseline-and-validation/18-BASELINE.md` 与 `docs/perf/` 下的测量报告。测量脚本一次性使用，不进入 `packages/*/lib`。

</domain>

<decisions>
## Implementation Decisions

### 测量环境
- **D-01:** 唯一真机为本机 Windows x64（Git Bash/MSYS 环境，RTX 4060 Laptop；与 v3.0 的 RTX 4060 证据同一台）。Linux/macOS 内存数据一律写「未测量」，不推断。
- **D-02:** 本机没有 ffmpeg/ffprobe 可执行文件（PATH 中无）；本地 libmpv 位于 `/c/libmpv-dev/mpv/libmpv-2.dll`，dev.4 pinned bundle 位于 `.dart_tool/hooks_runner/shared/mpv_kit_libs/build/v0.1.0-dev.4/`。测量优先使用 dev.4 pinned bundle 的 libmpv（`MPV_KIT_LIBMPV_PATH`），以保证基线对应已发布产物。媒体信息用 libmpv 自身属性（`video-params`、`file-format`、`video-codec`）读取，不依赖 ffprobe。

### 测量样本（用户 2026-11-01 指定）
- **D-03:** 真实编码样本使用用户提供的三个本地文件（不提交、不复制进仓库）：
  - `C:/Users/35490/Downloads/13349743_1920_1080_25fps.mp4`（1080p25，10 MB）
  - `C:/Users/35490/Downloads/12370391_2160_3840_60fps.mp4`（竖屏 2160x3840 60fps，37.6 MB）
  - `C:/Users/35490/Downloads/19204108-uhd_2160_3840_30fps.mp4`（竖屏 2160x3840 30fps，7.1 MB）
- **D-04:** 样本较短，30 分钟测量用 `loop-file=inf` 循环播放；报告需注明循环播放会使 demuxer 缓存在单文件长度内饱和，与长片源行为不同。
- **D-05:** 没有 8K 真实编码样本，本机也无法编码生成。8K 内存曲线沿用既往方法（lavfi 合成源，`docs/perf/2026-10-24-uhd-endurance.md` 与 `2026-10-25-8k-full-rate.md`）测 demuxer 预算与 `demuxer-donate-buffer` 的影响；8K 软件解码 `vd-lavc-threads` 对照写「未测量（无 8K 编码样本）」。`vd-lavc-threads` 对照以 2160x3840 样本在 `hwdec=no` 下进行。
- **D-06:** 注意 2160x3840 的像素数等于 3840x2160；MEM-02 的「超过 4K」触发条件按像素面积判定，因此竖屏 4K 样本属于「等于 4K」而不是「超过 4K」，报告中要显式说明这一点对 MEM-02 结论的影响（例如测出的线程收益是否足以支持把阈值设在 4K 以上）。

### 判定规则
- **D-07:** 每个候选问题的 confirmed / not-confirmed 判定规则须在测量前写入 BASELINE.md（预注册），沿用 Phase 17 的 memory-plateau 规则思想（先写规则后测量）。无法测量的项记为 not-confirmed（原因：未测量）。
- **D-08:** 体积基线用下载的 dev.4 release 资产（六个目标）做静态检查：逐库解包/压缩大小（`tools/bundle_report.sh`）、是否残留 `.symtab`/调试段（llvm-objdump/llvm-nm/`objdump -h` 等，按目标格式选择本机可用工具）。release 资产下载属于读取公开发布物，允许。

### Claude's Discretion
- 测量脚本形式（Dart 脚本 vs bash）、采样间隔、RSS/commit 读取方式（Windows 进程计数器）、报告排版。
- 上游修复核对的检索方法（在 `native/mpv/` 中按补丁内容 grep，而非 git 历史——vendored 树无 git 历史）。

</decisions>

<canonical_refs>
## Canonical References

- `C:\Users\35490\.claude\plans\mpv-kit-v0-1-0-dev-5-witty-lovelace.md` — 已批准的里程碑计划（阶段 0 = 本阶段）
- `.planning/REQUIREMENTS.md` — BASE-01..05 与 MEM-01..04 的准入关系
- `docs/perf/2026-10-24-uhd-endurance.md`, `docs/perf/2026-10-25-8k-full-rate.md` — 既往 4K/8K 测量方法与数据
- `docs/perf/fallback-uhd-regression.md` — Phase 17 memory-plateau 规则与 RTX 会话脚本
- `tools/bundle_report.sh` — 逐库体积报告
- `packages/mpv_kit/test/lifecycle_test.dart` — RSS 采样参考实现
- `packages/mpv_kit/lib/src/player/player.dart` — UHD-01 预算公式（266–313）、默认选项（102–130）
- `packages/mpv_kit/lib/src/ffi/bindings.dart` — 上游泄漏触发路径核对对象
- 上游：mpv #16619（mpv_command_ret/node NULL result 泄漏）、#17737（client-message 发送失败泄漏）、#16260（包装 AVFrame 包缓存超限）、#17889（packet pool GC，已知已包含）、#15099（gpu-next 长时 OOM，open）

</canonical_refs>

<deferred>
## Deferred Ideas

- 8K 真实编码样本的获取（需要 ffmpeg 编码器或用户提供）— 如 MEM-02/03 在 8K 上需要更强证据，在 Phase 19 前再议。

</deferred>

---

*Phase: 18-baseline-and-validation*
*Context gathered: 2026-11-01*
