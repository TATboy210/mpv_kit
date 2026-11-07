# mpv_kit v0.1.1 — 简化、去冗与低内存计划

**Status:** P0/P1 complete 2026-11-07（P0 基线 + 内存修复已落地；P2/P3 可选，待用户决定）
**Supersedes:** v3.1（目标 0.1.0-dev.5，Phase 18–22，0/5 已执行）
**Baseline tree:** `89761501b5eb82328932a52f72ef7b7c1a9f7d3f`（分支 `feat/mpv-master-upgrade`）
**Target release:** `0.1.1`（三个 Dart 包 + example）
**Core value:** 以尽可能小的源码改动，换取可验证的稳定性与 4K/8K UHD 长时间满帧播放能力——不崩溃、不泄漏、不积压。

---

## 0. 已锁定决策

| 项 | 决策 |
|---|---|
| 版本路线 | v0.1.1 取代 v3.1；以 dev.10 树为基线；不再执行 Phase 18–22 |
| 内存口径 | **example 应用**，本地 1080p，默认硬解（平台默认 `hwdec` 列表），稳定播放 10 分钟，Windows `Working Set` |
| 内存门禁 | **硬门禁：超过 250 MB 不发布 0.1.1** |
| API | 只增不破；本期预计 **零新增公共 API** |
| 原生渲染 | 允许重构，但必须行为等价、可独立回滚、golden 字节一致 |
| 社区代码 | vendored 树 = 上游 mpv v0.42.0 本体；相关修复/功能已全部包含；**无 verbatim backport** |
| bundle | 保留 GPL-3.0+ full（CD/DVD/BD/UHD 光盘栈 + 网络） |
| 验证 | 本机 Windows x64 为主；Linux/macOS 内存写“未测量”；发布前只跑一次托管 CI |
| 改动风格 | 优先删除/合并/配置，不新增抽象；每项独立提交、可单独回滚 |

---

## 1. 事实基线（已核对，2026-11-07）

### 1.1 代码图谱

- `.codegraph` 已按当前树重建：707 文件 / 18,221 节点 / 48,620 边。
- 旧 `.code-review-graph`（103 MB，快照 `cd47d67`）落后 65 个 Dart/C++ 文件与 252 个 mpv 文件，不再用于决策。
- 建议把 `.codegraph/` 加入 `.gitignore`；旧目录可在确认后删除。

### 1.2 社区/上游

- `native/mpv/MPV_VERSION` = `0.42.0`；`native/patches/UPSTREAM.md` 的 patch-drift 以 tag `b0841e8` 为基。
- #16619、#17737、#16260、packet_pool 增量释放、hwdec surface-pool、#18613 等均已在树内。
- #12566（packet_pool fast quit）上游未合并且上下文漂移，不 backport。
- #15099（长时播放泄漏）、#16658、#18022 上游 open 且无补丁；只作为已知风险观察。
- 0.42 之后 master 仅 3 个提交，均与桌面嵌入的内存/体积/稳定性无关。
- 本地 issue #2（iOS/Android）与“不做移动端”约束冲突，记为 out of scope。

### 1.3 Dart 前端

- 分层 `generated ← ffi ← core ← player`，`video → mpv_kit 公共面`，`libs/hook` 独立；无环、无反向依赖。
- 37 个 `MpvState` 中 33 个 eager 观察；仅 `demuxerCacheState`、`audioDevices` 等少数懒加载。
- `MpvTrack`、`MpvPlaylistEntry`、`MpvChapter`、`MpvVideoParams`、`MpvAudioParams` 无 `==`/`hashCode`，`MpvState` 的 `==` 去重对列表无效。
- `time-pos` 每事件同时进入专用观察流与全局 `_events`；保留现有 100ms/250ms 节流语义。
- 成功路径先拼错误串、每次 drain 新建 `Stopwatch`、`_onPreloaded` 重复解码 `track-list`、`defaultHwdecFor` 调两次。
- 1080p 软解已是 4 线程（实测 82 MiB vs 16 线程 153 MiB），该项已完成。
- 公共 API 冻结由 `api_freeze_test.dart` / `api_surface_test.dart` 约束；`MpvEventData` sealed 层级不可新增子类。

### 1.4 原生后端

- 单渲染线程；帧环 = quarantine + 2 + readyDepth(2)：Windows 8 槽、Linux/macOS 6 槽；1080p BGRA8 每槽 7.91 MiB。
- Windows quarantine = 4（DXGI 3 帧 + 在建帧），不可降；Linux/macOS = 2。
- 唯一可确定超过 250 MB 的组合：软件回退 3 代整环（ring6 ≈ 142 MiB、ring8 ≈ 190 MiB 瞬态）+ 满载 demuxer 上限。
- 1080p demuxer 自动预算 = 199.5/49.9 MiB（上限，非预分配）；本地文件实测常 <25 MiB。
- `hwdec-extra-frames=auto`；Vulkan Video 动态分配，调整无收益；音频缓冲 <1 MiB。
- 已有 strip/gc-sections/gzip -9n；无 LTO；Linux/macOS 的 FFmpeg strip 需复核。
- 可安全简化：release 剔除诊断探针、合并 4 份专用分配模板 / 3 份 `RendererName` / 3 份 `Release` / 2 份 EGL 探测、删除重复 include 与前置声明、macOS `MetalVulkanBackend` 纯转发层。
- 不可动：零拷贝同适配器校验、图像布局/队列族、帧生命周期、纹理注册顺序、线程归属、DRM fd 所有权、`report_swap` 记账。

---

## 2. 分组拆解

### A. 数据结构（Dart）

| ID | 内容 | 结论 | 验证 |
|---|---|---|---|
| A1 | 为 `MpvTrack`、`MpvPlaylistEntry`、`MpvChapter`、`MpvVideoParams`、`MpvAudioParams` 加值相等 + 列表比较，使 `MpvState` 去重生效 | 做（若 P0 显示重复发射有实际影响） | `models_test`、`player_test`、`api_freeze_test`、重复率复测 |
| A2 | `playlist`、`chapters`、`metadata` 改 `late final` 懒观察；`videoParams`/`trackList` 保持 eager（auto-tune/UI 依赖） | 做（仅这几个） | `player_test`、状态初值/事件测试、1080p 内存 |
| A3 | `MpvEventData` sealed 19 子类、枚举值 | 不做：冻结 | — |
| A4 | 模型 `raw` map | 不做：删除即破坏 API | — |
| A5 | 成功路径错误串惰性化、drain `Stopwatch` 复用、`_onPreloaded` 去重解码、`defaultHwdecFor` 单次调用 | 做（内部实现） | `mpv_test`、`player_test`、生命周期测试 |

### B. 接口（Dart 公共面）

- 公共 API 只增不破；本期零新增。
- `demuxerCacheState`、`eventQueueOverflows`、`autoTuneDemuxer`、1080p/4K 线程上限已在 dev.10，不重复实现。
- 方法通道协议不变；若原生改动需要新键，Dart/原生成对改并加测试。
- 不新增 `MpvEventData` 子类、`MpvVideoEventKind`/`MpvVideoBackend` 值。
- 不删除 `Mpv.handle`/`Mpv.bindings`、`@Deprecated forceSoftware` 或任何已发布签名。

### C. 前端（Dart/Flutter 消费层）

- 只做 P0 证实的项；不做“看起来更整洁”的重写。
- 不改变 `time-pos` 节流、`MpvState` sync broadcast、`ShutdownEvent` 重置、位置跳变直通语义。
- 不把内部 helper 暴露为新公共接口。

### D. 后端（原生渲染 + libmpv/构建）

| ID | 内容 | 风险 | 验证 |
|---|---|---|---|
| D1 | release 编译期剔除诊断探针（Windows pickup/Describe、D3D11 注入、macOS `debugFrameProbe`、renderer probe） | 低 | `meson test`、backend soak、real plugin |
| D2 | 合并重复分配模板、`RendererName`、`Release`、EGL 探测；删重复 include/前置声明；macOS `MetalVulkanBackend` 纯转发层 | 低-中 | golden 字节一致、bind/chain/fault/swap 测试 |
| D3 | 仅当 P0 >250 MB：`readyDepth 2→1` 或 ring 深度下调；软件回退代数仅在必要时动 | 中-高 | soak_memory + pixel probe + 真机；Windows quarantine 4 不可降 |
| D4 | Linux/macOS FFmpeg strip 复核；LTO/gc-sections；`bundle_report.sh` 逐目标对比 | 低-中 | smoke、ABI 审计、六目标体积 ≤ dev.10 |

---

## 3. 阶段计划

### P0 — 基线与测量（只测量，产品代码 diff = 0）

**目的：** 在改动任何产品代码前，拿到 example + 1080p + 默认硬解的 Working Set 峰值/平台期、内存构成、事件重复率、六目标体积，作为 250 MB 硬门禁与后续准入门槛。

**测量方法：**
1. 构建当前树（mpv 0.42 + GPL full）Windows x64 候选 bundle。本机 Git Bash 无 clang/meson/ninja/cmake/pkg-config/nasm，且无 `C:\msys64`；优先方案是**一次 `workflow_dispatch` 构建**（非频繁 CI），产物用于全期测量；若用户提供 MSYS2 CLANG64 环境则改为本地构建。
2. example 应用 + `C:/Users/35490/Downloads/13349743_1920_1080_25fps.mp4`，默认 `Player` 选项、默认硬解，稳定播放 10 分钟 × 3 次；每 5 s 采样 `ProcessInfo.currentRss`、`demuxer-cache-state`、`hwdec-current`、`vd-lavc-threads`。
3. 同条件 `vo=null` headless 探针（复用 `.planning/tmp/probe_8k.dart`，改 SAMPLE/SECONDS）做归因：demuxer/decoder 本体占多少。
4. 软解（`hwdec=no`）仅作信息项，不作门禁；若远高于硬解，记录为已知回退成本。
5. 60 s 播放期间统计 `videoParams`、`audioParams`、`trackList`、playlist、chapters 的发射次数与重复值比例。
6. dev.10 六目标 bundle 体积（解包/压缩）+ strip/symbol 审计；若 dev.10 无 release 资产，用 P0 构建产物 + `tools/bundle_report.sh`。

**产出：** `.planning/v0.1.1/BASELINE.md` + `docs/perf/2026-11-XX-1080p-memory.md`。

**门禁：**
- example 1080p 峰值/平台期 ≤ 250 MB → 内存项关闭，P2 只做等价简化。
- > 250 MB → 输出构成表（Flutter 引擎 / GPU 驱动 / 解码 / demuxer / 帧环 / Dart），只对占比最高的可控项进入 P1/P2。

**结果：** dev.9（mpv 0.41）峰值 233.3 MiB；0.42 GPL full 修复前峰值
294.1 MiB（120/120 次 ≥250 MB）；修复后 234.0 MiB（0/120 次 ≥250 MB）。
headless 对照显示 0.42 与 dev.9 的 demuxer/解码内存相同（338.4 vs 339.2 MiB，
`fw-bytes` <10 MB），增量在 Vulkan 零拷贝渲染路径。详见 `BASELINE.md`。

### P1 — 内存修复（已完成）

**P0 结论：** A1（值相等/去重）、A2（懒观察）、A5（内部去冗）在 1080p
本地播放中不是内存主因：60 秒仅 `tracks` 出现 1 次等值重复，`videoParams`
0 次；因此本里程碑**不实施**这些推测性改动。

**实际修复：** 在既有 `on_preloaded` 文件级调参中，对 ≤1080p 视频把
`hwdec-extra-frames` 从 mpv 0.42 的 `auto` 收到 `2`；>1080p 保持 `auto`；
用户显式设置或运行时修改永不覆盖。完整 example + 1080p + 默认硬解
10 分钟 Working Set 峰值 294.1 → 234.0 MiB，0/120 次 ≥250 MB。
- 测试：`player_test.dart` 新增 1080p→2、4K→auto、用户值不变三例。
- 复测：`dart test packages/mpv_kit` 164 passed / 2 skipped；
  `flutter test packages/mpv_kit_video` 36 passed；`mpv_kit_libs` 27 passed；
  三个包 `analyze --fatal-infos` 均无问题。

### P2 — 后端等价简化（已完成：安全子集）

**已完成：**
- 三份完全相同的 `RendererName` 合并为 `video_renderer.cc::ActiveRendererName`
  （`render_backend.h` 只声明，避免把 Vulkan 头带进所有编译单元）。
- 删除 `d3d11_interop.cpp` 重复的 `#include "d3d11_backend.h"`。
- 删除 `video_renderer.h` 冗余的 `class VulkanInterop;` 前置声明。
- Windows Flutter release 编译通过；0.42 1080p 60 秒回归 213–219 MiB，渲染正常。

**未合并（非真正等价，留待 0.1.2，需 native/CI 验证）：**
- 4 份专用分配模板（Vulkan/D3D11/GL/Metal）：CreateImage 的格式、共享模式、
  external handle 与内存属性不同，抽取公共 helper 风险高。
- 2 份 EGL 探测：`gl_interop.cc` 探测 GLES2 + memory_object（VAAPI），
  `opengl_backend.cc` 创建 GL/GLES3 渲染上下文，职责不同。
- `Release`：Vulkan/D3D11 相同，但 OpenGL 多了 bind/`FreeAllTargets`，
  三份并非同一实现；为两行合并抽象不划算。
- release 诊断探针剔除（D1）：会改变 release 行为/测试钩子，需一次 CI 构建验证；
  本机无 clang/meson。
- macOS `MetalVulkanBackend` 纯转发层：macOS-only，无真机验证。

### P3 — 构建体积（已通过 P3 CI）

- D4；六目标解包与压缩体积均 ≤ dev.10。
- `pe_audit.py --forbid-gpl` / `--forbid-angle`、smoke、ABI 审计保持绿；不改网络/decoder/demuxer/BSF/图形后端。

**已实现并通过 P3 CI（run `42348986527`，六目标全绿）：**
- `package.sh` 在 Linux 打包边界执行 `strip --strip-unneeded lib/*.so*`；
  macOS 在 `codesign` 之前执行 `strip -x lib/*.dylib`。
- 实测（解包 `lib/`，P0 → P3）：
  linux-x64 46.89 → 40.38 MiB（−6.51）；linux-arm64 42.61 → 35.79（−6.82）；
  macos-x64 42.88 → 42.41（−0.47）；macos-arm64 37.64 → 37.17（−0.47）；
  windows-x64/arm64 不变。
- 压缩 artifact：linux-x64 −2.83 MB、linux-arm64 −2.89 MB、
  macos-x64/arm64 各 −0.10 MB。
- Linux 的 `.symtab`/debug 已全部清除；macOS `strip -x` 保留 0.62 MiB
  外部符号表（安全，dylib 链接需要）。
- **未做 LTO**：需要完整构建与性能回归，风险/收益不匹配；留待 0.1.2。
- Windows 的 `libaacs.dll`/`libaacs-0.dll` 等重复不是冗余：libbluray 通过
  bare name `dlopen`，`package.sh` 显式复制为别名；不删除。

### P4 — API/文档/CHANGELOG

- 零新增 API；记录 250 MB 结果、#15099 已知风险、Linux/macOS 未测量。
- 更新 `packages/*/CHANGELOG.md`、版本一致性检查、`README` 内存/体积说明。

### P5 — 发布（每次对外动作需用户明确批准）

- 发布前只跑一次托管 CI（native-verify + sanitizers + flutter-plugin + release 构建）。
- 版本号 `0.1.1`；GitHub Release + `tools/pin_bundles.dart`；pub.dev 顺序 `mpv_kit → mpv_kit_libs → mpv_kit_video`。
- **硬门禁：example 1080p Working Set < 250 MB；否则不发布。**

---

## 4. 验证矩阵

| 检查 | 频率 | 通过条件 |
|---|---|---|
| `dart test`（packages/mpv_kit） | 每个 Dart 改动 | 全绿；覆盖率 ≥80% |
| `flutter test`（packages/mpv_kit_video） | 每个 Dart/通道改动 | 全绿 |
| `meson test`（native/tests） | 每个原生改动 | 全绿；goldens 字节一致 |
| `backend_soak_test` + `real_plugin_test` | 每个渲染改动 | 100 轮无泄漏；真实插件可播 |
| 1080p example Working Set | P0、P1/P2 后、发布前 | **<250 MB** |
| `tools/bundle_report.sh` | P3、发布前 | 六目标 ≤ dev.10 |
| `pe_audit.py` | P3、发布前 | GPL/ANGLE 门禁不变 |
| 托管 CI | 发布前一次 | 全绿 |

Linux/macOS 内存：**未测量**（无真机），报告中如实写明，不推断。

---

## 5. 不做清单

- 不新增 sealed 事件子类或枚举值。
- 不改公共签名、不删已发布成员、不删 deprecated 入口。
- 不重写渲染架构，不改零拷贝/帧生命周期/纹理注册/线程归属。
- 不移除 GPL 光盘栈；不裁剪 FFmpeg filter/decoder/demuxer/BSF；不动网络协议。
- 不 backport 未合并的上游 PR（#12566 等）。
- 不做频繁 CI、不每阶段推 PR。
- 不主动新增 API，不为“简化”引入新抽象。
- 不做 `-Os`/`--enable-small`；不做大型架构重写。

---

## 6. 风险与对策

1. **example HUD 占用**：硬门禁按 example 测，HUD/统计行会计入。若超标主要来自示例 UI，可瘦身 example（非库代码），但需用户确认。
2. **Flutter 引擎/GPU 驱动不可控**：若 250 MB 被引擎或驱动占据，按硬门禁**不发布**，给出构成报告并请用户决定。
3. **帧环下调撕裂**：只在 P0 证实超标时做最小项；必须 soak + pixel probe；Windows quarantine 4 保持。
4. **值相等改变发射语义**：用 `models_test`/`player_test` 钉住；不改变 `time-pos` 频率。
5. **懒观察初值时序**：保留 `videoParams`/`trackList` eager；懒观察项要有初值/事件测试。
6. **dev.10 无 release 资产**：P0 需一次 `workflow_dispatch` 构建（或用户提供 MSYS2 环境）。
7. **#15099 长时播放泄漏**：上游无补丁；P0 的 10 分钟测量无法覆盖长时泄漏，发布说明中保留为已知风险。

---

## 7. 参考

- `.planning/codebase/ARCHITECTURE.md`、`CONCERNS.md`、`STRUCTURE.md`（快照 `cd47d67`，仅作背景）
- `.planning/phases/18-baseline-and-validation/18-CONTEXT.md`（测量样本与方法，目标版本已过时）
- `docs/perf/2026-11-02-8k-memory.md`、`docs/perf/2026-10-24-uhd-endurance.md`
- `native/patches/UPSTREAM.md`
- `.codegraph/codegraph.db`（当前树索引）
