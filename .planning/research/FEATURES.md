# Project Research — FEATURES (milestone v2.0)

**Dimension:** 功能盘点——gpu-next 社区 bug 清单、调试 HUD、拖拽播放
**Date:** 2026-10-24 · **Method:** Web 调研(mpv/libplacebo issues)+ 本地快照 diff + 生成目录核对

## 1. gpu-next 社区 bug/反馈清单

| Issue | 症状 | 状态 | 对 mpv_kit(嵌入式 Vulkan 渲染后端)的相关性 |
|-------|------|------|---------------------------------------------|
| [#17258](https://github.com/mpv-player/mpv/issues/17258)(2026-01) | gpu-next+Vulkan 画面毛刺;seek 后画面冻结但音频继续(vo=gpu-next 已默认) | 近期活跃 | **高**——我们是 Vulkan 渲染后端 + 自有渲染线程;seek 冻结类问题需在我们的桥接上验证 |
| [#15196](https://github.com/mpv-player/mpv/issues/15196)(2024-10) | Windows 11 卡顿;社区用 MPO-GPU-FIX(禁 MPO/TDR/HAGS)缓解 | 环境交互 | 中——桌面合成链(MPO/HAGS)与我们的 quarantine 交互;文档化 + HUD 可观测即可诊断 |
| [#10716](https://github.com/mpv-player/mpv/issues/10716) | `video-sync=display-resample` + Vulkan 接近刷新率片源抖动 | 长期 | 低——我们默认 `video-sync=audio`(Phase 4 实测依据);v2 的 FEAT-01(display-sync 回报)才触及 |
| [#9479](https://github.com/mpv-player/mpv/issues/9479) | gpu-next 在部分机器上慢于 vo=gpu | 长期对比 | 低——基准化方向参考 |
| [#13909](https://github.com/mpv-player/mpv/discussions/13909) | Vulkan Video 解码指南/FAQ(FFmpeg 侧已知 bug) | 文档 | 中——我们 hwdec=vulkan 路径(patch 0002)的运维参考 |
| [#13792](https://github.com/mpv-player/mpv/issues/13792) | macOS 双 VO 不流畅 | 历史 | 低(macOS 侧) |

**待办(需求阶段决定取舍):** 在我们的快照升级(重定基)后复测 #17258 类 seek-冻结;HUD 中暴露 `video-sync/display-sync-active/MPO 相关`可观测项。

## 2. mpv-master 快照 diff(用户提供,`C:\Users\35490\Downloads\mpv-master\mpv-master`)

- 快照是**未打补丁的上游 master**(无 `include/mpv/render_vk.h`——该文件由我们的补丁 0001 创建)
- `vo_gpu_next.c`:快照 3012 行 vs vendored 3320 行(含补丁),**380 行差异**——上游 master 在我们 vendored 点之后有实质演化
- `vulkan/context.c` 22 行差异;`gpu/libmpv_gpu.c` 3 行
- **含义:** v2 的"gpu-next 优化升级"= 将 vendor 树推进到该快照(或更新的 master 点)并重定基 0001..0008(Phase 5 的 PATCH-DRIFT 门禁使重定基结果可机械验证)

## 3. 调试 HUD(功能盘点)

参考 mpv 自带 stats.lua 的分组,属性已在 vendored 目录核对(catalog.dart + mpv DOCS):

- **播放/同步:** `time-pos`、`avsync`、`total-avsync-change`、`frame-drop-count`、`decoder-frame-drop-count`、`vo-delayed-frame-count`、`estimated-vf-fps`、`video-sync`、`display-sync-active`、`mistimed-frame-count`、`vsync-ratio`
- **解码/缓存:** `hwdec-current`、`video-params`(w/h/pixelformat)、`demuxer-cache-duration`、`demuxer-cache-state`(完整 map:缓冲/速度/未读包)、`cache-buffering-state`、`demuxer-via-network`
- **渲染(我们自有):** `MpvVideoController.backend/reason`(Phase 3 诚实 reason)、`gpu-shader-cache-dir` 命中、控制器事件流(resize/renderError/gpuTimeout/recovered)
- **音频:** `audio-device`、`ao-volume`、`audio-params`
- HUD 形态:可切换的 overlay(文本面板),1s 轮询 + 事件叠加;复杂度低(纯 example 应用,不触生产 API)

## 4. 拖拽播放

- **首选 [desktop_drop](https://pub.dev/packages/desktop_drop) 0.7.1**(2026-04 发布,活跃维护,Win/Linux/macOS 全支持,per-target 接受)——example 应用直接依赖,DropTarget 包住 MpvVideo,`onDragDone` 取文件路径列表 → `player.open(path)`(首个视频文件);支持多文件/后续可扩展播放列表
- 备选 [super_drag_and_drop](https://pub.dev/packages/super_drag_and_drop)(双向拖拽,更重);原生 Win32 DropTarget(example/windows 已有 droptarget.c 迹象——flutter 模板自带)——无需第三方但跨平台要各写一份。**结论:desktop_drop,零原生代码,复杂度低**

**Sources:** 各 issue 链接如上 · [desktop_drop](https://pub.dev/packages/desktop_drop) · 本地 catalog.dart 核对
