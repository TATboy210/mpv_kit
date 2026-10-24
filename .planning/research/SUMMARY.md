# Project Research Summary — milestone v2.0 (GPU-Next Optimization & Full-Rate UHD)

**Date:** 2026-10-24 · 研究方式:本地引擎头文件/代码/快照实证 + 网络社区调研(调研子代理通道受限,按工作流回退路径由编排者内联执行)

## Key Findings

1. **ANGLE 绕过的真相:** Flutter 3.47.6 引擎在 Skia/ANGLE 后端下,两种 GPU 表面类型(`DxgiSharedHandle`/`D3d11Texture2D`)**都经 ANGLE**——切枚举不构成绕过。真正的原生命成路径是 **Impeller(Windows)**;但 Impeller 下共享句柄纹理曾在 3.47.0 崩溃(flutter#191468,PR #191017 修复于 main,3.47.6 未验证)。→ **必须 spike 先行**(REA 逆向本机 flutter_windows.dll + Impeller 冒烟),运行时保留 ANGLE 回退。
2. **media-kit 对比:** 他们整条渲染经 ANGLE(libmpv→ANGLE→共享纹理);我们渲染侧已是自有 Vulkan 后端,仅合成侧经 ANGLE——v2 把合成侧原生化后整链路无 ANGLE,架构领先可保持。共享句柄生命周期/无 fence/驱动差异是两者共同的坑。
3. **gpu-next 社区反馈:** 最相关的是 [#17258](https://github.com/mpv-player/mpv/issues/17258)(2026-01,Vulkan 毛刺 + seek 后画面冻结);Win11 卡顿类(#15196)属显示栈(MPO/HAGS)交互,以 HUD 观测 + 文档化应对。用户提供的 mpv-master 快照(未打补丁,vo_gpu_next 差 380 行)是 vendor 推进目标;Phase 5 的 PATCH-DRIFT 门禁使重定基机械可验证。
4. **8K 崩溃修复层:** Player 选项包按帧尺寸缩放 demuxer 队列(第一层、Dart 侧、可测)+ HUD 暴露缓存/内存观测(第二层);不在 native 层硬编码特判。
5. **HUD 与拖拽低风险:** 属性集合已在目录核对(同步/缓存/解码/渲染四组);[desktop_drop 0.7.1](https://pub.dev/packages/desktop_drop)(活跃维护、三平台)承担拖拽,零原生代码。

## Implications for Roadmap

- **构建顺序(依赖推导):** ① mpv-master 重定基(锁定上游点,其余工作基于它)→ ② 8K 队列缩放(独立小改,可与①并行)→ ③ 调试 HUD(早做,为④⑤提供观测)→ ④ Impeller/D3D spike → 依结论实施桥接切换 + quarantine 参数化 → ⑤ 拖拽播放(随时,依赖③的文件打开路径)→ ⑥ 4K/8K 满血验收(基准+长播收口)
- **spike 是桥接阶段的前置门**(P2/P3 陷阱:版本漂移、帧生命周期)——计划阶段应为 spike 设独立小阶段或计划内首任务
- v1 的五道门禁(PATCH-DRIFT/CONSISTENCY/PINS/CHECK-MATRIX/覆盖率)与三平台 integration test 全程把关;重定基触发一致性联动
- 公共 API 兼容优先:桥接/重定基/队列缩放均内部改动;HUD/拖拽在 example;唯一可能的新 API 是合成路径的只读诊断(需求阶段确认)

## Watch Out For(陷阱速览)

- `git apply` 本机假成功 → GNU patch + 门禁(P1)
- Impeller 版本漂移 → spike + 回退 + CI 锁版本(P2)
- 无 fence 生命周期的安全预算按路径实测,勿拍脑袋(P3)
- 8K 修复伤 4K → 三档同测(P4)
- seek-冻结(#17258)重定基后显式回归(P5)

## Sources

- [flutter#191468 — Impeller DXGI shared-handle 外部纹理崩溃](https://github.com/flutter/flutter/issues/191468)
- [media-kit](https://github.com/media-kit/media-kit) · [media_kit_video changelog](https://pub.dev/packages/media_kit_video/changelog)
- [mpv#17258](https://github.com/mpv-player/mpv/issues/17258) · [mpv#15196](https://github.com/mpv-player/mpv/issues/15196) · [mpv#13909](https://github.com/mpv-player/mpv/discussions/13909) · [mpv#10716](https://github.com/mpv-player/mpv/issues/10716) · [mpv#9479](https://github.com/mpv-player/mpv/issues/9479) · [mpv#13792](https://github.com/mpv-player/mpv/issues/13792)
- [desktop_drop](https://pub.dev/packages/desktop_drop) · [super_drag_and_drop(备选)](https://pub.dev/packages/super_drag_and_drop)
- 本地实证:flutter_texture_registrar.h(3.47.6)、mpv_kit_video 桥接源码、用户 mpv-master 快照 diff、v1 的 docs/perf 与 CONCERNS
