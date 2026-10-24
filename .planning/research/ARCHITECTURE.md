# Project Research — ARCHITECTURE (milestone v2.0)

**Dimension:** 架构集成——桥接升级、mpv-master 重定基、8K 内存修复的落点
**Date:** 2026-10-24 · **Method:** 本地代码通读(v1 阶段已完成大部分)+ 快照 diff + media-kit 对比

## 1. 现有桥接的精确扩展点

| 扩展点 | 位置 | v2 用途 |
|--------|------|---------|
| `Interop` 接口 | video_renderer.h:64-87(`vulkan()`/`interopReason()`/`CompositorLatency()`/`FrameReady()`) | 新增"合成路径"概念:同一 Interop 可按引擎后端选择注册类型(Impeller 原生 vs ANGLE 句柄) |
| 纹理注册回调 | windows/mpv_kit_video_plugin.cpp:210-230(当前固定 `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`) | 绕过 ANGLE 的切换点:按 spike 结论选 `D3d11Texture2D` 或保持句柄+Impeller |
| D3D11 纹理创建 | d3d11_interop.cpp:69-88(KMT 共享句柄、自建设备) | 若走同设备裸指针路径需改为在引擎设备上创建(STACK 选项 B) |
| quarantine 预算 | video_renderer.cc:43-44(`CompositorLatency()` clamp 到 [1,4]) | Impeller 原生路径若有 fence/实时回收,可收紧 → 更低延迟 |
| 后端/原因上报 | render_vk get_info(patch 0005)+ Phase 3 的 reason 管道 | 合成路径(ANGLE/Impeller/D3D)纳入 `backend`/`reason`,HUD 展示 |
| 事件通道 | MpvVideoEventKind(resize/renderError/gpuTimeout/deviceLost/softwareFallback) | 新增 compositor 变更事件(向后兼容,unknown 前向解析已有测试) |

## 2. mpv-master 重定基(vendor 推进)

- 现状:vendored = `v0.41.0-1113-gfd9265a905` + 补丁 0001..0008(Phase 5 重生成,PATCH-DRIFT 门禁字节级验证)
- 目标:vendor 推进到用户快照点(或更新 master);重放补丁(0004 历史上需手工重排——UPSTREAM.md 记录了 master 重构点;380 行 vo_gpu_next 差异预示又一次手工重排)
- 工具:Phase 5 的 `tools/check_patches.sh` 直接复用——更新 MPV_VERSION → 脚本失败 → 重放/手工修复补丁 → 门禁转绿,机械可验证
- 风险控制:CI 六目标矩阵 + Phase 6 integration test 在三平台把关;渲染回归用 Phase 4 基准 + 4K 长播对照

## 3. 8K 提交内存耗尽(v1 遗留,docs/perf/2026-10-24-uhd-endurance.md)

修复层选择(自队列所有者推导):
- **第一层(正确):Player 选项包按帧尺寸缩放**——`demuxer-max-bytes=400MiB`/`back=100MiB` 是 1080p 时代的绝对值,8K 一帧 YUV420P ≈124MiB 系统内存,队列 × 解码池 × 633MiB 共享环压爆提交额度。改为 `f(w,h)` 推导(如按 `max(bytes_of_frame × N_frames)`)在 Player 构造时计算——Dart 侧、行为可测、无 API 破坏
- 第二层(观测):HUD 暴露 demuxer-cache-state + 进程 commit 采样,把"优雅压力事件"(OBS 风格)作为后备
- 不在 mpv 队列层硬编码 8K 特判

## 4. media-kit 架构对比

- media-kit Windows:libmpv→**ANGLE**→共享纹理(整条渲染都在 ANGLE);我们:mpv→**自有 Vulkan 后端**→D3D11 共享纹理(仅合成侧经 ANGLE)。我们的渲染侧已领先;v2 把合成侧也原生化后,整链路无 ANGLE
- 他们的问题域(共享句柄生命周期/驱动差异/无 fence)与我们的 quarantine 设计同源;v2 的 Impeller 路径对两者都是前进方向

## 5. 构建顺序建议(依赖推导)

1. **mpv-master 重定基**先行——独立于桥接,锁定上游演化点(否则后续桥接工作基于旧 vendor,重定基后又要重验)
2. **8K 队列缩放**(Dart 侧,独立,小改动)可与 1 并行
3. **HUD**(example 应用,独立)——为 3/4 提供观测面板,宜早
4. **Impeller/D3D spike**(REA + 开关验证)→ 依 spike 结论实施桥接切换 + quarantine 收紧
5. **拖拽播放**(example,任意时点;依赖 HUD 后共享文件打开路径更顺)
6. **4K/8K 满血验收**(基准 + 长播)收尾

## 拖拽与 HUD 的集成

example 应用内:desktop_drop DropTarget 包 MpvVideo;HUD 为 Stack overlay(Widget),读 Player 状态流 + mpv 属性轮询 + 控制器事件流——全部已有 API,零生产代码改动(或仅暴露只读诊断)。
